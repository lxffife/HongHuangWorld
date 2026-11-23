#include "simulation/hell_trial_contribution.hpp"

#include <algorithm>
#include <limits>

namespace honghuang::simulation {

bool HellTrialContributionLedger::register_participant(
    const std::string& character_id, const std::string& session_id) {
    if (character_id.empty() || session_id.empty()) return false;
    auto [it, inserted] = participants_.try_emplace(character_id, Participant{session_id, 0, 0});
    if (!inserted) it->second.session_id = session_id;
    return true;
}

bool HellTrialContributionLedger::record_damage(
    const std::string& character_id, const std::string& session_id,
    std::int64_t effective_damage) {
    if (effective_damage <= 0 || character_id.empty() || session_id.empty()) return false;
    const auto found = participants_.find(character_id);
    if (found == participants_.end() || found->second.session_id != session_id) return false;
    auto& total = found->second.damage;
    if (total > std::numeric_limits<std::int64_t>::max() - effective_damage)
        total = std::numeric_limits<std::int64_t>::max();
    else
        total += effective_damage;
    return true;
}

bool HellTrialContributionLedger::record_healing(
    const std::string& character_id, const std::string& session_id,
    std::int64_t effective_healing) {
    if (effective_healing <= 0 || character_id.empty() || session_id.empty()) return false;
    const auto found = participants_.find(character_id);
    if (found == participants_.end() || found->second.session_id != session_id) return false;
    auto& total = found->second.healing;
    if (total > std::numeric_limits<std::int64_t>::max() - effective_healing)
        total = std::numeric_limits<std::int64_t>::max();
    else
        total += effective_healing;
    return true;
}

std::vector<HellTrialEligibleParticipant>
HellTrialContributionLedger::eligible_participants(std::int64_t minimum_contribution) const {
    std::vector<HellTrialEligibleParticipant> result;
    if (minimum_contribution <= 0) return result;
    result.reserve(participants_.size());
    for (const auto& [character_id, participant] : participants_) {
        const auto support_score = participant.healing / 2;
        const auto contribution = participant.damage > std::numeric_limits<std::int64_t>::max() - support_score
            ? std::numeric_limits<std::int64_t>::max() : participant.damage + support_score;
        if (contribution >= minimum_contribution) {
            result.push_back({character_id, participant.session_id, contribution});
        }
    }
    std::sort(result.begin(), result.end(), [](const auto& left, const auto& right) {
        return left.character_id < right.character_id;
    });
    return result;
}

std::int64_t HellTrialContributionLedger::contribution_for(const std::string& character_id) const {
    const auto found = participants_.find(character_id);
    if (found == participants_.end()) return 0;
    const auto support_score = found->second.healing / 2;
    return found->second.damage > std::numeric_limits<std::int64_t>::max() - support_score
        ? std::numeric_limits<std::int64_t>::max() : found->second.damage + support_score;
}

} // namespace honghuang::simulation
