package main

import (
	"bufio"
	"database/sql"
	"fmt"
	"log"
	"maps"
	"os"
	"path/filepath"
	"regexp"
	"strings"

	"github.com/hbollon/go-edlib"
	_ "github.com/mattn/go-sqlite3"
	"github.com/spf13/pflag"
)

func main() {
	paths := handleCLI()

	// connect to DB
	db, err := sql.Open("sqlite3", "tokens.db")
	if err != nil {
		log.Fatal(err)
	}
	defer db.Close()

	// Define the regex to match tokens
	wordRegex := regexp.MustCompile(`\b(?:_?)([_a-zA-Z]\w*)`)                 // match the words we want to match
	tokenCaseRegex := regexp.MustCompile(`([A-Z][a-z']+|[a-z']+|[A-Z']{3,})`) // match the cases within the matched words

	// mapping for full word check
	tokenMap := make(map[string]bool)
	maps.Copy(tokenMap, getTokensFromDB(db, "Solidity", 1e-8))
	maps.Copy(tokenMap, getTokensFromDB(db, "English", 0))

	// mapping for compound word check
	compoundMap := make(map[string]bool)
	maps.Copy(compoundMap, getTokensFromDB(db, "Solidity", 1e-3))
	maps.Copy(compoundMap, getTokensFromDB(db, "English", 0))

	// get a word list for edit distance and typo fix suggestion
	wordSuggestionList := make([]string, len(compoundMap))
	i := 0
	for k := range compoundMap {
		wordSuggestionList[i] = k
		i++
	}

	// Process the paths slice
	for _, file := range paths {
		processFile(file, wordRegex, tokenCaseRegex, tokenMap, compoundMap, wordSuggestionList)
	}
}

func processFile(path string, wordRegex *regexp.Regexp, tokenRegex *regexp.Regexp, tokenMap map[string]bool, compoundMap map[string]bool, wordList []string) {
	file, err := os.Open(path)
	if err != nil {
		fmt.Println(err)
		return
	}
	defer file.Close()

	lineNo := 0

	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		line := scanner.Text()
		lineNo++

		words := wordRegex.FindAllStringSubmatch(line, -1)
		for _, word := range words {
			tokens := tokenRegex.FindAllStringSubmatch(word[1], -1)
			for _, token := range tokens {
				// check whether the full word is part of the map
				if !tokenMap[strings.ToLower(token[1])] {
					// check whether the word in compounds is part of the map
					_, success := parseCompoundWords(strings.ToLower(token[1]), compoundMap)
					// also failed to build compound word, a typo then
					if !success {
						fmt.Printf("Typo in %s:%d: %s", path, lineNo, token[1])

						// find most similar words in word list for fix suggestion
						res, err := edlib.FuzzySearchSetThreshold(token[1], wordList, 3, 0.7, edlib.OSADamerauLevenshtein)
						if err != nil {
							fmt.Println(err)
						} else if strings.Join(res, "") == "" {
							fmt.Printf("\n")
						} else {
							fmt.Printf("  =>  %s\n", strings.Join(res, " "))
						}
					}
				}
			}
		}
	}
}

func parseCompoundWords(word string, knownWords map[string]bool) ([]string, bool) {
	// Base case: empty string or only a known word with at least 2 characters
	if word == "" || (len(word) >= 2 && knownWords[word]) {
		return []string{word}, true
	}

	// Recursive case: check potential tokens with length at least 2 and their remaining parts
	for i := 2; i < len(word); i++ {
		candidate := word[:i]
		if len(candidate) >= 2 && knownWords[candidate] {
			remaining, success := parseCompoundWords(word[i:], knownWords)
			if success {
				return append([]string{candidate}, remaining...), true
			}
		}
	}

	// No successful split found
	return nil, false
}

func getTokensFromDB(db *sql.DB, language string, minFrequency float32) map[string]bool {
	query := `
		WITH LanguageTotal AS (
			SELECT language, SUM(count) as total_count
			FROM tokens
			GROUP BY language
		)
		SELECT t.language, t.token, t.count, t.count / CAST(lt.total_count as FLOAT) as relative_count
		FROM tokens as t
		JOIN LanguageTotal lt ON t.language = lt.language
		WHERE t.language = ? AND relative_count > ?
		ORDER BY relative_count DESC;	
    `

	rows, err := db.Query(query, language, minFrequency)
	if err != nil {
		log.Fatal(err)
	}
	defer rows.Close()

	// Create a map to store tokens
	tokensMap := make(map[string]bool)

	for rows.Next() {
		var language string
		var token string
		var count int
		var relativeCount float32

		err = rows.Scan(&language, &token, &count, &relativeCount)
		if err != nil {
			log.Fatal(err)
		}

		// Add the token to the map
		tokensMap[token] = true
	}

	err = rows.Err()
	if err != nil {
		log.Fatal(err)
	}

	return tokensMap
}

func handleCLI() []string {
	scopeFile := pflag.StringP("scope", "s", "", "File containing additional file paths")
	pflag.Parse()

	basePath := pflag.Args()[0]

	// Ensure positional argument is provided
	if basePath == "" {
		fmt.Println("Missing positional argument: directory or file")
		os.Exit(1)
	}
	basePathInfo, err := os.Stat(basePath)
	if err != nil {
		fmt.Println("Error accessing positional argument:", err)
		os.Exit(1)
	}

	paths := []string{}

	// Read paths from scope file if provided
	if *scopeFile != "" {
		if !basePathInfo.IsDir() {
			fmt.Println("Positional argument must be a directory when --scope is used")
			os.Exit(1)
		}

		scopeBytes, err := os.ReadFile(*scopeFile)
		if err != nil {
			fmt.Println("Error reading scope file:", err)
			os.Exit(1)
		}

		scopePaths := strings.Split(string(scopeBytes), "\n")
		for _, scopePath := range scopePaths {
			scopePath = strings.TrimSpace(scopePath)
			if scopePath != "" {
				paths = append(paths, filepath.Join(basePath, scopePath))
			}
		}
	} else {
		if basePathInfo.IsDir() {
			err = filepath.Walk(basePath, func(path string, info os.FileInfo, err error) error {
				if err != nil {
					return err
				}
				if !info.IsDir() {
					paths = append(paths, path)
				}
				return nil
			})
			if err != nil {
				fmt.Println("Error walking folder:", err)
				os.Exit(1)
			}
		} else {
			paths = append(paths, basePath)
		}
	}

	return paths
}
