#include "simulation/projectile.hpp"

#ifdef NDEBUG
#undef NDEBUG
#endif
#include <cassert>

int main() {
    using honghuang::simulation::advance_projectile;

    float x = 0.0F;
    float z = 0.0F;
    // Swept collision catches a target between the start and end of a fast step.
    assert(advance_projectile(x, z, 20.0F, 0.0F, 0.1F, 1.0F, 0.0F, 0.25F));
    assert(x == 2.0F);

    x = 0.0F;
    z = 0.0F;
    assert(!advance_projectile(x, z, 10.0F, 0.0F, 0.1F, 1.0F, 1.0F, 0.25F));
    assert(x == 1.0F);

    x = 0.0F;
    z = 0.0F;
    assert(advance_projectile(x, z, 0.0F, -10.0F, 0.1F, 0.0F, -0.9F, 0.2F));
    assert(z == -1.0F);

    x = 0.0F;
    z = 0.0F;
    assert(!advance_projectile(x, z, 10.0F, 0.0F, -0.1F, 1.0F, 0.0F, 0.25F));
    assert(x == 0.0F);

    x = 0.0F;
    z = 0.0F;
    assert(!advance_projectile(x, z, 10.0F, 0.0F, 0.1F, 1.0F, 0.0F, 0.0F));
    assert(x == 0.0F);
    return 0;
}
