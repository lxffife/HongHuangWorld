package world

import (
	"context"
	"database/sql"
	"fmt"
)

type Definition struct {
	ID        string `json:"id"`
	Name      string `json:"name"`
	Type      string `json:"type"`
	Level     int16  `json:"level"`
}

type Service struct {
	db *sql.DB
}

func NewService(db *sql.DB) *Service {
	return &Service{db: db}
}

func (s *Service) ListEnabled(ctx context.Context) ([]Definition, error) {
	rows, err := s.db.QueryContext(ctx,
		`SELECT id, name, world_type, world_level FROM world_definitions WHERE enabled = TRUE ORDER BY world_level, id`)
	if err != nil {
		return nil, fmt.Errorf("list world definitions: %w", err)
	}
	defer rows.Close()

	worlds := make([]Definition, 0)
	for rows.Next() {
		var item Definition
		if err := rows.Scan(&item.ID, &item.Name, &item.Type, &item.Level); err != nil {
			return nil, fmt.Errorf("scan world definition: %w", err)
		}
		worlds = append(worlds, item)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate world definitions: %w", err)
	}
	return worlds, nil
}
