#include "protocol/frame.hpp"

#ifdef NDEBUG
#undef NDEBUG
#endif
#include <cassert>
#include <cstdint>
#include <string>
#include <vector>

int main() {
    using namespace honghuang::protocol;

    const std::vector<std::uint8_t> heartbeat_payload{};
    const auto encoded = encode_frame(MessageType::Heartbeat, heartbeat_payload);
    Frame decoded{};
    std::string error;
    assert(decode_frame(encoded, decoded, error));
    assert(decoded.version == kVersion);
    assert(decoded.type == MessageType::Heartbeat);
    assert(decoded.payload.empty());

    const std::vector<std::uint8_t> hello_payload{
        0x00, 0x03, 'a', 'b', 'c',
        0x00, 0x04, 't', 'e', 's', 't'
    };
    ClientHello hello{};
    assert(decode_client_hello(hello_payload, hello, error));
    assert(hello.ticket == "abc");
    assert(hello.client_build == "test");

    auto truncated = encoded;
    truncated.pop_back();
    assert(!decode_frame(truncated, decoded, error));

    auto invalid_magic = encoded;
    invalid_magic[0] = 0;
    assert(!decode_frame(invalid_magic, decoded, error));
    return 0;
}
