#pragma once

#include "simulation/hell_trial_encounter.hpp"

#include <string>
#include <string_view>

namespace honghuang::simulation {

struct HellTrialWaveTransition {
    bool advanced{};
    bool completed{};
    int stage{};
    std::string unlocked_definition_id;
};

class HellTrialWaveDirector {
public:
    explicit HellTrialWaveDirector(int floor = 0);

    bool enabled() const;
    int stage() const;
    bool completed() const;
    std::string_view active_definition_id() const;
    bool is_unlocked(std::string_view definition_id) const;
    HellTrialWaveTransition record_death(std::string_view definition_id);

private:
    const HellTrialFloorSpec* spec_{};
    int stage_{};
    bool completed_{};
};

} // namespace honghuang::simulation
