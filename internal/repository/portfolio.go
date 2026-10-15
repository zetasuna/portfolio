// Package repository
package repository

import (
	"context"
	"errors"
	"fmt"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/zetasuna/portfolio/internal/models"
)

var ErrNotFound = errors.New("portfolio item not found")

type Repository struct {
	db *pgxpool.Pool
}

func NewRepository(db *pgxpool.Pool) *Repository {
	return &Repository{db: db}
}

func (r *Repository) Create(
	ctx context.Context,
	input models.CreateItemInput,
) (*models.Item, error) {
	const query = `
		INSERT INTO portfolio_items (title, description, url)
		VALUES ($1, $2, $3)
		RETURNING id, title, description, url, created_at, updated_at
	`

	var item models.Item
	err := r.db.QueryRow(
		ctx, query,
		input.Title, input.Description, input.URL,
	).Scan(
		&item.ID,
		&item.Title,
		&item.Description,
		&item.URL,
		&item.CreatedAt,
		&item.UpdatedAt,
	)
	if err != nil {
		return nil, fmt.Errorf("create portfolio item: %w", err)
	}

	return &item, nil
}

func (r *Repository) GetByID(
	ctx context.Context,
	id int64,
) (*models.Item, error) {
	const query = `
		SELECT id, title, description, url, created_at, updated_at
		FROM portfolio_items
		WHERE id = $1
	`

	var item models.Item
	err := r.db.QueryRow(ctx, query, id).Scan(
		&item.ID,
		&item.Title,
		&item.Description,
		&item.URL,
		&item.CreatedAt,
		&item.UpdatedAt,
	)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, ErrNotFound
	}
	if err != nil {
		return nil, fmt.Errorf("get portfolio item: %w", err)
	}

	return &item, nil
}

func (r *Repository) List(
	ctx context.Context,
	limit, offset int,
) ([]models.Item, error) {
	const query = `
		SELECT id, title, description, url, created_at, updated_at
		FROM portfolio_items
		ORDER BY created_at DESC, id DESC
		LIMIT $1 OFFSET $2
	`

	rows, err := r.db.Query(ctx, query, limit, offset)
	if err != nil {
		return nil, fmt.Errorf("list portfolio items: %w", err)
	}
	defer rows.Close()

	items := make([]models.Item, 0)
	for rows.Next() {
		var item models.Item
		if err := rows.Scan(
			&item.ID,
			&item.Title,
			&item.Description,
			&item.URL,
			&item.CreatedAt,
			&item.UpdatedAt,
		); err != nil {
			return nil, fmt.Errorf("scan portfolio item: %w", err)
		}

		items = append(items, item)
	}

	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate portfolio items: %w", err)
	}

	return items, nil
}

func (r *Repository) Update(
	ctx context.Context,
	id int64,
	input models.UpdateItemInput,
) (*models.Item, error) {
	const query = `
		UPDATE portfolio_items
		SET title = $2,
		    description = $3,
		    url = $4,
		    updated_at = NOW()
		WHERE id = $1
		RETURNING id, title, description, url, created_at, updated_at
	`

	var item models.Item
	err := r.db.QueryRow(
		ctx, query,
		id, input.Title, input.Description, input.URL,
	).Scan(
		&item.ID,
		&item.Title,
		&item.Description,
		&item.URL,
		&item.CreatedAt,
		&item.UpdatedAt,
	)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, ErrNotFound
	}
	if err != nil {
		return nil, fmt.Errorf("update portfolio item: %w", err)
	}

	return &item, nil
}

func (r *Repository) Delete(
	ctx context.Context,
	id int64,
) error {
	const query = `DELETE FROM portfolio_items WHERE id = $1`

	result, err := r.db.Exec(ctx, query, id)
	if err != nil {
		return fmt.Errorf("delete portfolio item: %w", err)
	}

	if result.RowsAffected() == 0 {
		return ErrNotFound
	}

	return nil
}
