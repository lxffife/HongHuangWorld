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

 "github.com/liflife/HongHuangWorld/Backend/internal/adminauth"
 "github.com/liflife/HongHuangWorld/Backend/internal/database"
 "github.com/liflife/HongHuangWorld/Backend/internal/httpapi"
)

func main(){
 logger:=slog.New(slog.NewJSONHandler(os.Stdout,nil))
 dbURL:=os.Getenv("ADMIN_DATABASE_URL");if dbURL==""{dbURL=os.Getenv("DATABASE_URL")}
 ctx,cancel:=context.WithTimeout(context.Background(),10*time.Second)
 db,err:=database.OpenPostgres(ctx,dbURL);cancel()
 if err!=nil{logger.Error("admin database startup failed","error",err);os.Exit(1)}
 defer db.Close()
 bootstrapCtx,bootstrapCancel:=context.WithTimeout(context.Background(),10*time.Second)
 created,err:=adminauth.NewService(db).Bootstrap(bootstrapCtx,os.Getenv("ADMIN_BOOTSTRAP_USERNAME"),os.Getenv("ADMIN_BOOTSTRAP_EMAIL"),os.Getenv("ADMIN_BOOTSTRAP_PASSWORD"))
 bootstrapCancel()
 if err!=nil{logger.Error("admin bootstrap failed","error",err);os.Exit(1)}
 if created{logger.Info("initial super administrator created","username",os.Getenv("ADMIN_BOOTSTRAP_USERNAME"))}
 addr:=os.Getenv("ADMIN_HTTP_ADDR");if addr==""{addr="0.0.0.0:8790"}
 server:=&http.Server{Addr:addr,Handler:httpapi.NewAdminRouter(logger,db),ReadHeaderTimeout:5*time.Second}
 runCtx,stop:=signal.NotifyContext(context.Background(),os.Interrupt,syscall.SIGTERM);defer stop()
 go func(){logger.Info("admin API starting","addr",addr);if err:=server.ListenAndServe();err!=nil&&!errors.Is(err,http.ErrServerClosed){logger.Error("admin API stopped unexpectedly","error",err);stop()}}()
 <-runCtx.Done()
 shutdownCtx,shutdownCancel:=context.WithTimeout(context.Background(),10*time.Second);defer shutdownCancel()
 if err:=server.Shutdown(shutdownCtx);err!=nil{logger.Error("admin API shutdown failed","error",err)}
 logger.Info("admin API stopped")
}
