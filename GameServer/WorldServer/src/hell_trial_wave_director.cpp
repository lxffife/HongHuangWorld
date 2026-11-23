#include "simulation/hell_trial_wave_director.hpp"

namespace honghuang::simulation {

HellTrialWaveDirector::HellTrialWaveDirector(int floor) {
    if (floor >= 1 && floor <= HellTrialEncounter::floor_count) {
        spec_ = &hell_trial_floor_specs()[static_cast<std::size_t>(floor - 1)];
    }
}

bool HellTrialWaveDirector::enabled() const { return spec_ != nullptr; }
int HellTrialWaveDirector::stage() const { return stage_; }
bool HellTrialWaveDirector::completed() const { return completed_; }

bool HellTrialWaveDirector::restore_stage(int stage) {
    if (!enabled() || stage < 0 || stage > 4) return false;
    stage_ = stage;
    completed_ = stage_ == 4;
    return true;
}

std::string_view HellTrialWaveDirector::active_definition_id() const {
    if (!spec_ || completed_) return {};
    if (stage_ < static_cast<int>(spec_->objective_monster_ids.size())) {
        return spec_->objective_monster_ids[static_cast<std::size_t>(stage_)];
    }
    return spec_->guardian_id;
}

bool HellTrialWaveDirector::is_unlocked(std::string_view definition_id) const {
    return !enabled() || (!completed_ && active_definition_id() == definition_id);
}

HellTrialWaveTransition HellTrialWaveDirector::record_death(std::string_view definition_id) {
    HellTrialWaveTransition result;
    result.stage = stage_;
    result.completed = completed_;
    if (!enabled() || completed_ || definition_id.empty() ||
        active_definition_id() != definition_id) {
        return result;
    }

    ++stage_;
    result.advanced = true;
    if (stage_ > static_cast<int>(spec_->objective_monster_ids.size())) {
        completed_ = true;
        result.completed = true;
        result.unlocked_definition_id.clear();
    } else {
        result.unlocked_definition_id = std::string(active_definition_id());
    }
    result.stage = stage_;
    return result;
}

} // namespace honghuang::simulation
