package identityadmin

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"net/url"
	"strings"
	"time"
)

var ErrUnavailable = errors.New("identity administration service unavailable")

type Account struct {
	ID string `json:"id"`
	Username string `json:"username"`
	Email *string `json:"email,omitempty"`
	Status string `json:"status"`
	CreatedAt time.Time `json:"created_at"`
}

type AccountPage struct { Items []Account `json:"items"` }

type Client struct { baseURL string; apiKey string; httpClient *http.Client }

func New(baseURL,apiKey string) *Client {
	return &Client{baseURL:strings.TrimRight(strings.TrimSpace(baseURL),"/"),apiKey:strings.TrimSpace(apiKey),httpClient:&http.Client{Timeout:5*time.Second}}
}

func (c *Client) ready() bool { return c.baseURL!="" && c.apiKey!="" }

func (c *Client) ListAccounts(ctx context.Context,q string,limit int)(AccountPage,error) {
	if !c.ready(){return AccountPage{},ErrUnavailable}
	u:=c.baseURL+"/api/v1/internal/admin/accounts?q="+url.QueryEscape(q)+"&limit="+fmt.Sprint(limit)
	req,err:=http.NewRequestWithContext(ctx,http.MethodGet,u,nil);if err!=nil{return AccountPage{},err}
	req.Header.Set("X-Identity-Service-Key",c.apiKey)
	resp,err:=c.httpClient.Do(req);if err!=nil{return AccountPage{},fmt.Errorf("%w: %v",ErrUnavailable,err)};defer resp.Body.Close()
	if resp.StatusCode!=http.StatusOK{return AccountPage{},fmt.Errorf("%w: identity returned %d",ErrUnavailable,resp.StatusCode)}
	var page AccountPage;if err:=json.NewDecoder(resp.Body).Decode(&page);err!=nil{return AccountPage{},err};return page,nil
}

func (c *Client) SetAccountStatus(ctx context.Context,id,status string) error {
	if !c.ready(){return ErrUnavailable}
	body,_:=json.Marshal(map[string]string{"status":status})
	req,err:=http.NewRequestWithContext(ctx,http.MethodPatch,c.baseURL+"/api/v1/internal/admin/accounts/"+url.PathEscape(id)+"/status",bytes.NewReader(body));if err!=nil{return err}
	req.Header.Set("Content-Type","application/json");req.Header.Set("X-Identity-Service-Key",c.apiKey)
	resp,err:=c.httpClient.Do(req);if err!=nil{return fmt.Errorf("%w: %v",ErrUnavailable,err)};defer resp.Body.Close()
	if resp.StatusCode==http.StatusNotFound{return fmt.Errorf("identity account not found")}
	if resp.StatusCode<200||resp.StatusCode>=300{return fmt.Errorf("%w: identity returned %d",ErrUnavailable,resp.StatusCode)}
	return nil
}
