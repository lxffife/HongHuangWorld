#include "network/chat_delivery_policy.hpp"

#include <cassert>

int main() {
    using honghuang::network::chat_delivery_is_permanent_http_error;

    // Authentication, validation and other permanent client errors require
    // operator intervention rather than an endless retry loop.
    assert(chat_delivery_is_permanent_http_error(400));
    assert(chat_delivery_is_permanent_http_error(401));
    assert(chat_delivery_is_permanent_http_error(403));
    assert(chat_delivery_is_permanent_http_error(404));
    assert(chat_delivery_is_permanent_http_error(409));
    assert(chat_delivery_is_permanent_http_error(422));

    // Transient client responses, network failures (status 0), redirects and
    // server errors remain retryable.
    assert(!chat_delivery_is_permanent_http_error(0));
    assert(!chat_delivery_is_permanent_http_error(301));
    assert(!chat_delivery_is_permanent_http_error(408));
    assert(!chat_delivery_is_permanent_http_error(425));
    assert(!chat_delivery_is_permanent_http_error(429));
    assert(!chat_delivery_is_permanent_http_error(500));
    assert(!chat_delivery_is_permanent_http_error(502));
    assert(!chat_delivery_is_permanent_http_error(503));
    return 0;
}
