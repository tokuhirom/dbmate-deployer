package main

import (
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
)

func main() {
	http.HandleFunc("/webhook", func(w http.ResponseWriter, r *http.Request) {
		// Read request body
		body, err := io.ReadAll(r.Body)
		if err != nil {
			log.Printf("Error reading body: %v", err)
			http.Error(w, "Error reading body", http.StatusBadRequest)
			return
		}
		defer r.Body.Close()

		// Parse JSON to pretty print
		var payload map[string]interface{}
		if err := json.Unmarshal(body, &payload); err != nil {
			log.Printf("Error parsing JSON: %v", err)
			http.Error(w, "Error parsing JSON", http.StatusBadRequest)
			return
		}

		// Print request details
		fmt.Println("=== Webhook Request Received ===")
		fmt.Printf("Method: %s\n", r.Method)
		fmt.Printf("Path: %s\n", r.URL.Path)
		fmt.Printf("Content-Type: %s\n", r.Header.Get("Content-Type"))
		fmt.Println("\n=== Payload ===")
		prettyJSON, _ := json.MarshalIndent(payload, "", "  ")
		fmt.Println(string(prettyJSON))
		fmt.Println("\n✓ Webhook processed successfully")

		// Respond with success
		w.WriteHeader(http.StatusOK)
		w.Write([]byte("ok"))
	})

	port := os.Getenv("PORT")
	if port == "" {
		port = "9876"
	}

	log.Printf("Webhook logger starting on port %s", port)
	log.Fatal(http.ListenAndServe(":"+port, nil))
}
