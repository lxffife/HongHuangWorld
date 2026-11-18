#pragma once

namespace honghuang::network {

// Treat permanent client errors as operator-actionable dead letters. Timeouts,
// throttling and server-side failures remain retryable because they may recover.
inline bool chat_delivery_is_permanent_http_error(long status) noexcept {
    return status >= 400 && status < 500 &&
           status != 408 && status != 425 && status != 429;
}

} // namespace honghuang::network
