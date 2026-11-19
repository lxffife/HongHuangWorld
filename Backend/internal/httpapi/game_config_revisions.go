package httpapi

import (
    "context"
    "database/sql"
    "encoding/json"
    "fmt"
    "strings"
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
    return recordConfigRevisionWithReason(ctx, tx, resourceType, resourceID, changeKind, oldSnapshot, newSnapshot, "")
}

func recordConfigRevisionWithReason(ctx context.Context, tx *sql.Tx, resourceType, resourceID, changeKind string, oldSnapshot, newSnapshot json.RawMessage, reason string) error {
    if resourceType == "" || resourceID == "" {
        return fmt.Errorf("revision resource identity is required")
    }
    if len(reason) > 300 { return fmt.Errorf("revision reason exceeds 300 characters") }
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
    _, err := tx.ExecContext(ctx, `INSERT INTO game_config_revisions(resource_type,resource_id,revision_number,old_snapshot,new_snapshot,change_kind,reason)
        VALUES($1,$2,$3,$4::jsonb,$5::jsonb,$6,$7)`, resourceType, resourceID, next, nullableJSON(oldSnapshot), nullableJSON(newSnapshot), changeKind, reason)
    return err
}

func nullableJSON(value json.RawMessage) any {
    if len(value) == 0 || string(value) == "null" {
        return nil
    }
    return string(value)
}

func listConfigRevisions(ctx context.Context, db *sql.DB, resourceType, resourceID string, limit int) ([]map[string]any, error) {
    rows, err := db.QueryContext(ctx, `SELECT id,resource_type,resource_id,revision_number,old_snapshot,new_snapshot,change_kind,reason,created_at
        FROM game_config_revisions
        WHERE ($1='' OR resource_type=$1) AND ($2='' OR resource_id=$2)
        ORDER BY created_at DESC,id DESC LIMIT $3`, resourceType, resourceID, limit)
    if err != nil { return nil, err }
    defer rows.Close()
    items := make([]map[string]any, 0)
    for rows.Next() {
        var id int64
        var kind, resourceIDValue, change, reason string
        var revision int
        var oldValue, newValue []byte
        var created any
        if err := rows.Scan(&id,&kind,&resourceIDValue,&revision,&oldValue,&newValue,&change,&reason,&created); err != nil { return nil, err }
        item := map[string]any{"id":id,"resource_type":kind,"resource_id":resourceIDValue,"revision_number":revision,"change_kind":change,"reason":reason,"created_at":created}
        if len(oldValue)>0 { item["old_snapshot"]=json.RawMessage(oldValue) }
        if len(newValue)>0 { item["new_snapshot"]=json.RawMessage(newValue) }
        items=append(items,item)
    }
    return items, rows.Err()
}

var errRevisionRollbackConflict = fmt.Errorf("configuration revision cannot be restored because current game data depends on it")

func restoreConfigSnapshot(ctx context.Context, tx *sql.Tx, resourceType, resourceID string, snapshot json.RawMessage) error {
    switch resourceType {
    case "monster_definition":
        if len(snapshot)==0 {
            _,err:=tx.ExecContext(ctx,`DELETE FROM monster_definitions WHERE id=$1`,resourceID);return err
        }
        var v struct{Name string `json:"name"`;Level int `json:"level"`;MaxHealth float64 `json:"max_health"`;Attack float64 `json:"attack"`;Defense float64 `json:"defense"`;MoveSpeed float64 `json:"move_speed"`;AggroRadius float64 `json:"aggro_radius"`;LeashRadius float64 `json:"leash_radius"`;Enabled bool `json:"enabled"`}
        if err:=json.Unmarshal(snapshot,&v);err!=nil{return err}
        if v.LeashRadius<v.AggroRadius{return fmt.Errorf("invalid monster snapshot")}
        result,err:=tx.ExecContext(ctx,`UPDATE monster_definitions SET name=$2,level=$3,max_health=$4,attack=$5,defense=$6,move_speed=$7,aggro_radius=$8,leash_radius=$9,enabled=$10,updated_at=now() WHERE id=$1`,resourceID,v.Name,v.Level,v.MaxHealth,v.Attack,v.Defense,v.MoveSpeed,v.AggroRadius,v.LeashRadius,v.Enabled)
        if err!=nil{return err};affected,_:=result.RowsAffected();if affected==0{return errRevisionRollbackConflict};return nil
    case "monster_spawn_point":
        if len(snapshot)==0 { _,err:=tx.ExecContext(ctx,`DELETE FROM world_monster_spawn_points WHERE id=$1`,resourceID);return err }
        var v struct{SpawnX float64 `json:"spawn_x"`;SpawnZ float64 `json:"spawn_z"`;RareSpawn bool `json:"rare_spawn"`;SpawnChancePercent int `json:"spawn_chance_percent"`;RetrySpawnSeconds int `json:"retry_spawn_seconds"`;FirstSpawnDelaySeconds int `json:"first_spawn_delay_seconds"`;Enabled bool `json:"enabled"`}
        if err:=json.Unmarshal(snapshot,&v);err!=nil{return err}
        result,err:=tx.ExecContext(ctx,`UPDATE world_monster_spawn_points SET spawn_x=$2,spawn_z=$3,rare_spawn=$4,spawn_chance_percent=$5,retry_spawn_seconds=$6,first_spawn_delay_seconds=$7,enabled=$8,updated_at=now() WHERE id=$1`,resourceID,v.SpawnX,v.SpawnZ,v.RareSpawn,v.SpawnChancePercent,v.RetrySpawnSeconds,v.FirstSpawnDelaySeconds,v.Enabled)
        if err!=nil{return err};affected,_:=result.RowsAffected();if affected==0{return errRevisionRollbackConflict};return nil
    case "item_definition":
        if len(snapshot)==0 { _,err:=tx.ExecContext(ctx,`DELETE FROM item_definitions WHERE id=$1`,resourceID);return err }
        var v struct{Name string `json:"name"`;Description string `json:"description"`;IconKey string `json:"icon_key"`;MaxStack int `json:"max_stack"`;Enabled bool `json:"enabled"`}
        if err:=json.Unmarshal(snapshot,&v);err!=nil{return err}
        var used int
        if err:=tx.QueryRowContext(ctx,`SELECT GREATEST(COALESCE((SELECT MAX(quantity) FROM character_inventory WHERE item_id=$1),0),COALESCE((SELECT MAX(max_quantity) FROM monster_loot_entries WHERE item_id=$1),0),COALESCE((SELECT MAX(quantity) FROM ground_drops WHERE item_id=$1 AND status='available'),0))`,resourceID).Scan(&used);err!=nil{return err}
        if v.MaxStack<used{return errRevisionRollbackConflict}
        result,err:=tx.ExecContext(ctx,`UPDATE item_definitions SET name=$2,description=$3,icon_key=$4,max_stack=$5,enabled=$6,updated_at=now() WHERE id=$1`,resourceID,v.Name,v.Description,v.IconKey,v.MaxStack,v.Enabled)
        if err!=nil{return err};affected,_:=result.RowsAffected();if affected==0{return errRevisionRollbackConflict};return nil
    case "monster_loot_entry":
        parts:=strings.SplitN(resourceID,":",2);if len(parts)!=2{return fmt.Errorf("invalid loot revision identity")}
        if len(snapshot)==0 { _,err:=tx.ExecContext(ctx,`DELETE FROM monster_loot_entries WHERE monster_id=$1 AND item_id=$2`,parts[0],parts[1]);return err }
        var v struct{DropChanceBP int `json:"drop_chance_bp"`;MinQuantity int `json:"min_quantity"`;MaxQuantity int `json:"max_quantity"`}
        if err:=json.Unmarshal(snapshot,&v);err!=nil{return err}
        var maxStack int
        if err:=tx.QueryRowContext(ctx,`SELECT max_stack FROM item_definitions WHERE id=$1 AND enabled=TRUE FOR SHARE`,parts[1]).Scan(&maxStack);err!=nil{return err}
        if v.MaxQuantity>maxStack{return errRevisionRollbackConflict}
        if _,err:=tx.ExecContext(ctx,`SELECT pg_advisory_xact_lock(hashtext($1))`,parts[0]);err!=nil{return err}
        var otherTotal int
        if err:=tx.QueryRowContext(ctx,`SELECT COALESCE(SUM(drop_chance_bp),0)::int FROM monster_loot_entries WHERE monster_id=$1 AND item_id<>$2`,parts[0],parts[1]).Scan(&otherTotal);err!=nil{return err}
        if otherTotal+v.DropChanceBP>10000{return errRevisionRollbackConflict}
        _,err:=tx.ExecContext(ctx,`INSERT INTO monster_loot_entries(monster_id,item_id,drop_chance_bp,min_quantity,max_quantity) VALUES($1,$2,$3,$4,$5) ON CONFLICT(monster_id,item_id) DO UPDATE SET drop_chance_bp=EXCLUDED.drop_chance_bp,min_quantity=EXCLUDED.min_quantity,max_quantity=EXCLUDED.max_quantity`,parts[0],parts[1],v.DropChanceBP,v.MinQuantity,v.MaxQuantity)
        return err
    default:
        return fmt.Errorf("unsupported revision resource type")
    }
}
