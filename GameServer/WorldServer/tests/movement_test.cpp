#include "simulation/movement.hpp"
#include "simulation/world_obstacles.hpp"

#ifdef NDEBUG
#undef NDEBUG
#endif
#include <cassert>
#include <cmath>
#include <limits>

int main() {
    using namespace honghuang::simulation;

    float x = 3.0F;
    float z = 4.0F;
    assert(normalize_direction(x, z));
    assert(std::abs(x - 0.6F) < 0.0001F);
    assert(std::abs(z - 0.8F) < 0.0001F);

    x = std::numeric_limits<float>::quiet_NaN();
    z = 0.0F;
    assert(!normalize_direction(x, z));

    x = 3.0e38F;
    z = 3.0e38F;
    assert(normalize_direction(x, z));
    assert(std::abs(std::hypot(x, z) - 1.0F) < 0.0001F);

    assert(within_interest_radius(0.0F, 0.0F, 80.0F, 0.0F, 80.0F));
    assert(!within_interest_radius(0.0F, 0.0F, 80.01F, 0.0F, 80.0F));
    assert(within_interest_radius(0.0F, 0.0F, 48.0F, 64.0F, 80.0F));
    assert(!within_interest_radius(0.0F, 0.0F, 0.0F, 0.0F, -1.0F));
    assert(!within_interest_radius(std::numeric_limits<float>::infinity(), 0.0F, 0.0F, 0.0F, 80.0F));

    assert(effective_player_movement_speed(5.0F) == 5.0F);
    assert(effective_player_movement_speed(5.5F) == 5.5F);
    assert(effective_player_movement_speed(0.1F) == 1.0F);
    assert(effective_player_movement_speed(50.0F) == 10.0F);
    assert(effective_player_movement_speed(std::numeric_limits<float>::quiet_NaN()) == 5.0F);
    assert(effective_player_movement_speed(std::numeric_limits<float>::infinity()) == 5.0F);

    float world_x = 99.9F;
    float world_z = 0.0F;
    integrate_horizontal(world_x, world_z, 1.0F, 0.0F, 0.1F);
    assert(std::abs(world_x - 100.0F) < 0.0001F);

    float y = 0.15F;
    float velocity = 0.0F;
    bool jump = true;
    integrate_vertical(y, velocity, jump, 0.05F);
    assert(!jump);
    assert(y > 0.0F);
    for (int i = 0; i < 30; ++i) integrate_vertical(y, velocity, jump, 0.05F);
    assert(y == 0.0F);
    assert(velocity == 0.0F);


    // Fengdu server-authoritative collision: buildings and walls block, gate gaps remain open.
    float city_x = 10.0F;
    float city_z = -95.5F;
    integrate_fengdu_horizontal(city_x, city_z, 0.0F, -1.0F, 0.1F, 5.0F);
    assert(city_z > -96.0F); // north wall blocks entry through solid section

    city_x = 0.0F;
    city_z = -95.5F;
    integrate_fengdu_horizontal(city_x, city_z, 0.0F, -1.0F, 0.1F, 5.0F);
    assert(city_z < -95.5F); // north gate opening is traversable

    city_x = 0.0F;
    city_z = -20.0F;
    integrate_fengdu_horizontal(city_x, city_z, 0.0F, -1.0F, 0.1F, 5.0F);
    assert(city_z < -20.0F); // south gate opening is traversable

    city_x = 7.0F;
    city_z = -81.0F;
    integrate_fengdu_horizontal(city_x, city_z, -1.0F, 0.0F, 0.1F, 5.0F);
    assert(std::abs(city_x - 7.0F) < 0.001F); // imperial palace blocks entry

    city_x = 46.0F;
    city_z = -60.0F;
    integrate_fengdu_horizontal(city_x, city_z, 1.0F, 0.0F, 0.1F, 5.0F);
    assert(city_x > 46.0F); // east gate opening is traversable

    city_x = -46.0F;
    city_z = -60.0F;
    integrate_fengdu_horizontal(city_x, city_z, -1.0F, 0.0F, 0.1F, 5.0F);
    assert(city_x < -46.0F); // west gate opening is traversable

    city_x = 46.0F;
    city_z = -80.0F;
    integrate_fengdu_horizontal(city_x, city_z, 1.0F, 0.0F, 0.1F, 5.0F);
    assert(std::abs(city_x - 46.0F) < 0.001F); // east wall blocks outside the gate

    city_x = 7.0F;
    city_z = -81.5F;
    integrate_fengdu_horizontal(city_x, city_z, -1.0F, 1.0F, 0.1F, 5.0F);
    assert(std::abs(city_x - 7.0F) < 0.001F && city_z > -81.5F); // slide along palace wall

    // The outer moat blocks movement on all four sides, while bridge gaps remain open.
    city_x = 20.0F;
    city_z = -104.3F;
    integrate_fengdu_horizontal(city_x, city_z, 0.0F, 1.0F, 0.1F, 5.0F);
    assert(std::abs(city_z + 104.3F) < 0.001F); // north moat blocks

    city_x = 0.0F;
    city_z = -110.0F;
    for (int step = 0; step < 44; ++step) {
        integrate_fengdu_horizontal(city_x, city_z, 0.0F, 1.0F, 0.1F, 5.0F);
    }
    assert(city_z > -90.0F); // cross the entire north moat and gate

    city_x = 20.0F;
    city_z = -15.7F;
    integrate_fengdu_horizontal(city_x, city_z, 0.0F, -1.0F, 0.1F, 5.0F);
    assert(std::abs(city_z + 15.7F) < 0.001F); // south moat blocks

    city_x = 0.0F;
    city_z = -10.0F;
    for (int step = 0; step < 44; ++step) {
        integrate_fengdu_horizontal(city_x, city_z, 0.0F, -1.0F, 0.1F, 5.0F);
    }
    assert(city_z < -30.0F); // cross the entire south moat and gate

    city_x = -54.3F;
    city_z = -80.0F;
    integrate_fengdu_horizontal(city_x, city_z, 1.0F, 0.0F, 0.1F, 5.0F);
    assert(std::abs(city_x + 54.3F) < 0.001F); // west moat blocks

    city_x = -60.0F;
    city_z = -60.0F;
    for (int step = 0; step < 44; ++step) {
        integrate_fengdu_horizontal(city_x, city_z, 1.0F, 0.0F, 0.1F, 5.0F);
    }
    assert(city_x > -40.0F); // cross the entire west moat and gate

    city_x = 54.3F;
    city_z = -80.0F;
    integrate_fengdu_horizontal(city_x, city_z, -1.0F, 0.0F, 0.1F, 5.0F);
    assert(std::abs(city_x - 54.3F) < 0.001F); // east moat blocks

    city_x = 60.0F;
    city_z = -60.0F;
    for (int step = 0; step < 44; ++step) {
        integrate_fengdu_horizontal(city_x, city_z, -1.0F, 0.0F, 0.1F, 5.0F);
    }
    assert(city_x < 40.0F); // cross the entire east moat and gate

    city_x = 0.0F;
    city_z = 0.0F;
    integrate_fengdu_horizontal(city_x, city_z, 1.0F, 0.0F, 0.1F, 5.0F);
    assert(std::abs(city_x - 0.5F) < 0.0001F); // ordinary open terrain remains unchanged

    return 0;
}
