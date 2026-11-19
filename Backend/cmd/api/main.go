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
	"github.com/liflife/HongHuangWorld/Backend/internal/gameevents"
	"github.com/liflife/HongHuangWorld/Backend/internal/httpapi"
	"github.com/liflife/HongHuangWorld/Backend/internal/worldentry"
)

func main() {
	logger := slog.New(slog.NewJSONHandler(os.Stdout, nil))
	if os.Getenv("GAME_ADMIN_INTERNAL_API_KEY") == "" {
		logger.Error("GAME_ADMIN_INTERNAL_API_KEY is required")
		os.Exit(1)
	}
	startupCtx, startupCancel := context.WithTimeout(context.Background(), 10*time.Second)
	db, err := database.OpenPostgres(startupCtx, os.Getenv("DATABASE_URL"))
	startupCancel()
	if err != nil {
		logger.Error("database startup failed", "error", err)
		os.Exit(1)
	}
	defer db.Close()

	addr := os.Getenv("HTTP_ADDR")
	if addr == "" {
		addr = ":8787"
	}

	server := &http.Server{
		Addr:              addr,
		Handler:           httpapi.NewRouter(logger, db),
		ReadHeaderTimeout: 5 * time.Second,
	}

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	go runSessionRecovery(ctx, worldentry.NewService(db), logger)
	go gameevents.RunOutboxPublisher(ctx, db, logger)

	go func() {
		logger.Info("backend starting", "addr", addr)
		if err := server.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			logger.Error("backend stopped unexpectedly", "error", err)
			stop()
		}
	}()

	<-ctx.Done()
	shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if err := server.Shutdown(shutdownCtx); err != nil {
		logger.Error("graceful shutdown failed", "error", err)
	}
	logger.Info("backend stopped")
}


func runSessionRecovery(ctx context.Context, service *worldentry.Service, logger *slog.Logger) {
	ticker := time.NewTicker(15 * time.Second)
	defer ticker.Stop()

	recoverOnce := func() {
		recoveryCtx, cancel := context.WithTimeout(ctx, 5*time.Second)
		defer cancel()
		closed, err := service.RecoverOrphanedSessions(recoveryCtx)
		if err != nil {
			logger.Error("orphan world session recovery failed", "error", err)
			return
		}
		if closed > 0 {
			logger.Info("orphan world sessions recovered", "closed_sessions", closed)
		}
	}

	recoverOnce()
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			recoverOnce()
		}
	}
}
