#pragma once

namespace honghuang::persistence {

// Outbox delivery handlers accept only their documented success response.
// Network failures, server failures, and explicitly transient HTTP statuses
// should be retried; every other rejected response needs operator attention.
inline bool is_retryable_outbox_http_status(long status) noexcept {
    return status <= 0 || status >= 500 ||
           status == 408 || status == 425 || status == 429;
}

} // namespace honghuang::persistence
