package main

import (
	"database/sql"
	"encoding/csv"
	"fmt"
	"io"
	"log"
	"os"

	_ "github.com/mattn/go-sqlite3" // Import the SQLite driver
)

func main() {
	if len(os.Args) != 3 {
		log.Fatal("Usage: go run main.go <csv_file> <database_file>")
	}

	csvFileArg := os.Args[1]
	dbFileArg := os.Args[2]

	// Open CSV file
	csvFile, err := os.Open(csvFileArg)
	if err != nil {
		log.Fatal(err)
	}
	defer csvFile.Close()

	// Create CSV reader
	reader := csv.NewReader(csvFile)

	// Open database
	db, err := sql.Open("sqlite3", dbFileArg)
	if err != nil {
		log.Fatal(err)
	}
	defer db.Close()

	// Create the table if it doesn't exist
	_, err = db.Exec(`
        CREATE TABLE IF NOT EXISTS tokens (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            language TEXT,
            token TEXT,
            count INTEGER,
            UNIQUE(language, token)
        )
    `)
	if err != nil {
		log.Fatal(err)
	}

	// Insert data from CSV into database
	for {
		record, err := reader.Read()
		if err == io.EOF {
			break
		}
		if err != nil {
			log.Fatal(err)
		}

		stmt, err := db.Prepare("INSERT INTO tokens (language, token, count) VALUES (?, ?, ?)")
		if err != nil {
			log.Fatal(err)
		}

		_, err = stmt.Exec("English", record[0], record[1])
		if err != nil {
			log.Fatal(err)
		}

		stmt.Close()
	}

	fmt.Println("Data imported successfully!")
}
