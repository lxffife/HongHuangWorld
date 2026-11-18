package chat

import "testing"

func TestServiceDatabaseModes(t *testing.T) {
	legacy := NewService(nil)
	if legacy.projectionMode {
		t.Fatal("NewService must preserve legacy database mode by default")
	}
	projection := NewProjectionService(nil)
	if !projection.projectionMode {
		t.Fatal("NewProjectionService must enable Chat-owned projection mode")
	}
}
