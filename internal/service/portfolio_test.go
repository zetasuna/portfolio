package service

import (
	"context"
	"errors"
	"strings"
	"testing"

	"github.com/zetasuna/portfolio/internal/models"
)

type mockPortfolioRepository struct {
	createFn  func(context.Context, models.CreateItemInput) (*models.Item, error)
	getByIDFn func(context.Context, int64) (*models.Item, error)
	listFn    func(context.Context, int, int) ([]models.Item, error)
	updateFn  func(context.Context, int64, models.UpdateItemInput) (*models.Item, error)
	deleteFn  func(context.Context, int64) error

	createCalls  int
	getByIDCalls int
	listCalls    int
	updateCalls  int
	deleteCalls  int

	createInput models.CreateItemInput
	getByID     int64
	listLimit   int
	listOffset  int
	updateID    int64
	updateInput models.UpdateItemInput
	deleteID    int64
}

func (m *mockPortfolioRepository) Create(
	ctx context.Context,
	input models.CreateItemInput,
) (*models.Item, error) {
	m.createCalls++
	m.createInput = input

	if m.createFn != nil {
		return m.createFn(ctx, input)
	}
	return &models.Item{Title: input.Title}, nil
}

func (m *mockPortfolioRepository) GetByID(
	ctx context.Context,
	id int64,
) (*models.Item, error) {
	m.getByIDCalls++
	m.getByID = id

	if m.getByIDFn != nil {
		return m.getByIDFn(ctx, id)
	}
	return &models.Item{ID: id}, nil
}

func (m *mockPortfolioRepository) List(
	ctx context.Context,
	limit, offset int,
) ([]models.Item, error) {
	m.listCalls++
	m.listLimit = limit
	m.listOffset = offset

	if m.listFn != nil {
		return m.listFn(ctx, limit, offset)
	}
	return []models.Item{}, nil
}

func (m *mockPortfolioRepository) Update(
	ctx context.Context,
	id int64,
	input models.UpdateItemInput,
) (*models.Item, error) {
	m.updateCalls++
	m.updateID = id
	m.updateInput = input

	if m.updateFn != nil {
		return m.updateFn(ctx, id, input)
	}
	return &models.Item{ID: id, Title: input.Title}, nil
}

func (m *mockPortfolioRepository) Delete(
	ctx context.Context,
	id int64,
) error {
	m.deleteCalls++
	m.deleteID = id

	if m.deleteFn != nil {
		return m.deleteFn(ctx, id)
	}
	return nil
}

func TestCreateTrimsTitle(t *testing.T) {
	repo := &mockPortfolioRepository{}
	svc := NewPortfolioService(repo)

	item, err := svc.Create(context.Background(), models.CreateItemInput{
		Title:       "  My Portfolio  ",
		Description: "Example",
		URL:         "https://example.com",
	})
	if err != nil {
		t.Fatalf("Create() error = %v", err)
	}

	if item.Title != "My Portfolio" {
		t.Errorf("item.Title = %q, want %q", item.Title, "My Portfolio")
	}
	if repo.createInput.Title != "My Portfolio" {
		t.Errorf("repository received title %q", repo.createInput.Title)
	}
	if repo.createCalls != 1 {
		t.Errorf("Create calls = %d, want 1", repo.createCalls)
	}
}

func TestCreateRejectsEmptyTitle(t *testing.T) {
	tests := []string{"", " ", "\t\n"}

	for _, title := range tests {
		t.Run(title, func(t *testing.T) {
			repo := &mockPortfolioRepository{}
			svc := NewPortfolioService(repo)

			_, err := svc.Create(context.Background(), models.CreateItemInput{
				Title: title,
			})

			if !errors.Is(err, ErrInvalidInput) {
				t.Errorf("error = %v, want ErrInvalidInput", err)
			}
			if repo.createCalls != 0 {
				t.Errorf("repository called %d times, want 0", repo.createCalls)
			}
		})
	}
}

func TestCreateRejectsTitleOver200Characters(t *testing.T) {
	repo := &mockPortfolioRepository{}
	svc := NewPortfolioService(repo)

	_, err := svc.Create(context.Background(), models.CreateItemInput{
		Title: strings.Repeat("a", 201),
	})

	if !errors.Is(err, ErrInvalidInput) {
		t.Errorf("error = %v, want ErrInvalidInput", err)
	}
	if repo.createCalls != 0 {
		t.Errorf("repository called %d times, want 0", repo.createCalls)
	}
}

func TestCreateAccepts200UnicodeCharacters(t *testing.T) {
	repo := &mockPortfolioRepository{}
	svc := NewPortfolioService(repo)

	title := strings.Repeat("ế", 200)
	_, err := svc.Create(context.Background(), models.CreateItemInput{
		Title: title,
	})
	if err != nil {
		t.Fatalf("Create() error = %v", err)
	}

	if repo.createInput.Title != title {
		t.Errorf("repository received an unexpected title")
	}
}

func TestListPagination(t *testing.T) {
	tests := []struct {
		name       string
		limit      int
		offset     int
		wantLimit  int
		wantOffset int
		wantErr    bool
	}{
		{
			name:       "default limit",
			limit:      0,
			offset:     0,
			wantLimit:  DefaultPageSize,
			wantOffset: 0,
		},
		{
			name:       "negative limit uses default",
			limit:      -1,
			offset:     5,
			wantLimit:  DefaultPageSize,
			wantOffset: 5,
		},
		{
			name:       "limit capped at maximum",
			limit:      500,
			offset:     0,
			wantLimit:  MaxPageSize,
			wantOffset: 0,
		},
		{
			name:    "negative offset rejected",
			limit:   10,
			offset:  -1,
			wantErr: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			repo := &mockPortfolioRepository{}
			svc := NewPortfolioService(repo)

			_, err := svc.List(context.Background(), tt.limit, tt.offset)

			if tt.wantErr {
				if !errors.Is(err, ErrInvalidInput) {
					t.Fatalf("error = %v, want ErrInvalidInput", err)
				}
				if repo.listCalls != 0 {
					t.Errorf("repository called %d times, want 0", repo.listCalls)
				}
				return
			}

			if err != nil {
				t.Fatalf("List() error = %v", err)
			}
			if repo.listLimit != tt.wantLimit {
				t.Errorf("limit = %d, want %d", repo.listLimit, tt.wantLimit)
			}
			if repo.listOffset != tt.wantOffset {
				t.Errorf("offset = %d, want %d", repo.listOffset, tt.wantOffset)
			}
		})
	}
}

func TestGetByIDRejectsInvalidID(t *testing.T) {
	repo := &mockPortfolioRepository{}
	svc := NewPortfolioService(repo)

	_, err := svc.GetByID(context.Background(), 0)

	if !errors.Is(err, ErrInvalidID) {
		t.Errorf("error = %v, want ErrInvalidID", err)
	}
	if repo.getByIDCalls != 0 {
		t.Errorf("repository called %d times, want 0", repo.getByIDCalls)
	}
}

func TestUpdateRejectsEmptyTitle(t *testing.T) {
	repo := &mockPortfolioRepository{}
	svc := NewPortfolioService(repo)

	_, err := svc.Update(context.Background(), 1, models.UpdateItemInput{
		Title: "   ",
	})

	if !errors.Is(err, ErrInvalidInput) {
		t.Errorf("error = %v, want ErrInvalidInput", err)
	}
	if repo.updateCalls != 0 {
		t.Errorf("repository called %d times, want 0", repo.updateCalls)
	}
}

func TestDeleteRejectsInvalidID(t *testing.T) {
	repo := &mockPortfolioRepository{}
	svc := NewPortfolioService(repo)

	err := svc.Delete(context.Background(), -1)

	if !errors.Is(err, ErrInvalidID) {
		t.Errorf("error = %v, want ErrInvalidID", err)
	}
	if repo.deleteCalls != 0 {
		t.Errorf("repository called %d times, want 0", repo.deleteCalls)
	}
}

func TestRepositoryErrorIsPreserved(t *testing.T) {
	dbErr := errors.New("database unavailable")
	repo := &mockPortfolioRepository{
		createFn: func(
			context.Context,
			models.CreateItemInput,
		) (*models.Item, error) {
			return nil, dbErr
		},
	}
	svc := NewPortfolioService(repo)

	_, err := svc.Create(context.Background(), models.CreateItemInput{
		Title: "Valid title",
	})

	if !errors.Is(err, dbErr) {
		t.Errorf("error = %v, want wrapped database error", err)
	}
}
