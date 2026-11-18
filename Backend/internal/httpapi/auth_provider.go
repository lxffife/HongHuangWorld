package httpapi

import (
	"os"

	"github.com/liflife/HongHuangWorld/Backend/internal/auth"
)

// configuredAuthProvider always delegates authentication to the independent
// Identity service. Chat never reads Identity credentials or Game account tables.
func configuredAuthProvider() auth.Provider {
	return auth.NewHTTPClient(os.Getenv("IDENTITY_API_BASE"), os.Getenv("IDENTITY_SERVICE_TOKEN"))
}
