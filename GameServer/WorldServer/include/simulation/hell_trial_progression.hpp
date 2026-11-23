#pragma once

#include <array>
#include <cstddef>

namespace honghuang::simulation {

// Server-side policy for the eighteen hell trials.
// The final floor is the deepest Abi/Wujian sanctuary; it is not a nineteenth floor.
enum class HellTrialCompletion {
    accepted,
    invalid_floor,
    floor_locked,
    objective_incomplete,
    guardian_alive,
    already_completed
};

class HellTrialProgression {
public:
    static constexpr int floor_count = 18;

    bool can_enter_floor(int floor) const {
        if (!valid_floor(floor)) return false;
        return floor <= highest_unlocked_floor();
    }

    bool is_floor_completed(int floor) const {
        return valid_floor(floor) && completed_[static_cast<std::size_t>(floor - 1)];
    }

    int highest_unlocked_floor() const {
        for (int floor = 1; floor <= floor_count; ++floor) {
            if (!completed_[static_cast<std::size_t>(floor - 1)]) return floor;
        }
        return floor_count;
    }

    bool final_trial_completed() const {
        return is_floor_completed(floor_count);
    }

    HellTrialCompletion complete_floor(
        int floor, bool objective_complete, bool guardian_defeated) {
        if (!valid_floor(floor)) return HellTrialCompletion::invalid_floor;
        if (!can_enter_floor(floor)) return HellTrialCompletion::floor_locked;
        if (is_floor_completed(floor)) return HellTrialCompletion::already_completed;
        if (!objective_complete) return HellTrialCompletion::objective_incomplete;
        if (!guardian_defeated) return HellTrialCompletion::guardian_alive;

        completed_[static_cast<std::size_t>(floor - 1)] = true;
        return HellTrialCompletion::accepted;
    }

private:
    static bool valid_floor(int floor) {
        return floor >= 1 && floor <= floor_count;
    }

    std::array<bool, floor_count> completed_{};
};

} // namespace honghuang::simulation
