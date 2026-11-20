#pragma once

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <string_view>

namespace honghuang::simulation {

enum class SpellElement {
    Fire,
    Ice,
    Lightning,
    Life
};

struct SpellDefinition {
    std::string_view id;
    SpellElement element;
    std::int32_t mana_cost;
    std::int32_t cast_time_ms;
    std::int32_t cooldown_ms;
    float range;
    float projectile_speed;
    float projectile_lifetime_seconds;
    std::int32_t power_basis_points;
    std::int32_t defense_penetration_basis_points;
    bool enabled;
};

// Spell IDs and all combat values are selected by the server. The client may
// request an ID, but it must never submit or override any value in this table.
inline constexpr SpellDefinition kFireballSpell{
    "fireball", SpellElement::Fire, 18, 350, 1800,
    20.0F, 16.0F, 1.8F, 12500, 0, true
};

inline const SpellDefinition* find_spell_definition(std::string_view id) {
    if (id == kFireballSpell.id) return &kFireballSpell;
    return nullptr;
}

inline bool valid_spell_definition(const SpellDefinition& spell) {
    return !spell.id.empty() &&
        spell.mana_cost > 0 && spell.mana_cost <= 100000 &&
        spell.cast_time_ms >= 0 && spell.cast_time_ms <= 30000 &&
        spell.cooldown_ms > 0 && spell.cooldown_ms <= 300000 &&
        std::isfinite(spell.range) && spell.range > 0.0F && spell.range <= 200.0F &&
        std::isfinite(spell.projectile_speed) && spell.projectile_speed > 0.0F &&
        spell.projectile_speed <= 200.0F &&
        std::isfinite(spell.projectile_lifetime_seconds) &&
        spell.projectile_lifetime_seconds > 0.0F &&
        spell.projectile_lifetime_seconds <= 30.0F &&
        spell.power_basis_points > 0 && spell.power_basis_points <= 100000 &&
        spell.defense_penetration_basis_points >= 0 &&
        spell.defense_penetration_basis_points <= 10000;
}

inline bool can_pay_spell_cost(std::int64_t current_mana, std::int32_t mana_cost) {
    return current_mana >= 0 && mana_cost > 0 && current_mana >= mana_cost;
}

} // namespace honghuang::simulation
