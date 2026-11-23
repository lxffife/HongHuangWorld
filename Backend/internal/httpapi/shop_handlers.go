package httpapi

import (
	"errors"
	"log/slog"
	"net/http"
	"strings"

	"github.com/liflife/HongHuangWorld/Backend/internal/auth"
	"github.com/liflife/HongHuangWorld/Backend/internal/shop"
)

type shopHandlers struct {
	authService auth.Provider
	service *shop.Service
	logger *slog.Logger
}

type shopPurchaseRequest struct {
	RequestID string `json:"request_id"`
	ItemID string `json:"item_id"`
	Quantity int `json:"quantity"`
}

func (h *shopHandlers) authenticate(w http.ResponseWriter,r *http.Request)(auth.Account,bool){
	header:=r.Header.Get("Authorization")
	if !strings.HasPrefix(header,"Bearer "){http.Error(w,"unauthorized",http.StatusUnauthorized);return auth.Account{},false}
	account,err:=h.authService.Authenticate(r.Context(),strings.TrimSpace(strings.TrimPrefix(header,"Bearer ")))
	if err!=nil{http.Error(w,"unauthorized",http.StatusUnauthorized);return auth.Account{},false}
	return account,true
}

func (h *shopHandlers) list(w http.ResponseWriter,r *http.Request){
	account,ok:=h.authenticate(w,r);if !ok{return}
	shops,err:=h.service.ListForAccount(r.Context(),account.ID)
	if err!=nil{h.logger.Error("list official shops failed","account_id",account.ID,"error",err);http.Error(w,"internal server error",http.StatusInternalServerError);return}
	writeJSON(w,http.StatusOK,map[string]any{"shops":shops})
}

func (h *shopHandlers) purchase(w http.ResponseWriter,r *http.Request){
	account,ok:=h.authenticate(w,r);if !ok{return}
	var request shopPurchaseRequest
	if err:=decodeJSON(w,r,&request);err!=nil{http.Error(w,"invalid request body",http.StatusBadRequest);return}
	result,err:=h.service.Purchase(r.Context(),account.ID,shop.PurchaseRequest{
		RequestID:request.RequestID,ShopID:r.PathValue("shopID"),ItemID:request.ItemID,Quantity:request.Quantity,
	})
	switch{
	case err==nil:writeJSON(w,http.StatusOK,result)
	case errors.Is(err,shop.ErrInvalidRequest):http.Error(w,"invalid shop purchase request",http.StatusBadRequest)
	case errors.Is(err,shop.ErrShopUnavailable):http.Error(w,"shop or item is unavailable in the current world",http.StatusNotFound)
	case errors.Is(err,shop.ErrInsufficientFunds):http.Error(w,"insufficient currency balance",http.StatusConflict)
	case errors.Is(err,shop.ErrInventoryFull):http.Error(w,"inventory is full",http.StatusConflict)
	case errors.Is(err,shop.ErrStackLimit):http.Error(w,"item stack limit exceeded",http.StatusConflict)
	case errors.Is(err,shop.ErrOutOfStock):http.Error(w,"shop item is out of stock",http.StatusConflict)
	case errors.Is(err,shop.ErrIdempotencyConflict):http.Error(w,"request id was already used",http.StatusConflict)
	default:h.logger.Error("purchase official shop item failed","account_id",account.ID,"shop_id",r.PathValue("shopID"),"error",err);http.Error(w,"internal server error",http.StatusInternalServerError)
	}
}
