// Package service
package service

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"unicode/utf8"

	"github.com/zetasuna/portfolio/internal/models"
	"github.com/zetasuna/portfolio/internal/repository"
)

var (
	ErrInvalidInput = errors.New("invalid input")
	ErrInvalidID    = errors.New("invalid item ID")
	ErrNotFound     = errors.New("portfolio item not found")
)

const (
	DefaultPageSize = 20
	MaxPageSize     = 100
	MaxTitleLength  = 200
)

type PortfolioRepository interface {
	Create(
		ctx context.Context,
		input models.CreateItemInput,
	) (*models.Item, error)

	GetByID(ctx context.Context, id int64) (*models.Item, error)

	List(
		ctx context.Context,
		limit, offset int,
	) ([]models.Item, error)

	Update(
		ctx context.Context,
		id int64,
		input models.UpdateItemInput,
	) (*models.Item, error)

	Delete(ctx context.Context, id int64) error
}

type PortfolioService struct {
	repo PortfolioRepository
}

func NewPortfolioService(repo PortfolioRepository) *PortfolioService {
	return &PortfolioService{repo: repo}
}

func validateTitle(title string) (string, error) {
	title = strings.TrimSpace(title)

	if title == "" {
		return "", fmt.Errorf("%w: title is required", ErrInvalidInput)
	}

	if utf8.RuneCountInString(title) > MaxTitleLength {
		return "", fmt.Errorf(
			"%w: title must not exceed %d characters",
			ErrInvalidInput,
			MaxTitleLength,
		)
	}

	return title, nil
}

func (s *PortfolioService) Create(
	ctx context.Context,
	input models.CreateItemInput,
) (*models.Item, error) {
	title, err := validateTitle(input.Title)
	if err != nil {
		return nil, err
	}

	input.Title = title

	item, err := s.repo.Create(ctx, input)
	if err != nil {
		return nil, fmt.Errorf("create portfolio item: %w", err)
	}

	return item, nil
}

func (s *PortfolioService) GetByID(
	ctx context.Context,
	id int64,
) (*models.Item, error) {
	if id <= 0 {
		return nil, ErrInvalidID
	}

	item, err := s.repo.GetByID(ctx, id)
	if errors.Is(err, repository.ErrNotFound) {
		return nil, ErrNotFound
	}
	if err != nil {
		return nil, fmt.Errorf("get portfolio item: %w", err)
	}

	return item, nil
}

func (s *PortfolioService) List(
	ctx context.Context,
	limit, offset int,
) ([]models.Item, error) {
	if limit <= 0 {
		limit = DefaultPageSize
	}
	if limit > MaxPageSize {
		limit = MaxPageSize
	}
	if offset < 0 {
		return nil, fmt.Errorf(
			"%w: offset must not be negative",
			ErrInvalidInput,
		)
	}

	items, err := s.repo.List(ctx, limit, offset)
	if err != nil {
		return nil, fmt.Errorf("list portfolio items: %w", err)
	}

	return items, nil
}

func (s *PortfolioService) Update(
	ctx context.Context,
	id int64,
	input models.UpdateItemInput,
) (*models.Item, error) {
	if id <= 0 {
		return nil, ErrInvalidID
	}

	title, err := validateTitle(input.Title)
	if err != nil {
		return nil, err
	}

	input.Title = title

	item, err := s.repo.Update(ctx, id, input)
	if errors.Is(err, repository.ErrNotFound) {
		return nil, ErrNotFound
	}
	if err != nil {
		return nil, fmt.Errorf("update portfolio item: %w", err)
	}

	return item, nil
}

func (s *PortfolioService) Delete(
	ctx context.Context,
	id int64,
) error {
	if id <= 0 {
		return ErrInvalidID
	}

	err := s.repo.Delete(ctx, id)
	if errors.Is(err, repository.ErrNotFound) {
		return ErrNotFound
	}
	if err != nil {
		return fmt.Errorf("delete portfolio item: %w", err)
	}

	return nil
}
