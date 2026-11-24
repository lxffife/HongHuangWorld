#include "persistence/outbox_delivery_policy.hpp"

#include <cassert>

int main() {
    using honghuang::persistence::is_retryable_outbox_http_status;

    // No HTTP response usually means a transport failure; server failures retry.
    assert(is_retryable_outbox_http_status(0));
    assert(is_retryable_outbox_http_status(-1));
    assert(is_retryable_outbox_http_status(500));
    assert(is_retryable_outbox_http_status(502));
    assert(is_retryable_outbox_http_status(503));
    assert(is_retryable_outbox_http_status(599));

    // These client statuses are transient despite being in the 4xx range.
    assert(is_retryable_outbox_http_status(408));
    assert(is_retryable_outbox_http_status(425));
    assert(is_retryable_outbox_http_status(429));

    // Auth, missing routes/resources, redirects, malformed requests, and
    // unexpected success codes must not loop forever as pending deliveries.
    assert(!is_retryable_outbox_http_status(200));
    assert(!is_retryable_outbox_http_status(201));
    assert(!is_retryable_outbox_http_status(204));
    assert(!is_retryable_outbox_http_status(301));
    assert(!is_retryable_outbox_http_status(400));
    assert(!is_retryable_outbox_http_status(401));
    assert(!is_retryable_outbox_http_status(403));
    assert(!is_retryable_outbox_http_status(404));
    assert(!is_retryable_outbox_http_status(422));

    return 0;
}
