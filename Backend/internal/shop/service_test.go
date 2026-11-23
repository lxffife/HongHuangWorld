package shop

import "testing"

func TestValidPurchaseRequest(t *testing.T) {
	valid := PurchaseRequest{
		RequestID: "2b1c7f1a-8d11-4d29-9f43-5c4cba0a6a10",
		ShopID: "fengdu_elixir_shop",
		ItemID: "minor_health_pill",
		Quantity: 3,
	}
	if !validPurchaseRequest("account-1", valid) {
		t.Fatal("expected a well-formed purchase request to be valid")
	}
}

func TestValidPurchaseRequestRejectsInvalidFields(t *testing.T) {
	tests := []struct {
		name string
		accountID string
		request PurchaseRequest
	}{
		{name:"missing account",accountID:"",request:PurchaseRequest{RequestID:"2b1c7f1a-8d11-4d29-9f43-5c4cba0a6a10",ShopID:"fengdu_elixir_shop",ItemID:"minor_health_pill",Quantity:1}},
		{name:"invalid request id",accountID:"account-1",request:PurchaseRequest{RequestID:"not-a-uuid",ShopID:"fengdu_elixir_shop",ItemID:"minor_health_pill",Quantity:1}},
		{name:"missing shop",accountID:"account-1",request:PurchaseRequest{RequestID:"2b1c7f1a-8d11-4d29-9f43-5c4cba0a6a10",ItemID:"minor_health_pill",Quantity:1}},
		{name:"missing item",accountID:"account-1",request:PurchaseRequest{RequestID:"2b1c7f1a-8d11-4d29-9f43-5c4cba0a6a10",ShopID:"fengdu_elixir_shop",Quantity:1}},
		{name:"zero quantity",accountID:"account-1",request:PurchaseRequest{RequestID:"2b1c7f1a-8d11-4d29-9f43-5c4cba0a6a10",ShopID:"fengdu_elixir_shop",ItemID:"minor_health_pill",Quantity:0}},
		{name:"quantity over limit",accountID:"account-1",request:PurchaseRequest{RequestID:"2b1c7f1a-8d11-4d29-9f43-5c4cba0a6a10",ShopID:"fengdu_elixir_shop",ItemID:"minor_health_pill",Quantity:100}},
	}
	for _,tt:=range tests{
		t.Run(tt.name,func(t *testing.T){
			if validPurchaseRequest(tt.accountID,tt.request){t.Fatal("expected invalid purchase request")}
		})
	}
}
