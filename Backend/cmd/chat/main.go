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

	"github.com/liflife/HongHuangWorld/Backend/internal/chat"
	"github.com/liflife/HongHuangWorld/Backend/internal/chatprojection"
	"github.com/liflife/HongHuangWorld/Backend/internal/database"
	"github.com/liflife/HongHuangWorld/Backend/internal/httpapi"
)

func main() {
	logger := slog.New(slog.NewJSONHandler(os.Stdout, nil))
	databaseURL := os.Getenv("CHAT_DATABASE_URL")
	if databaseURL == "" {
		logger.Error("CHAT_DATABASE_URL is required; configure it independently from the game API")
		os.Exit(1)
	}

	if os.Getenv("IDENTITY_API_BASE") == "" || os.Getenv("IDENTITY_SERVICE_TOKEN") == "" {
		logger.Error("IDENTITY_API_BASE and IDENTITY_SERVICE_TOKEN are required; Chat authentication is owned by Identity")
		os.Exit(1)
	}

	startupCtx, startupCancel := context.WithTimeout(context.Background(), 10*time.Second)
	db, err := database.OpenPostgres(startupCtx, databaseURL)
	startupCancel()
	if err != nil {
		logger.Error("chat database startup failed", "error", err)
		os.Exit(1)
	}
	defer db.Close()

	if gameDBURL := os.Getenv("DATABASE_URL"); gameDBURL != "" && gameDBURL == databaseURL {
		logger.Error("CHAT_DATABASE_URL must point to the dedicated Chat database, not DATABASE_URL")
		os.Exit(1)
	}

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	// Chat always consumes Game domain events into its own database. Game and
	// Chat remain independently available; no runtime SQL crosses DB boundaries.
	go chatprojection.Run(ctx, db, logger)
	chatService := chat.NewService(db)

	addr := os.Getenv("CHAT_HTTP_ADDR")
	if addr == "" {
		addr = ":8788"
	}

	handler, closeChatTransports := httpapi.NewChatRouterWithServiceAndShutdown(logger, db, chatService)
	defer closeChatTransports()
	server := &http.Server{
		Addr:              addr,
		Handler:           handler,
		ReadHeaderTimeout: 5 * time.Second,
		IdleTimeout:       60 * time.Second,
	}

	go runChatRetentionCleanup(ctx, chatService, logger)

	go func() {
		logger.Info("chat service starting", "addr", addr)
		if err := server.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			logger.Error("chat service stopped unexpectedly", "error", err)
			stop()
		}
	}()

	<-ctx.Done()
	shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if err := server.Shutdown(shutdownCtx); err != nil {
		logger.Error("chat graceful shutdown failed", "error", err)
	}
	logger.Info("chat service stopped")
}

func runChatRetentionCleanup(ctx context.Context, service *chat.Service, logger *slog.Logger) {
	cleanup := func() {
		cleanupCtx, cancel := context.WithTimeout(ctx, 30*time.Second)
		defer cancel()
		deleted, err := service.PruneExpiredMessages(cleanupCtx)
		if err != nil {
			logger.Error("chat retention cleanup failed", "error", err)
			return
		}
		if deleted > 0 {
			logger.Info("expired chat messages removed", "count", deleted, "retention_days", 30)
		}
	}

	// Run once after startup, then hourly. Cleanup never runs on a send/history request.
	cleanup()
	ticker := time.NewTicker(time.Hour)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			cleanup()
		}
	}
}

