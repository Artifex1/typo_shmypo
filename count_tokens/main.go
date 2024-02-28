package main

import (
	"database/sql"
	"fmt"
	"log"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"sync"

	_ "github.com/mattn/go-sqlite3"
	"github.com/schollz/progressbar/v3"
)

func main() {
	// Check for the required argument
	if len(os.Args) != 2 {
		log.Fatal("Please provide a directory path as the first argument")
	}

	// Get the directory path from positional argument
	directoryPath := os.Args[1]

	// Check if the path is a directory
	fileInfo, err := os.Stat(directoryPath)
	if err != nil {
		log.Fatal(err)
	}

	if !fileInfo.IsDir() {
		log.Fatal("Provided path is not a directory")
	}

	// Connect to SQLite database
	db, err := sql.Open("sqlite3", "tokens.db")
	db.SetMaxOpenConns(1)
	if err != nil {
		log.Fatal(err)
	}
	defer db.Close()

	// Create table with ID, language, and token columns, ensuring uniqueness for language-token combinations
	_, err = db.Exec(`CREATE TABLE IF NOT EXISTS tokens (
		id INTEGER PRIMARY KEY AUTOINCREMENT,
		language TEXT,
		token TEXT,
		count INTEGER,
		UNIQUE(language, token)
	)`)
	if err != nil {
		log.Fatal(err)
	}
	_, err = db.Exec("PRAGMA journal_mode = WAL; PRAGMA synchronous = NORMAL;")
	if err != nil {
		log.Fatal(err)
	}

	// Define the regex to match tokens
	wordRegex := regexp.MustCompile(`\b(?:_?)([_a-zA-Z]\w*)`)                 // match the words we want to match
	tokenCaseRegex := regexp.MustCompile(`([A-Z][a-z']+|[a-z']+|[A-Z']{3,})`) // match the cases within the matched words

	errChan := make(chan error)
	var wg sync.WaitGroup

	var totalFiles int

	// Update totalFiles before processing starts
	err = filepath.Walk(directoryPath, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return err
		}

		if filepath.Ext(path) == ".sol" {
			totalFiles++
		}
		return nil
	})
	if err != nil {
		log.Fatal(err)
	}

	fmt.Printf("Files to process: %d\n", totalFiles)
	// Create a progress bar with totalFiles as length
	bar := progressbar.NewOptions(totalFiles,
		progressbar.OptionSetWidth(50),
		progressbar.OptionSetDescription("Processing files"),
		progressbar.OptionSetWriter(os.Stdout),
	)

	fmt.Println("Starting token count...")
	// Recursively process .sol files using transactions
	err = filepath.Walk(directoryPath, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return err
		}

		if filepath.Ext(path) == ".sol" {
			wg.Add(1)
			go func(path string) {
				defer func() {
					wg.Done()
					bar.Add(1)
				}()

				// Read file content
				fileContent, err := os.ReadFile(path)
				if err != nil {
					errChan <- err
					return
				}

				// Apply regex and count matches
				matches := wordRegex.FindAllStringSubmatch(string(fileContent), -1)
				tokenCounts := make(map[string]int)
				for _, match := range matches {
					tokens := tokenCaseRegex.FindAllStringSubmatch(match[1], -1)
					for _, token := range tokens {
						tokenCounts[strings.ToLower(token[1])]++
					}
				}

				tx, err := db.Begin()
				if err != nil {
					tx.Rollback()
					errChan <- err
					return
				}

				// Insert counts into database within the transaction
				for token, count := range tokenCounts {
					_, err := tx.Exec(`
						INSERT OR REPLACE INTO tokens (language, token, count) 
						VALUES (?, ?, COALESCE((SELECT count FROM tokens WHERE language = ? AND token = ?), 0) + ?)
						`, "Solidity", token, "Solidity", token, count)
					if err != nil {
						errChan <- err
						return
					}
				}

				err = tx.Commit()
				if err != nil {
					errChan <- err
					tx.Rollback()
					return
				}
			}(path)
		}
		return nil
	})
	if err != nil {
		log.Fatal(err)
	}

	wg.Wait() // Wait for goroutines to finish
	bar.Finish()

	close(errChan) // Signal end of errors

	if err := <-errChan; err != nil {
		log.Fatal(err)
	}

	fmt.Println("\nAll files processed and token counts stored in tokens.db")
}
