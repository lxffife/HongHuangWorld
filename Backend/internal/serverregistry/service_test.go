package serverregistry

import (
	"context"
	"errors"
	"testing"
)

func TestSetAdminStateRejectsInvalidInputBeforeDatabaseAccess(t *testing.T) {
	service := NewService(nil)
	cases := []struct {
		name string
		nodeKey string
		state string
	}{
		{name:"empty node key",nodeKey:"",state:"draining"},
		{name:"unknown state",nodeKey:"node-1",state:"stopped"},
		{name:"state cannot be blank",nodeKey:"node-1",state:""},
	}
	for _, tc := range cases {
		t.Run(tc.name,func(t *testing.T) {
			_, err := service.SetAdminState(context.Background(),tc.nodeKey,tc.state)
			if !errors.Is(err,ErrInvalidNodeState) { t.Fatalf("expected ErrInvalidNodeState, got %v",err) }
		})
	}
}
