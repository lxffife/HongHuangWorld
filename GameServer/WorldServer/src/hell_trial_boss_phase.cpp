#include "simulation/hell_trial_boss_phase.hpp"

#include <algorithm>
#include <cmath>

namespace honghuang::simulation {

HellTrialBossPhaseTransition HellTrialBossPhaseController::update(
    double health, double max_health) {
    HellTrialBossPhaseTransition result;
    result.phase = phase_;
    if (!std::isfinite(health) || !std::isfinite(max_health) || max_health <= 0.0)
        return result;

    const double ratio = std::clamp(health / max_health, 0.0, 1.0);
    int desired_phase = ratio <= 0.30 ? 3 : (ratio <= 0.65 ? 2 : 1);
    desired_phase = std::max(phase_, desired_phase);
    result.health_ratio = ratio;
    if (desired_phase != phase_) {
        phase_ = desired_phase;
        result.changed = true;
    }
    result.phase = phase_;
    return result;
}

int HellTrialBossPhaseController::phase() const { return phase_; }

void HellTrialBossPhaseController::reset() { phase_ = 0; }

double HellTrialBossPhaseController::attack_multiplier() const {
    if (phase_ >= 3) return 1.60;
    if (phase_ == 2) return 1.25;
    return 1.0;
}

double HellTrialBossPhaseController::tempo_multiplier() const {
    if (phase_ >= 3) return 0.75;
    if (phase_ == 2) return 0.90;
    return 1.0;
}

MonsterAttackProfile HellTrialBossPhaseController::attack_profile(
    const MonsterDefinition& definition, int floor) const {
    auto profile = monster_attack_profile(definition);
    if (phase_ < 2 || floor < 1 || floor > 18) return profile;

    if (phase_ >= 3) {
        profile.windup_ms = 900;
        profile.recovery_ms = 700;
        profile.cooldown_ms = 2500;
        profile.splash_radius = std::min(
            6.8F, 5.0F + static_cast<float>(floor) * 0.1F);
        profile.range = profile.splash_radius;
        profile.style = "heavy_slam";
        return profile;
    }

    // Phase two introduces a floor-themed signature attack. The mapping is
    // deterministic so every WorldServer instance presents the same pattern.
    switch ((floor - 1) % 6) {
    case 0:
        profile.windup_ms = 720;
        profile.recovery_ms = 650;
        profile.cooldown_ms = 2200;
        profile.range = 7.0F;
        profile.style = "soul_bolt";
        break;
    case 1:
        profile.windup_ms = 500;
        profile.recovery_ms = 480;
        profile.cooldown_ms = 1350;
        profile.range = 2.8F;
        profile.style = "blade_slash";
        break;
    case 2:
        profile.windup_ms = 760;
        profile.recovery_ms = 680;
        profile.cooldown_ms = 2200;
        profile.range = 7.0F;
        profile.style = "poison_bolt";
        break;
    case 3:
        profile.windup_ms = 820;
        profile.recovery_ms = 720;
        profile.cooldown_ms = 2300;
        profile.range = 7.0F;
        profile.style = "frost_bolt";
        break;
    case 4:
        profile.windup_ms = 950;
        profile.recovery_ms = 800;
        profile.cooldown_ms = 2500;
        profile.splash_radius = 4.2F + static_cast<float>(floor) * 0.04F;
        profile.range = profile.splash_radius;
        profile.style = "heavy_slam";
        break;
    default:
        profile.windup_ms = 620;
        profile.recovery_ms = 560;
        profile.cooldown_ms = 1650;
        profile.range = 3.0F;
        profile.style = "blade_slash";
        break;
    }
    return profile;
}

} // namespace honghuang::simulation
