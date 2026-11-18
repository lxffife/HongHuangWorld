package main

import (
	"context"
	"errors"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/liflife/HongHuangWorld/Backend/internal/database"
	"github.com/liflife/HongHuangWorld/Backend/internal/httpapi"
)

func main() {
	logger := slog.New(slog.NewJSONHandler(os.Stdout, nil))
	databaseURL := os.Getenv("IDENTITY_DATABASE_URL")
	if databaseURL == "" {
		logger.Error("IDENTITY_DATABASE_URL is required")
		os.Exit(1)
	}
	if os.Getenv("IDENTITY_INTERNAL_API_KEY") == "" {
		logger.Error("IDENTITY_INTERNAL_API_KEY is required")
		os.Exit(1)
	}
	startupCtx, startupCancel := context.WithTimeout(context.Background(), 10*time.Second)
	db, err := database.OpenPostgres(startupCtx, databaseURL)
	startupCancel()
	if err != nil {
		logger.Error("identity database startup failed", "error", err)
		os.Exit(1)
	}
	defer db.Close()

	addr := os.Getenv("IDENTITY_HTTP_ADDR")
	if addr == "" {
		addr = "127.0.0.1:8789"
	}
	server := &http.Server{
		Addr: addr, Handler: httpapi.NewIdentityRouter(logger, db),
		ReadHeaderTimeout: 5 * time.Second, IdleTimeout: 60 * time.Second,
	}
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	go func() {
		logger.Info("identity service starting", "addr", addr)
		if err := server.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			logger.Error("identity service stopped unexpectedly", "error", err)
			stop()
		}
	}()
	<-ctx.Done()
	shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if err := server.Shutdown(shutdownCtx); err != nil {
		logger.Error("identity graceful shutdown failed", "error", err)
	}
	logger.Info("identity service stopped")
}
