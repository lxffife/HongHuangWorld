#include "simulation/monster.hpp"

#ifdef NDEBUG
#undef NDEBUG
#endif
#include <cassert>
#include <cmath>

int main() {
    using namespace honghuang::simulation;

    const MonsterDefinition wolf{
        .id = "wolf",
        .name = "荒原狼",
        .level = 3,
        .max_health = 80.0F,
        .attack = 12.0F,
        .defense = 4.0F,
        .move_speed = 4.0F,
        .aggro_radius = 10.0F,
        .leash_radius = 20.0F,
        .spawn_x = 0.0F,
        .spawn_z = 0.0F
    };
    assert(valid_monster_definition(wolf));
    const auto wolf_profile = monster_attack_profile(wolf);
    assert(wolf_profile.windup_ms == 320 && wolf_profile.cooldown_ms == 900);
    assert(std::string(wolf_profile.style) == "wolf_lunge");

    // Pack members receive separate approach points but remain within melee reach.
    MonsterState pack_left{.x = -6.0F, .z = -6.0F, .health = wolf.max_health};
    MonsterState pack_right{.x = 6.0F, .z = 6.0F, .health = wolf.max_health};
    const MonsterTarget pack_slot_left{.id = "pack-player", .x = 0.0F, .z = 0.0F,
        .alive = true, .approach_x = -0.65F, .approach_z = 0.0F, .has_approach_position = true};
    const MonsterTarget pack_slot_right{.id = "pack-player", .x = 0.0F, .z = 0.0F,
        .alive = true, .approach_x = 0.65F, .approach_z = 0.0F, .has_approach_position = true};
    for (int step = 0; step < 200; ++step) {
        assert(tick_monster(wolf, pack_left, &pack_slot_left, 0.05F));
        assert(tick_monster(wolf, pack_right, &pack_slot_right, 0.05F));
    }
    assert(pack_left.x < 0.0F && pack_right.x > 0.0F);
    // Attack reach is measured from the player, not from the assigned approach point.
    // The approach point is a formation offset, so its own distance is not the melee invariant.
    assert(pack_left.mode == MonsterMode::Chasing);
    assert(pack_right.mode == MonsterMode::Chasing);
    assert(std::hypot(pack_left.x, pack_left.z) <= wolf.attack_range + 0.01F);
    assert(std::hypot(pack_right.x, pack_right.z) <= wolf.attack_range + 0.01F);
    assert(std::hypot(pack_left.x - pack_right.x, pack_left.z - pack_right.z) > 1.0F);

    auto iron_beast = wolf;
    iron_beast.id = "iron_beast";
    iron_beast.name = "铁骨兽";
    const auto iron_profile = monster_attack_profile(iron_beast);
    assert(iron_profile.windup_ms > wolf_profile.windup_ms);
    assert(std::string(iron_profile.style) == "heavy_slam");
    assert(iron_profile.splash_radius >= 3.6F);
    assert(iron_profile.splash_radius < iron_beast.leash_radius);

    auto soul = wolf;
    soul.id = "wind_soul";
    soul.name = "风系游魂";
    const auto soul_profile = monster_attack_profile(soul);
    assert(soul_profile.range >= 6.0F);
    assert(std::string(soul_profile.style) == "soul_bolt");
    soul.attack_range = soul_profile.range;

    // Ranged souls approach from outside attack range, then retreat when rushed.
    MonsterState soul_state{.x = 0.0F, .z = 0.0F, .health = soul.max_health};
    const MonsterTarget distant_player{.id = "player-ranged", .x = 10.0F, .z = 0.0F, .alive = true};
    assert(tick_monster(soul, soul_state, &distant_player, 0.05F));
    assert(soul_state.mode == MonsterMode::Chasing);
    assert(soul_state.x > 0.0F);
    soul_state.x = 0.0F;
    const MonsterTarget close_player{.id = "player-ranged", .x = 3.0F, .z = 0.0F, .alive = true};
    assert(tick_monster(soul, soul_state, &close_player, 0.05F));
    assert(soul_state.x < 0.0F);
    assert(soul_state.yaw < -1.5F);
    assert(std::hypot(soul_state.x - close_player.x, soul_state.z - close_player.z) > 3.0F);

    // Kiting must not push a soul beyond its spawn leash.
    soul_state.x = 19.9F;
    soul_state.z = 0.0F;
    const MonsterTarget flank_player{.id = "player-ranged", .x = 18.0F, .z = 0.0F, .alive = true};
    assert(tick_monster(soul, soul_state, &flank_player, 0.05F));
    assert(soul_state.x <= soul.leash_radius - 0.049F);

    MonsterState state{.x = 0.0F, .z = 0.0F, .health = 80.0F};
    const MonsterTarget player{.id = "player-1", .x = 8.0F, .z = 0.0F, .alive = true};
    assert(tick_monster(wolf, state, &player, 0.05F));
    assert(state.mode == MonsterMode::Chasing);
    assert(state.target_id == "player-1");
    assert(state.x > 0.0F && state.x < player.x);
    assert(std::abs(state.yaw + 1.5707963F) < 0.001F);

    // Chase stops at attack range instead of walking into the player's position.
    state.x = 0.0F;
    state.z = 0.0F;
    for (int step = 0; step < 200; ++step) {
        assert(tick_monster(wolf, state, &player, 0.05F));
    }
    assert(state.mode == MonsterMode::Chasing);
    assert(std::abs(state.x - (player.x - wolf.attack_range)) < 0.01F);

    // The existing target gets a small hysteresis margin to avoid aggro flicker.
    const MonsterTarget retained_player{.id = "player-1", .x = 10.5F, .z = 0.0F, .alive = true};
    assert(tick_monster(wolf, state, &retained_player, 0.05F));
    assert(state.mode == MonsterMode::Chasing);

    const MonsterTarget far_player{.id = "player-1", .x = 100.0F, .z = 0.0F, .alive = true};
    state.x = 25.0F;
    state.z = 0.0F;
    assert(tick_monster(wolf, state, &far_player, 0.05F));
    assert(state.mode == MonsterMode::Returning);
    assert(state.target_id.empty());
    assert(state.x < 25.0F);
    assert(std::abs(state.yaw - 1.5707963F) < 0.001F);

    state.health = 0.0F;
    assert(tick_monster(wolf, state, nullptr, 0.05F));
    assert(state.mode == MonsterMode::Dead);
    assert(state.health == 0.0F);

    auto invalid = wolf;
    invalid.leash_radius = 2.0F;
    assert(!valid_monster_definition(invalid));
    invalid = wolf;
    invalid.attack_range = invalid.leash_radius;
    assert(!valid_monster_definition(invalid));
    assert(!tick_monster(wolf, state, nullptr, -0.1F));
    return 0;
}
