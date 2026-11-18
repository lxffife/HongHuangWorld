package httpapi

import (
	"database/sql"
	"os"

	"github.com/liflife/HongHuangWorld/Backend/internal/auth"
)

// configuredAuthProvider uses the standalone Identity service when configured.
// The database-backed provider remains only as a temporary migration fallback.
func configuredAuthProvider(db *sql.DB) auth.Provider {
	baseURL := os.Getenv("IDENTITY_API_BASE")
	if baseURL != "" {
		return auth.NewHTTPClient(baseURL, os.Getenv("IDENTITY_SERVICE_TOKEN"))
	}
	return auth.NewService(db)
}
