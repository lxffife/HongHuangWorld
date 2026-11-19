package httpapi

import (
    "context"
    "database/sql"
    "encoding/json"
    "fmt"
)

type configRevisionQueryer interface {
    QueryRowContext(context.Context, string, ...any) *sql.Row
}

func readConfigSnapshot(ctx context.Context, q configRevisionQueryer, table, where string, args ...any) (json.RawMessage, error) {
    // table and where are selected only by trusted server-side call sites.
    var snapshot []byte
    err := q.QueryRowContext(ctx, "SELECT to_jsonb(t) FROM "+table+" t WHERE "+where, args...).Scan(&snapshot)
    if err != nil {
        return nil, err
    }
    return json.RawMessage(snapshot), nil
}

func recordConfigRevision(ctx context.Context, tx *sql.Tx, resourceType, resourceID, changeKind string, oldSnapshot, newSnapshot json.RawMessage) error {
    if resourceType == "" || resourceID == "" {
        return fmt.Errorf("revision resource identity is required")
    }
    if changeKind != "create" && changeKind != "update" && changeKind != "delete" && changeKind != "rollback" {
        return fmt.Errorf("invalid revision change kind")
    }
    if _, err := tx.ExecContext(ctx, "SELECT pg_advisory_xact_lock(hashtext($1))", resourceType+":"+resourceID); err != nil {
        return err
    }
    var next int
    if err := tx.QueryRowContext(ctx, "SELECT COALESCE(MAX(revision_number),0)+1 FROM game_config_revisions WHERE resource_type=$1 AND resource_id=$2", resourceType, resourceID).Scan(&next); err != nil {
        return err
    }
    _, err := tx.ExecContext(ctx, `INSERT INTO game_config_revisions(resource_type,resource_id,revision_number,old_snapshot,new_snapshot,change_kind)
        VALUES($1,$2,$3,$4::jsonb,$5::jsonb,$6)`, resourceType, resourceID, next, nullableJSON(oldSnapshot), nullableJSON(newSnapshot), changeKind)
    return err
}

func nullableJSON(value json.RawMessage) any {
    if len(value) == 0 || string(value) == "null" {
        return nil
    }
    return string(value)
}

func listConfigRevisions(ctx context.Context, db *sql.DB, resourceType, resourceID string, limit int) ([]map[string]any, error) {
    rows, err := db.QueryContext(ctx, `SELECT id,resource_type,resource_id,revision_number,old_snapshot,new_snapshot,change_kind,created_at
        FROM game_config_revisions
        WHERE ($1='' OR resource_type=$1) AND ($2='' OR resource_id=$2)
        ORDER BY created_at DESC,id DESC LIMIT $3`, resourceType, resourceID, limit)
    if err != nil { return nil, err }
    defer rows.Close()
    items := make([]map[string]any, 0)
    for rows.Next() {
        var id int64
        var kind, resource, resourceIDValue, change string
        var revision int
        var oldValue, newValue []byte
        var created any
        if err := rows.Scan(&id,&kind,&resourceIDValue,&revision,&oldValue,&newValue,&change,&created); err != nil { return nil, err }
        item := map[string]any{"id":id,"resource_type":kind,"resource_id":resourceIDValue,"revision_number":revision,"change_kind":change,"created_at":created}
        if len(oldValue)>0 { item["old_snapshot"]=json.RawMessage(oldValue) }
        if len(newValue)>0 { item["new_snapshot"]=json.RawMessage(newValue) }
        items=append(items,item)
    }
    return items, rows.Err()
}
