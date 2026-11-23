package shop

import (
	"context"
	"database/sql"
	"errors"

	"github.com/liflife/HongHuangWorld/Backend/internal/economy"
	"fmt"
	"math"
	"regexp"
	"strings"
)

var (
	ErrInvalidRequest = errors.New("invalid shop request")
	ErrShopUnavailable = errors.New("shop or item is unavailable")
	ErrInsufficientFunds = economy.ErrInsufficientFunds
	ErrInventoryFull = errors.New("inventory is full")
	ErrStackLimit = errors.New("inventory stack limit exceeded")
	ErrOutOfStock = errors.New("shop item is out of stock")
	ErrIdempotencyConflict = errors.New("shop request id was already used")
)

var uuidPattern = regexp.MustCompile(`(?i)^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$`)

type Service struct { db *sql.DB }

func NewService(db *sql.DB) *Service { return &Service{db: db} }

type ShopItem struct {
	ItemID string `json:"item_id"`
	Name string `json:"name"`
	Category string `json:"category"`
	Quality int `json:"quality"`
	MaxStack int `json:"max_stack"`
	IconKey string `json:"icon_key"`
	Description string `json:"description"`
	UnitPrice int64 `json:"unit_price"`
	StockQuantity *int64 `json:"stock_quantity,omitempty"`
}

type Shop struct {
	ID string `json:"id"`
	Name string `json:"name"`
	Type string `json:"type"`
	Description string `json:"description"`
	CurrencyID string `json:"currency_id"`
	CurrencyName string `json:"currency_name"`
	CurrencySymbol string `json:"currency_symbol"`
	Items []ShopItem `json:"items"`
}

type PurchaseRequest struct {
	RequestID string
	ShopID string
	ItemID string
	Quantity int
}

type PurchaseResult struct {
	Applied bool `json:"applied"`
	ShopID string `json:"shop_id"`
	ItemID string `json:"item_id"`
	ItemName string `json:"item_name"`
	Quantity int `json:"quantity"`
	CurrencyID string `json:"currency_id"`
	TotalPrice int64 `json:"total_price"`
	BalanceAfter int64 `json:"balance_after"`
}

func validPurchaseRequest(accountID string, request PurchaseRequest) bool {
	return strings.TrimSpace(accountID) != "" &&
		uuidPattern.MatchString(request.RequestID) &&
		len(request.ShopID) > 0 && len(request.ShopID) <= 64 &&
		len(request.ItemID) > 0 && len(request.ItemID) <= 64 &&
		request.Quantity >= 1 && request.Quantity <= 99
}

func (s *Service) ListForAccount(ctx context.Context, accountID string) ([]Shop, error) {
	if strings.TrimSpace(accountID) == "" { return nil, ErrInvalidRequest }
	var worldID string
	err := s.db.QueryRowContext(ctx, `SELECT c.world_id
		FROM souls soul JOIN characters c ON c.id=soul.current_character_id
		JOIN world_sessions ws ON ws.character_id=c.id AND ws.session_state='active'
		WHERE soul.account_id=$1 AND c.status='alive'`, accountID).Scan(&worldID)
	if errors.Is(err, sql.ErrNoRows) { return []Shop{}, nil }
	if err != nil { return nil, fmt.Errorf("resolve current character world for shops: %w", err) }

	rows, err := s.db.QueryContext(ctx, `SELECT s.id,s.display_name,s.shop_type,s.description,
		s.currency_id,c.display_name,c.symbol,
		i.id,i.name,i.category,i.quality,i.max_stack,i.icon_key,i.description,
		si.unit_price,si.stock_quantity
		FROM npc_shop_definitions s
		JOIN currency_definitions c ON c.id=s.currency_id AND c.enabled
		LEFT JOIN npc_shop_items si ON si.shop_id=s.id AND si.enabled
		LEFT JOIN item_definitions i ON i.id=si.item_id AND i.enabled
		WHERE s.world_id=$1 AND s.enabled
		ORDER BY s.shop_type,s.id,si.sort_order,i.quality DESC,i.name`, worldID)
	if err != nil { return nil, fmt.Errorf("list official NPC shops: %w", err) }
	defer rows.Close()

	shops := make([]Shop, 0)
	indexByID := make(map[string]int)
	for rows.Next() {
		var shopID, name, shopType, description, currencyID, currencyName, currencySymbol string
		var itemID, itemName, category, iconKey, itemDescription sql.NullString
		var quality, maxStack sql.NullInt64
		var price sql.NullInt64
		var stock sql.NullInt64
		if err := rows.Scan(&shopID,&name,&shopType,&description,&currencyID,&currencyName,&currencySymbol,
			&itemID,&itemName,&category,&quality,&maxStack,&iconKey,&itemDescription,&price,&stock); err != nil {
			return nil, fmt.Errorf("scan official shop catalog: %w", err)
		}
		idx, exists := indexByID[shopID]
		if !exists {
			idx = len(shops)
			indexByID[shopID] = idx
			shops = append(shops, Shop{ID:shopID,Name:name,Type:shopType,Description:description,
				CurrencyID:currencyID,CurrencyName:currencyName,CurrencySymbol:currencySymbol,Items:[]ShopItem{}})
		}
		if !itemID.Valid { continue }
		item := ShopItem{ItemID:itemID.String,Name:itemName.String,Category:category.String,
			Quality:int(quality.Int64),MaxStack:int(maxStack.Int64),IconKey:iconKey.String,
			Description:itemDescription.String,UnitPrice:price.Int64}
		if stock.Valid { value:=stock.Int64; item.StockQuantity=&value }
		shops[idx].Items = append(shops[idx].Items,item)
	}
	if err := rows.Err(); err != nil { return nil, fmt.Errorf("iterate official shop catalog: %w", err) }
	return shops,nil
}

func (s *Service) Purchase(ctx context.Context, accountID string, request PurchaseRequest) (PurchaseResult,error) {
	if !validPurchaseRequest(accountID,request) { return PurchaseResult{},ErrInvalidRequest }
	tx,err:=s.db.BeginTx(ctx,nil)
	if err!=nil{return PurchaseResult{},fmt.Errorf("begin NPC shop purchase: %w",err)}
	defer tx.Rollback()

	var characterID,worldID string
	if err:=tx.QueryRowContext(ctx,`SELECT c.id::text,c.world_id
		FROM souls soul JOIN characters c ON c.id=soul.current_character_id
		JOIN world_sessions ws ON ws.character_id=c.id AND ws.session_state='active'
		WHERE soul.account_id=$1 AND c.status='alive' FOR UPDATE OF c`,accountID).Scan(&characterID,&worldID);err!=nil{
		if errors.Is(err,sql.ErrNoRows){return PurchaseResult{},ErrInvalidRequest}
		return PurchaseResult{},fmt.Errorf("resolve shop buyer character: %w",err)
	}

	var replay PurchaseResult
	var replayShopID,replayItemID string
	var replayQuantity int
	err=tx.QueryRowContext(ctx,`SELECT shop_id,item_id,quantity,currency_id,total_price,balance_after
		FROM npc_shop_purchase_events WHERE account_id=$1 AND request_id=$2::uuid`,accountID,request.RequestID).
		Scan(&replayShopID,&replayItemID,&replayQuantity,&replay.CurrencyID,&replay.TotalPrice,&replay.BalanceAfter)
	if err==nil{
		if replayShopID!=request.ShopID||replayItemID!=request.ItemID||replayQuantity!=request.Quantity{return PurchaseResult{},ErrIdempotencyConflict}
		var itemName string
		if err:=tx.QueryRowContext(ctx,`SELECT name FROM item_definitions WHERE id=$1`,request.ItemID).Scan(&itemName);err!=nil{return PurchaseResult{},fmt.Errorf("load replayed shop item name: %w",err)}
		replay.Applied=false;replay.ShopID=replayShopID;replay.ItemID=replayItemID;replay.ItemName=itemName;replay.Quantity=replayQuantity
		if err:=tx.Commit();err!=nil{return PurchaseResult{},fmt.Errorf("commit NPC shop purchase replay: %w",err)}
		return replay,nil
	}
	if !errors.Is(err,sql.ErrNoRows){return PurchaseResult{},fmt.Errorf("check NPC shop purchase idempotency: %w",err)}

	var currencyID,itemName string
	var price int64
	var stock sql.NullInt64
	var maxStack int
	err=tx.QueryRowContext(ctx,`SELECT s.currency_id,i.name,si.unit_price,si.stock_quantity,i.max_stack
		FROM npc_shop_definitions s
		JOIN npc_shop_items si ON si.shop_id=s.id AND si.item_id=$3 AND si.enabled
		JOIN item_definitions i ON i.id=si.item_id AND i.enabled
		JOIN currency_definitions c ON c.id=s.currency_id AND c.enabled
		WHERE s.id=$1 AND s.world_id=$2 AND s.enabled
		FOR UPDATE OF si`,request.ShopID,worldID,request.ItemID).
		Scan(&currencyID,&itemName,&price,&stock,&maxStack)
	if errors.Is(err,sql.ErrNoRows){return PurchaseResult{},ErrShopUnavailable}
	if err!=nil{return PurchaseResult{},fmt.Errorf("load NPC shop item: %w",err)}
	if int64(request.Quantity)>math.MaxInt64/price{return PurchaseResult{},ErrInvalidRequest}
	total:=price*int64(request.Quantity)
	if stock.Valid&&stock.Int64<int64(request.Quantity){return PurchaseResult{},ErrOutOfStock}
	if request.Quantity>maxStack{return PurchaseResult{},ErrStackLimit}

	var currentQuantity int
	err=tx.QueryRowContext(ctx,`SELECT quantity FROM character_inventory
		WHERE character_id=$1::uuid AND item_id=$2 FOR UPDATE`,characterID,request.ItemID).Scan(&currentQuantity)
	hasStack:=err==nil
	if err!=nil&&!errors.Is(err,sql.ErrNoRows){return PurchaseResult{},fmt.Errorf("lock buyer inventory stack: %w",err)}
	if hasStack&&currentQuantity>maxStack-request.Quantity{return PurchaseResult{},ErrStackLimit}
	if !hasStack{
		var usedSlots,maxSlots int
		if err:=tx.QueryRowContext(ctx,`SELECT
			(SELECT count(*) FROM character_inventory ci WHERE ci.character_id=c.id)+
			(SELECT count(*) FROM character_item_instances ii WHERE ii.character_id=c.id),
			COALESCE((SELECT cap.max_slots FROM character_inventory_capacity cap WHERE cap.character_id=c.id),40)
			FROM characters c WHERE c.id=$1::uuid`,characterID).Scan(&usedSlots,&maxSlots);err!=nil{
			return PurchaseResult{},fmt.Errorf("check buyer inventory capacity: %w",err)
		}
		if usedSlots>=maxSlots{return PurchaseResult{},ErrInventoryFull}
	}

	eventKey:="npc_shop:"+request.RequestID
	ledgerResult,err:=economy.NewService(s.db).ApplyDeltaInTx(ctx,tx,accountID,currencyID,eventKey,"trade",-total,"npc_shop",request.ShopID,"购买"+itemName)
	if err!=nil{return PurchaseResult{},err}
	if !ledgerResult.Applied{return PurchaseResult{},ErrIdempotencyConflict}
	balance:=ledgerResult.AvailableAfter

	if _,err:=tx.ExecContext(ctx,`INSERT INTO character_inventory(character_id,item_id,quantity)
		VALUES($1::uuid,$2,$3)
		ON CONFLICT(character_id,item_id) DO UPDATE
		SET quantity=character_inventory.quantity+EXCLUDED.quantity,updated_at=now()`,
		characterID,request.ItemID,request.Quantity);err!=nil{
		return PurchaseResult{},fmt.Errorf("grant NPC shop item: %w",err)
	}
	if _,err:=tx.ExecContext(ctx,`INSERT INTO npc_shop_purchase_events
		(account_id,character_id,request_id,shop_id,item_id,quantity,currency_id,total_price,balance_after)
		VALUES($1,$2::uuid,$3::uuid,$4,$5,$6,$7,$8,$9)`,
		accountID,characterID,request.RequestID,request.ShopID,request.ItemID,request.Quantity,currencyID,total,balance);err!=nil{
		return PurchaseResult{},fmt.Errorf("record NPC shop purchase: %w",err)
	}
	result:=PurchaseResult{Applied:true,ShopID:request.ShopID,ItemID:request.ItemID,ItemName:itemName,
		Quantity:request.Quantity,CurrencyID:currencyID,TotalPrice:total,BalanceAfter:balance}
	if err:=tx.Commit();err!=nil{return PurchaseResult{},fmt.Errorf("commit NPC shop purchase: %w",err)}
	return result,nil
}
