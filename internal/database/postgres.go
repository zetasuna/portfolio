// Package database
package database

import (
	"context"
	"fmt"
	"os"
	"strconv"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

func Connect(ctx context.Context) (*pgxpool.Pool, error) {
	host := os.Getenv("DB_HOST")
	port := os.Getenv("DB_PORT")
	name := os.Getenv("DB_NAME")
	user := os.Getenv("DB_USER")
	password := os.Getenv("DB_PASSWORD")
	sslmode := os.Getenv("DB_SSLMODE")

	if host == "" || port == "" || name == "" ||
		user == "" || password == "" {
		return nil, fmt.Errorf("database configuration is incomplete")
	}

	if sslmode == "" {
		sslmode = "disable"
	}

	portNumber, err := strconv.Atoi(port)
	if err != nil || portNumber < 1 || portNumber > 65535 {
		return nil, fmt.Errorf("invalid DB_PORT")
	}

	config, err := pgxpool.ParseConfig(
		fmt.Sprintf(
			"host=%s port=%d dbname=%s user=%s password=%s sslmode=%s",
			host, portNumber, name, user, password, sslmode,
		),
	)
	if err != nil {
		return nil, fmt.Errorf("parse database configuration: %w", err)
	}

	config.MaxConns = 10
	config.MinConns = 0

	pool, err := pgxpool.NewWithConfig(ctx, config)
	if err != nil {
		return nil, fmt.Errorf("create database pool: %w", err)
	}

	if err := pool.Ping(ctx); err != nil {
		pool.Close()
		return nil, fmt.Errorf("ping database: %w", err)
	}

	return pool, nil
}

func ConnectWithRetry(
	ctx context.Context,
) (*pgxpool.Pool, error) {
	var lastErr error

	for {
		pool, err := Connect(ctx)
		if err == nil {
			return pool, nil
		}
		lastErr = err

		timer := time.NewTimer(2 * time.Second)
		select {
		case <-ctx.Done():
			timer.Stop()
			return nil, fmt.Errorf(
				"connect to database: %w (last error: %v)",
				ctx.Err(), lastErr,
			)
		case <-timer.C:
		}
	}
}
