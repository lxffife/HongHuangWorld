#include "simulation/support_combat.hpp"

#ifdef NDEBUG
#undef NDEBUG
#endif
#include <cassert>

int main() {
    using namespace honghuang::simulation;
    assert(life_mend_amount(0) == 30);
    assert(life_mend_amount(10) == 50);
    assert(life_mend_amount(-4) == 30);
    assert(life_mend_amount(1000000) == 200030);
    assert(guardian_aegis_amount(100) == 25);
    assert(guardian_aegis_amount(3) == 1);
    assert(guardian_aegis_amount(0) == 0);
    std::int64_t shield = 25;
    assert(absorb_with_shield(10, shield) == 10 && shield == 15);
    assert(absorb_with_shield(30, shield) == 15 && shield == 0);
    assert(absorb_with_shield(5, shield) == 0 && shield == 0);
    shield = 20;
    assert(absorb_with_shield(-5, shield) == 0 && shield == 20);
    assert(support_target_in_range(12.0, 0.0));
    assert(!support_target_in_range(12.01, 0.0));
    assert(!support_target_in_range(0.0, 0.0, 0.0));
}
