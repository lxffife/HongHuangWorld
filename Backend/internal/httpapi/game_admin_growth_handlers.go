package httpapi

import (
	"context"
	"database/sql"
	"log/slog"
	"net/http"
	"time"
)

func (h *gamePlayerAdminHandlers) growth(w http.ResponseWriter, r *http.Request) {
	if !h.authorize(w, r) { return }
	accountID := strings.TrimSpace(r.PathValue("accountID"))
	if accountID == "" || len(accountID) > 64 {
		http.Error(w, "invalid account id", http.StatusBadRequest)
		return
	}
	ctx, cancel := context.WithTimeout(r.Context(), 8*time.Second)
	defer cancel()

	var soulID string
	err := h.db.QueryRowContext(ctx, `SELECT id::text FROM souls WHERE account_id=$1::uuid`, accountID).Scan(&soulID)
	if err == sql.ErrNoRows {
		writeJSON(w, http.StatusOK, map[string]any{
			"essence": nil, "inheritance_attributes": nil,
			"absorption_progress": []map[string]any{}, "absorption_records": []map[string]any{},
			"mutation_records": []map[string]any{}, "fusion_records": []map[string]any{},
			"birth_inheritance": []map[string]any{},
		})
		return
	}
	if err != nil {
		h.logger.Error("game admin growth soul lookup failed", "error", err)
		http.Error(w, "internal server error", http.StatusInternalServerError)
		return
	}

	essence, err := queryAdminRows(ctx, h.db, `
		SELECT soul_power,soul_wisdom,soul_resilience,soul_perception,
		       absorption_capacity,absorbed_energy,absorbed_count,updated_at
		FROM soul_essence_attributes WHERE soul_id=$1::uuid`, soulID)
	if err != nil { adminGrowthQueryError(h.logger,w,"essence",err); return }
	inheritance, err := queryAdminRows(ctx,h.db,`
		SELECT strength,constitution,agility,spirit,vitality,updated_at
		FROM soul_inheritance_attributes WHERE soul_id=$1::uuid`,soulID)
	if err != nil { adminGrowthQueryError(h.logger,w,"inheritance attributes",err); return }
	progress, err := queryAdminRows(ctx,h.db,`
		SELECT attribute,absorbed_count,awarded_points,applied_points,max_points,next_threshold,updated_at
		FROM soul_absorption_attribute_progress WHERE soul_id=$1::uuid
		ORDER BY CASE attribute WHEN 'strength' THEN 1 WHEN 'constitution' THEN 2 WHEN 'agility' THEN 3 WHEN 'spirit' THEN 4 ELSE 5 END`,soulID)
	if err != nil { adminGrowthQueryError(h.logger,w,"absorption progress",err); return }
	absorptions, err := queryAdminRows(ctx,h.db,`
		SELECT records.id::text,records.event_id::text,records.source_entity_id,
		       records.absorption_kind_id,kinds.name AS absorption_name,kinds.rarity,
		       kinds.quality_tier,records.energy_gained,records.progress_units,
		       COALESCE(kinds.inheritance_attribute,records.selected_attribute,'') AS attribute,
		       records.attribute_points_awarded,records.created_at
		FROM soul_absorption_records records
		JOIN soul_absorption_kinds kinds ON kinds.id=records.absorption_kind_id
		WHERE records.soul_id=$1::uuid
		ORDER BY records.created_at DESC,records.id DESC LIMIT 100`,soulID)
	if err != nil { adminGrowthQueryError(h.logger,w,"absorption records",err); return }
	mutations, err := queryAdminRows(ctx,h.db,`
		SELECT id::text,event_id::text,mutation_key,mutation_name,description,rarity,
		       attribute,attribute_bonus,created_at
		FROM soul_mutation_records WHERE soul_id=$1::uuid
		ORDER BY created_at DESC,id DESC LIMIT 50`,soulID)
	if err != nil { adminGrowthQueryError(h.logger,w,"mutation records",err); return }
	fusions, err := queryAdminRows(ctx,h.db,`
		SELECT id::text,recipe_id,fusion_name,description,strength_bonus,
		       constitution_bonus,agility_bonus,spirit_bonus,vitality_bonus,created_at
		FROM soul_fusion_records WHERE soul_id=$1::uuid
		ORDER BY created_at DESC,id DESC LIMIT 50`,soulID)
	if err != nil { adminGrowthQueryError(h.logger,w,"fusion records",err); return }
	births, err := queryAdminRows(ctx,h.db,`
		SELECT snapshot.character_id::text,character.name AS character_name,
		       snapshot.life_index,snapshot.source_absorbed_count,
		       snapshot.source_growth_stage,snapshot.source_growth_name,
		       snapshot.source_strength,snapshot.source_constitution,
		       snapshot.source_agility,snapshot.source_spirit,snapshot.source_vitality,
		       snapshot.applied_strength,snapshot.applied_constitution,
		       snapshot.applied_agility,snapshot.applied_spirit,snapshot.applied_vitality,
		       snapshot.dominant_attribute,snapshot.created_at
		FROM character_birth_inheritance snapshot
		JOIN characters character ON character.id=snapshot.character_id
		WHERE snapshot.soul_id=$1::uuid
		ORDER BY snapshot.life_index DESC LIMIT 100`,soulID)
	if err != nil { adminGrowthQueryError(h.logger,w,"birth inheritance",err); return }

	writeJSON(w,http.StatusOK,map[string]any{
		"essence": firstAdminRow(essence),
		"inheritance_attributes": firstAdminRow(inheritance),
		"absorption_progress": progress,
		"absorption_records": absorptions,
		"mutation_records": mutations,
		"fusion_records": fusions,
		"birth_inheritance": births,
		"limits": map[string]int{"absorption_records":100,"mutation_records":50,"fusion_records":50,"birth_inheritance":100},
	})
}

func firstAdminRow(rows []map[string]any) any {
	if len(rows)==0 { return nil }
	return rows[0]
}

func adminGrowthQueryError(logger *slog.Logger,w http.ResponseWriter,section string,err error) {
	logger.Error("game admin player growth query failed","section",section,"error",err)
	http.Error(w,"internal server error",http.StatusInternalServerError)
}

func queryAdminRows(ctx context.Context,db *sql.DB,query string,args ...any)([]map[string]any,error) {
	rows,err:=db.QueryContext(ctx,query,args...)
	if err!=nil{return nil,err}
	defer rows.Close()
	columns,err:=rows.Columns()
	if err!=nil{return nil,err}
	items:=make([]map[string]any,0)
	for rows.Next(){
		values:=make([]any,len(columns))
		dest:=make([]any,len(columns))
		for i:=range values{dest[i]=&values[i]}
		if err:=rows.Scan(dest...);err!=nil{return nil,err}
		item:=make(map[string]any,len(columns))
		for i,column:=range columns{
			switch value:=values[i].(type){
			case []byte:item[column]=string(value)
			default:item[column]=value
			}
		}
		items=append(items,item)
	}
	if err:=rows.Err();err!=nil{return nil,err}
	return items,nil
}
