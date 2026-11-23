#pragma once

#include <array>
#include <cstddef>
#include <string>
#include <string_view>
#include <unordered_set>

namespace honghuang::simulation {

struct HellTrialFloorSpec {
    int floor{};
    std::string_view name;
    std::array<std::string_view, 3> objective_monster_ids;
    std::array<std::string_view, 3> objective_monster_names;
    std::string_view guardian_id;
    std::string_view guardian_name;
    int recommended_level{};
    int objective_required{3};
};

struct HellTrialDeathResult {
    bool objective_kill_recorded{};
    bool guardian_killed{};
    bool completion_ready{};
    int objective_kills{};
    int objective_required{};
    bool guardian_defeated{};
};

class HellTrialEncounter {
public:
    static constexpr int floor_count = 18;

    explicit HellTrialEncounter(int floor = 0);

    bool enabled() const;
    int floor() const;
    const HellTrialFloorSpec* spec() const;
    int objective_kills() const;
    bool guardian_defeated() const;
    bool completed() const;
    void clamp_player_position(float& x, float& z) const;

    // runtime_id identifies one spawn point/life. Repeated death callbacks for
    // the same life cannot inflate the objective counter.
    HellTrialDeathResult record_monster_death(
        std::string_view runtime_id, std::string_view definition_id);

private:
    int floor_{};
    const HellTrialFloorSpec* spec_{};
    int objective_kills_{};
    bool guardian_defeated_{};
    bool completed_{};
    std::unordered_set<std::string> counted_runtime_ids_;
};

const std::array<HellTrialFloorSpec, HellTrialEncounter::floor_count>&
hell_trial_floor_specs();

} // namespace honghuang::simulation
