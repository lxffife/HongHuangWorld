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
    std::string_view trial_hint;
    std::string_view guardian_hint;
    int recommended_level{};
    int objective_required{3};
};

struct HellTrialEvidenceSpec {
    std::string_view id;
    std::string_view name;
    std::string_view location_hint;
    std::string_view description;
    std::array<std::string_view, 3> option_ids;
    std::array<std::string_view, 3> option_labels;
    std::string_view correct_option_id;
    float x{};
    float z{};
};

struct HellTrialEvidenceResult {
    bool accepted{};
    bool newly_solved{};
    bool already_solved{};
    bool completed{};
    int solved_count{};
    int required{};
    std::string evidence_id;
    std::string message;
};

const std::array<HellTrialEvidenceSpec, 3>& hell_trial_evidence_specs();

class HellTrialInvestigation {
public:
    explicit HellTrialInvestigation(int floor = 0);
    bool enabled() const;
    bool completed() const;
    int solved_count() const;
    bool is_solved(std::string_view evidence_id) const;
    HellTrialEvidenceResult submit(std::string_view evidence_id, std::string_view option_id);
private:
    bool enabled_{};
    std::unordered_set<std::string> solved_evidence_ids_;
};


enum class HellTrialHazardPhase { Warning, Active, Recovery };

struct HellTrialHazardTransition {
    bool changed{};
    HellTrialHazardPhase phase{HellTrialHazardPhase::Warning};
    int cycle{1};
    double phase_remaining_seconds{};
};

class HellTrialShearHazard {
public:
    explicit HellTrialShearHazard(int floor = 0);
    bool enabled() const;
    HellTrialHazardPhase phase() const;
    int cycle() const;
    double phase_remaining_seconds() const;
    HellTrialHazardTransition update(double delta_seconds);
    bool is_inside_danger_zone(float x, float z) const;
private:
    bool enabled_{};
    HellTrialHazardPhase phase_{HellTrialHazardPhase::Warning};
    int cycle_{1};
    double elapsed_seconds_{};
};

struct HellTrialDeathResult {
    bool objective_kill_recorded{};
    bool guardian_killed{};
    bool completion_ready{};
    int objective_kills{};
    int objective_required{};
    bool guardian_defeated{};
};


struct HellTrialSoulRescueResult {
    bool accepted{};
    bool completed{};
    bool expired{};
    int rescued_count{};
    std::string first_lantern_id;
    std::string message;
};

class HellTrialSoulRescue {
public:
    explicit HellTrialSoulRescue(int floor = 0);
    bool enabled() const;
    bool completed() const;
    int rescued_count() const;
    std::string_view first_lantern_id() const;
    double remaining_seconds(double now_seconds) const;
    HellTrialSoulRescueResult activate(
        std::string_view lantern_id, std::string_view rescuer_id, double now_seconds);
private:
    bool enabled_{};
    bool completed_{};
    std::string first_lantern_id_;
    std::string first_rescuer_id_;
    double deadline_seconds_{};
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
    bool restore_stage(int stage);
    void clamp_player_position(float& x, float& z) const;

    // life_id is unique for each monster life, even when the same spawn point
    // respawns. Repeated death callbacks for one life cannot inflate the counter.
    HellTrialDeathResult record_monster_death(
        std::string_view life_id, std::string_view definition_id);

private:
    int floor_{};
    const HellTrialFloorSpec* spec_{};
    int objective_kills_{};
    bool guardian_defeated_{};
    bool completed_{};
    std::unordered_set<std::string> counted_life_ids_;
};

const std::array<HellTrialFloorSpec, HellTrialEncounter::floor_count>&
hell_trial_floor_specs();

} // namespace honghuang::simulation
