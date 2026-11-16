#include "simulation/movement.hpp"

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

    return 0;
}
