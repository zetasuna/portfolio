package main

import (
	"context"
	"log"
	"net/http"
	"time"

	"github.com/zetasuna/portfolio/internal/database"
	"github.com/zetasuna/portfolio/internal/handlers"
	"github.com/zetasuna/portfolio/internal/repository"
	"github.com/zetasuna/portfolio/internal/service"
)

func main() {
	ctx, cancel := context.WithTimeout(
		context.Background(),
		60*time.Second,
	)
	defer cancel()

	pool, err := database.ConnectWithRetry(ctx)
	if err != nil {
		log.Fatalf("database connection failed: %v", err)
	}
	defer pool.Close()

	log.Println("PostgreSQL connection established")

	repo := repository.NewRepository(pool)
	portfolioService := service.NewPortfolioService(repo)
	portfolioHandler := handlers.NewPortfolioHandler(portfolioService)

	mux := http.NewServeMux()
	mux.HandleFunc("/healthz", handlers.Health)
	mux.Handle("/readyz", handlers.Readiness(pool))
	mux.HandleFunc("/api/items", portfolioHandler.Collection)
	mux.HandleFunc("/api/items/{id}", portfolioHandler.Item)

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
