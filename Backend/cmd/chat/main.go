package main

import (
	"context"
	"errors"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"database/sql"
	"strings"
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

	startupCtx, startupCancel := context.WithTimeout(context.Background(), 10*time.Second)
	db, err := database.OpenPostgres(startupCtx, databaseURL)
	startupCancel()
	if err != nil {
		logger.Error("chat database startup failed", "error", err)
		os.Exit(1)
	}
	defer db.Close()

	apiDB := db
	chatService := chat.NewService(db)
	var projectionAPIDB *sql.DB
	if strings.EqualFold(strings.TrimSpace(os.Getenv("CHAT_USE_PROJECTION_DATABASE")), "true") {
		if strings.TrimSpace(os.Getenv("IDENTITY_API_BASE")) == "" {
			logger.Error("projection Chat mode requires IDENTITY_API_BASE; Chat DB intentionally has no local account credentials")
			os.Exit(1)
		}
		projectionURL := strings.TrimSpace(os.Getenv("CHAT_PROJECTION_DATABASE_URL"))
		if projectionURL == "" || projectionURL == databaseURL {
			logger.Error("projection Chat mode requires a distinct CHAT_PROJECTION_DATABASE_URL")
			os.Exit(1)
		}
		projectionCtx, projectionCancel := context.WithTimeout(context.Background(), 10*time.Second)
		projectionAPIDB, err = database.OpenPostgres(projectionCtx, projectionURL)
		projectionCancel()
		if err != nil {
			logger.Error("Chat projection API database startup failed", "error", err)
			os.Exit(1)
		}
		defer projectionAPIDB.Close()
		apiDB = projectionAPIDB
		chatService = chat.NewProjectionService(apiDB)
		logger.Warn("Chat API is using Chat-owned projections; enable only after history backfill and acceptance")
	}

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	// During the database cutover period, the legacy Chat API can continue
	// using CHAT_DATABASE_URL while this independent worker maintains the
	// new Chat-owned projection database.
	projectionURL := os.Getenv("CHAT_PROJECTION_DATABASE_URL")
	if projectionURL != "" {
		go runGameProjectionConsumer(ctx, projectionURL, logger)
	} else {
		logger.Warn("CHAT_PROJECTION_DATABASE_URL is empty; Game projection consumer is disabled")
	}

	addr := os.Getenv("CHAT_HTTP_ADDR")
	if addr == "" {
		addr = ":8788"
	}

	handler, closeChatTransports := httpapi.NewChatRouterWithServiceAndShutdown(logger, apiDB, chatService)
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

func runGameProjectionConsumer(ctx context.Context, databaseURL string, logger *slog.Logger) {
	for ctx.Err() == nil {
		openCtx, cancel := context.WithTimeout(ctx, 10*time.Second)
		db, err := database.OpenPostgres(openCtx, databaseURL)
		cancel()
		if err != nil {
			logger.Error("Chat projection database unavailable; retrying connection", "error", err)
			if !waitForChatProjection(ctx, 5*time.Second) {
				return
			}
			continue
		}
		chatprojection.Run(ctx, db, logger)
		_ = db.Close()
		if ctx.Err() == nil && !waitForChatProjection(ctx, 2*time.Second) {
			return
		}
	}
}

func waitForChatProjection(ctx context.Context, duration time.Duration) bool {
	timer := time.NewTimer(duration)
	defer timer.Stop()
	select {
	case <-ctx.Done():
		return false
	case <-timer.C:
		return true
	}
}
