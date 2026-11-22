#pragma once

#include <algorithm>
#include <array>
#include <cstdint>
#include <string_view>

namespace honghuang::simulation {

// Mastery is tracked independently for each spell. XP is awarded only for
// server-confirmed hits; callers must not invoke this for casts or misses.
inline constexpr std::int32_t kSpellMasteryMaxLevel = 10;
inline constexpr std::int64_t kSpellMasteryMaxXp = 4500;
inline constexpr std::int32_t kSpellMasteryXpPerHitCap = 10;
inline constexpr std::array<std::int64_t, kSpellMasteryMaxLevel> kSpellMasteryLevelXp{
    0, 100, 300, 600, 1000, 1500, 2100, 2800, 3600, 4500
};

struct SpellMastery {
    std::string_view spell_id;
    std::int64_t experience{};
    std::int32_t level{1};
};

inline std::int32_t spell_mastery_level(std::int64_t experience) {
    const auto xp = std::clamp<std::int64_t>(experience, 0, kSpellMasteryMaxXp);
    std::int32_t level = 1;
    for (std::size_t i = 1; i < kSpellMasteryLevelXp.size(); ++i) {
        if (xp < kSpellMasteryLevelXp[i]) break;
        level = static_cast<std::int32_t>(i + 1);
    }
    return level;
}

// A confirmed hit grants at most 10 mastery XP. Invalid IDs, misses (zero XP),
// negative values, and attempts to exceed the cap cannot advance progression.
inline SpellMastery award_spell_mastery_xp(SpellMastery mastery,
                                            std::int32_t confirmed_hit_xp) {
    if (mastery.spell_id.empty() || mastery.spell_id.size() > 64) return mastery;
    if (confirmed_hit_xp <= 0) return mastery;
    const auto award = std::min(confirmed_hit_xp, kSpellMasteryXpPerHitCap);
    mastery.experience = std::clamp<std::int64_t>(
        mastery.experience, 0, kSpellMasteryMaxXp);
    mastery.experience = std::min<std::int64_t>(
        kSpellMasteryMaxXp, mastery.experience + award);
    mastery.level = spell_mastery_level(mastery.experience);
    return mastery;
}

// Each level above 1 adds 1% spell power, capped at +9% at level 10.
inline std::int32_t spell_mastery_power_bonus_basis_points(std::int32_t level) {
    const auto safe_level = std::clamp(level, 1, kSpellMasteryMaxLevel);
    return (safe_level - 1) * 100;
}

} // namespace honghuang::simulation
