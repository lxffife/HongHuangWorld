#pragma once

#include <cstdint>
#include <string>
#include <unordered_map>
#include <vector>

namespace honghuang::simulation {

struct HellTrialEligibleParticipant {
    std::string character_id;
    std::string session_id;
    std::int64_t damage{};
};

// Tracks authenticated participation for one dedicated hell-floor instance.
// Damage is retained when a character reconnects with a new session ID.
class HellTrialContributionLedger {
public:
    bool register_participant(const std::string& character_id, const std::string& session_id);
    bool record_damage(const std::string& character_id, const std::string& session_id,
                       std::int64_t effective_damage);
    std::vector<HellTrialEligibleParticipant> eligible_participants(
        std::int64_t minimum_damage) const;
    std::int64_t damage_for(const std::string& character_id) const;

private:
    struct Participant {
        std::string session_id;
        std::int64_t damage{};
    };
    std::unordered_map<std::string, Participant> participants_;
};

} // namespace honghuang::simulation
