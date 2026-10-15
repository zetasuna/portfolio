package main

import (
	"log"
	"net/http"
	"time"

	"github.com/zetasuna/portfolio/internal/handlers"
)

func main() {
	mux := http.NewServeMux()
	mux.HandleFunc("/healthz", handlers.Health)

	server := &http.Server{
		Addr:              ":8080",
		Handler:           mux,
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       10 * time.Second,
		WriteTimeout:      15 * time.Second,
		IdleTimeout:       60 * time.Second,
	}

	log.Printf("HTTP server listening on %s", server.Addr)

	if err := server.ListenAndServe(); err != nil &&
		err != http.ErrServerClosed {
		log.Fatal(err)
	}
}
