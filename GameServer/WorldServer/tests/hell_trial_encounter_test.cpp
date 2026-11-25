#include "simulation/hell_trial_encounter.hpp"

#include <cassert>
#include <limits>
#include <string>
#include <unordered_set>

using honghuang::simulation::HellTrialEncounter;
using honghuang::simulation::HellTrialInvestigation;
using honghuang::simulation::hell_trial_floor_specs;

int main() {
    const auto& specs = hell_trial_floor_specs();
    assert(specs.size() == 18);
    std::unordered_set<std::string> guardian_ids;
    std::unordered_set<std::string> objective_ids;
    int previous_recommended_level = 0;
    for (const auto& spec : specs) {
        assert(guardian_ids.emplace(spec.guardian_id).second);
        assert(!spec.trial_hint.empty());
        assert(!spec.guardian_hint.empty());
        assert(spec.recommended_level > previous_recommended_level);
        previous_recommended_level = spec.recommended_level;
        for (const auto id : spec.objective_monster_ids) assert(objective_ids.emplace(id).second);
    }
    for (int floor = 1; floor <= HellTrialEncounter::floor_count; ++floor) {
        HellTrialEncounter encounter(floor);
        assert(encounter.enabled());
        assert(encounter.floor() == floor);
        assert(encounter.spec() != nullptr);
        assert(!encounter.spec()->name.empty());
        assert(!encounter.spec()->guardian_id.empty());
        assert(!encounter.spec()->trial_hint.empty());
        assert(!encounter.spec()->guardian_hint.empty());
        assert(encounter.spec()->objective_required == 3);
        assert(!encounter.completed());
    }

    HellTrialEncounter arena(3);
    float arena_x = 42.0F;
    float arena_z = -35.0F;
    arena.clamp_player_position(arena_x, arena_z);
    assert(arena_x == 27.0F && arena_z == -27.0F);
    HellTrialEncounter ordinary(0);
    float ordinary_x = 42.0F;
    float ordinary_z = -35.0F;
    ordinary.clamp_player_position(ordinary_x, ordinary_z);
    assert(ordinary_x == 42.0F && ordinary_z == -35.0F);

    HellTrialEncounter invalid(19);
    assert(!invalid.enabled());
    assert(invalid.floor() == 0);

    HellTrialEncounter encounter(1);
    auto result = encounter.record_monster_death("mob-a", "hell_f01_tongue_wraith");
    assert(result.objective_kill_recorded && result.objective_kills == 1);
    result = encounter.record_monster_death("mob-a", "hell_f01_tongue_wraith");
    assert(!result.objective_kill_recorded && result.objective_kills == 1);
    result = encounter.record_monster_death("mob-b", "hell_f01_sin_clerk");
    assert(result.objective_kill_recorded && result.objective_kills == 2);
    result = encounter.record_monster_death("mob-c", "hell_f01_echo_ghost");
    assert(result.objective_kill_recorded && result.objective_kills == 3);
    assert(!result.completion_ready); // Objective alone cannot complete the floor.

    result = encounter.record_monster_death("boss-1", "hell_f01_tongue_jailer");
    assert(result.guardian_killed && result.guardian_defeated);
    assert(result.completion_ready);
    assert(encounter.completed());

    result = encounter.record_monster_death("boss-1", "hell_f01_tongue_jailer");
    assert(!result.completion_ready); // Completion callback is emitted only once.

    HellTrialEncounter respawn(1);
    result = respawn.record_monster_death("spawn-a-life-1", "hell_f01_tongue_wraith");
    assert(result.objective_kills == 1 && result.objective_kill_recorded);
    result = respawn.record_monster_death("spawn-a-life-1", "hell_f01_tongue_wraith");
    assert(result.objective_kills == 1 && !result.objective_kill_recorded);
    // The same spawn point gets a new life ID after respawn and counts once more.
    result = respawn.record_monster_death("spawn-a-life-2", "hell_f01_tongue_wraith");
    assert(result.objective_kills == 2 && result.objective_kill_recorded);
    result = respawn.record_monster_death("spawn-a-life-3", "hell_f01_tongue_wraith");
    assert(result.objective_kills == 3 && result.objective_kill_recorded);
    // The required count is capped; additional respawns cannot inflate snapshots.
    result = respawn.record_monster_death("spawn-a-life-4", "hell_f01_tongue_wraith");
    assert(result.objective_kills == 3 && !result.objective_kill_recorded);

    HellTrialEncounter recovered(1);
    assert(recovered.restore_stage(2));
    assert(recovered.objective_kills() == 2);
    assert(!recovered.guardian_defeated() && !recovered.completed());
    assert(!recovered.restore_stage(5));
    assert(recovered.restore_stage(4));
    assert(recovered.objective_kills() == 3);
    assert(recovered.guardian_defeated() && recovered.completed());

    HellTrialEncounter boss_first(18);
    result = boss_first.record_monster_death("boss-18", "hell_f18_abyss_judge");
    assert(result.guardian_killed && !result.completion_ready);
    boss_first.record_monster_death("mob-18a", "hell_f18_void_blade");
    boss_first.record_monster_death("mob-18b", "hell_f18_abyssal_chain");
    result = boss_first.record_monster_death("mob-18c", "hell_f18_last_sinner");
    assert(result.objective_kills == 3 && result.completion_ready);

    std::unordered_set<std::string> evidence_ids;
    for (const auto& evidence_spec : honghuang::simulation::hell_trial_evidence_specs()) {
        assert(evidence_ids.emplace(evidence_spec.id).second);
        assert(!evidence_spec.name.empty() && !evidence_spec.location_hint.empty());
        assert(!evidence_spec.description.empty());
        assert(evidence_spec.x >= -27.0F && evidence_spec.x <= 27.0F);
        assert(evidence_spec.z >= -27.0F && evidence_spec.z <= 27.0F);
        bool correct_option_exists = false;
        for (const auto option_id : evidence_spec.option_ids) {
            if (option_id == evidence_spec.correct_option_id) correct_option_exists = true;
        }
        assert(correct_option_exists);
    }

    HellTrialInvestigation investigation(1);
    assert(investigation.enabled() && !investigation.completed());
    auto evidence = investigation.submit("registry_seal", "before_third_bell");
    assert(!evidence.accepted && investigation.solved_count() == 0);
    evidence = investigation.submit("unknown_clue", "after_third_bell");
    assert(!evidence.accepted);
    evidence = investigation.submit("registry_seal", "after_third_bell");
    assert(evidence.accepted && evidence.newly_solved && evidence.solved_count == 1);
    evidence = investigation.submit("registry_seal", "after_third_bell");
    assert(evidence.accepted && evidence.already_solved && evidence.solved_count == 1);
    evidence = investigation.submit("echo_stone", "west_corridor");
    assert(evidence.accepted && evidence.solved_count == 2 && !evidence.completed);
    evidence = investigation.submit("soul_lantern", "after_replacement");
    assert(evidence.accepted && evidence.completed && investigation.completed());
    HellTrialInvestigation other_floor(2);
    assert(!other_floor.enabled());
    assert(!other_floor.submit("registry_seal", "after_third_bell").accepted);



    HellTrialSoulRescue soul_rescue(3);
    assert(soul_rescue.enabled() && !soul_rescue.completed());
    auto rescue = soul_rescue.activate("west", "character-a", 100.0);
    assert(rescue.accepted && rescue.rescued_count == 1 && !rescue.completed);
    assert(soul_rescue.remaining_seconds(104.0) == 11.0);
    rescue = soul_rescue.activate("east", "character-a", 105.0);
    assert(!rescue.accepted && !rescue.completed); // Must be a different teammate.
    rescue = soul_rescue.activate("west", "character-b", 106.0);
    assert(!rescue.accepted && !rescue.completed); // Cannot double-activate one lantern.
    rescue = soul_rescue.activate("east", "character-b", 107.0);
    assert(rescue.accepted && rescue.completed && rescue.rescued_count == 2);
    assert(soul_rescue.completed() && soul_rescue.rescued_count() == 2);
    rescue = soul_rescue.activate("west", "character-c", 108.0);
    assert(rescue.accepted && rescue.completed && rescue.rescued_count == 2);

    HellTrialSoulRescue expired_rescue(3);
    rescue = expired_rescue.activate("east", "character-a", 10.0);
    assert(rescue.accepted && expired_rescue.rescued_count() == 1);
    rescue = expired_rescue.activate("west", "character-b", 26.0);
    assert(rescue.accepted && rescue.expired && !rescue.completed);
    assert(rescue.rescued_count == 1 && rescue.first_lantern_id == "west");
    HellTrialSoulRescue ticking_rescue(3);
    ticking_rescue.activate("west", "character-a", 50.0);
    assert(!ticking_rescue.update(64.9));
    assert(ticking_rescue.update(65.0));
    assert(ticking_rescue.rescued_count() == 0);
    assert(ticking_rescue.first_lantern_id().empty());
    assert(!ticking_rescue.update(66.0));

    HellTrialSoulRescue disabled_rescue(2);
    assert(!disabled_rescue.enabled());
    assert(!disabled_rescue.activate("west", "character-a", 1.0).accepted);

    HellTrialShearHazard shear(2);
    assert(shear.enabled() && shear.phase() == honghuang::simulation::HellTrialHazardPhase::Warning);
    assert(shear.is_inside_danger_zone(0.0F, 0.0F));
    assert(!shear.is_inside_danger_zone(-12.0F, 0.0F));
    assert(!shear.is_inside_danger_zone(12.0F, 0.0F));
    assert(!shear.is_inside_danger_zone(std::numeric_limits<float>::quiet_NaN(), 0.0F));
    auto hazard = shear.update(2.4);
    assert(!hazard.changed && hazard.phase == honghuang::simulation::HellTrialHazardPhase::Warning);
    hazard = shear.update(0.2);
    assert(hazard.changed && hazard.phase == honghuang::simulation::HellTrialHazardPhase::Active);
    assert(hazard.cycle == 1);
    hazard = shear.update(1.8);
    assert(hazard.changed && hazard.phase == honghuang::simulation::HellTrialHazardPhase::Recovery);
    hazard = shear.update(3.7);
    assert(hazard.changed && hazard.phase == honghuang::simulation::HellTrialHazardPhase::Warning);
    assert(hazard.cycle == 2);
    HellTrialShearHazard disabled_shear(3);
    assert(!disabled_shear.enabled());
    assert(!disabled_shear.update(20.0).changed);

    HellTrialEncounter unrelated(7);
    result = unrelated.record_monster_death("mob-x", "hell_f01_tongue_wraith");
    assert(!result.objective_kill_recorded);
    assert(!result.guardian_killed);
    return 0;
}
