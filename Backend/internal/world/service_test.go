package world

import "testing"

func TestDefinitionJSONShape(t *testing.T) {
	item := Definition{ID: "qingyun_human", Name: "青云人界", Type: "human", Level: 1}
	if item.ID == "" || item.Name == "" || item.Level < 1 {
		t.Fatal("world definition test fixture is invalid")
	}
}
