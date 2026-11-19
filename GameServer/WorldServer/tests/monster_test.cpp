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
