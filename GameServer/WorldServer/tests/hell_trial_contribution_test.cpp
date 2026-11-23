#include "simulation/hell_trial_contribution.hpp"

#include <cassert>
#include <cstdint>
#include <limits>

using honghuang::simulation::HellTrialContributionLedger;

int main() {
    HellTrialContributionLedger ledger;
    assert(!ledger.register_participant("", "session-a"));
    assert(!ledger.register_participant("char-a", ""));
    assert(ledger.register_participant("char-a", "session-a"));
    assert(ledger.register_participant("char-b", "session-b"));

    // Unregistered characters and stale sessions cannot claim contribution.
    assert(!ledger.record_damage("char-c", "session-c", 500));
    assert(!ledger.record_damage("char-a", "old-session", 500));
    assert(!ledger.record_damage("char-a", "session-a", 0));
    assert(ledger.record_damage("char-a", "session-a", 20));
    assert(ledger.record_damage("char-b", "session-b", 8));
    assert(ledger.eligible_participants(10).size() == 1);

    // Reconnecting rotates the authenticated session but preserves earned damage.
    assert(ledger.register_participant("char-a", "session-a-reconnected"));
    assert(!ledger.record_damage("char-a", "session-a", 100));
    assert(ledger.record_damage("char-a", "session-a-reconnected", 15));
    auto eligible = ledger.eligible_participants(30);
    assert(eligible.size() == 1);
    assert(eligible.front().character_id == "char-a");
    assert(eligible.front().session_id == "session-a-reconnected");
    assert(eligible.front().damage == 35);

    // Accumulation saturates rather than overflowing into a negative value.
    assert(ledger.record_damage("char-a", "session-a-reconnected",
                                std::numeric_limits<std::int64_t>::max()));
    assert(ledger.damage_for("char-a") == std::numeric_limits<std::int64_t>::max());
    assert(ledger.eligible_participants(std::numeric_limits<std::int64_t>::max()).size() == 1);
    assert(ledger.eligible_participants(0).empty());
    return 0;
}
