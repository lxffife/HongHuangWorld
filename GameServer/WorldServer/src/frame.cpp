#include "protocol/frame.hpp"

#include <limits>

namespace honghuang::protocol {
namespace {
std::uint16_t read_u16(const std::uint8_t* p) {
    return static_cast<std::uint16_t>((static_cast<std::uint16_t>(p[0]) << 8U) |
                                      static_cast<std::uint16_t>(p[1]));
}
std::uint32_t read_u32(const std::uint8_t* p) {
    return (static_cast<std::uint32_t>(p[0]) << 24U) |
           (static_cast<std::uint32_t>(p[1]) << 16U) |
           (static_cast<std::uint32_t>(p[2]) << 8U) |
            static_cast<std::uint32_t>(p[3]);
}
void write_u16(std::vector<std::uint8_t>& out, std::uint16_t v) {
    out.push_back(static_cast<std::uint8_t>((v >> 8U) & 0xffU));
    out.push_back(static_cast<std::uint8_t>(v & 0xffU));
}
void write_u32(std::vector<std::uint8_t>& out, std::uint32_t v) {
    out.push_back(static_cast<std::uint8_t>((v >> 24U) & 0xffU));
    out.push_back(static_cast<std::uint8_t>((v >> 16U) & 0xffU));
    out.push_back(static_cast<std::uint8_t>((v >> 8U) & 0xffU));
    out.push_back(static_cast<std::uint8_t>(v & 0xffU));
}
bool read_string(std::span<const std::uint8_t> data, std::size_t& offset, std::string& out) {
    if (offset + 2U > data.size()) return false;
    const auto size = static_cast<std::size_t>(read_u16(data.data() + offset));
    offset += 2U;
    if (size == 0U || offset + size > data.size()) return false;
    out.assign(reinterpret_cast<const char*>(data.data() + offset), size);
    offset += size;
    return true;
}
} // namespace

bool decode_frame(std::span<const std::uint8_t> bytes, Frame& out, std::string& error) {
    if (bytes.size() < kHeaderSize) { error = "frame header is truncated"; return false; }
    if (read_u32(bytes.data()) != kMagic) { error = "invalid frame magic"; return false; }
    const auto length = static_cast<std::size_t>(read_u32(bytes.data() + 8U));
    if (length > kMaxPayloadSize || bytes.size() != kHeaderSize + length) {
        error = "invalid frame payload length"; return false;
    }
    out.version = read_u16(bytes.data() + 4U);
    out.type = static_cast<MessageType>(read_u16(bytes.data() + 6U));
    out.payload.assign(bytes.begin() + static_cast<std::ptrdiff_t>(kHeaderSize), bytes.end());
    if (out.version != kVersion) { error = "unsupported protocol version"; return false; }
    return true;
}

std::vector<std::uint8_t> encode_frame(MessageType type, std::span<const std::uint8_t> payload) {
    if (payload.size() > kMaxPayloadSize || payload.size() > std::numeric_limits<std::uint32_t>::max()) return {};
    std::vector<std::uint8_t> out;
    out.reserve(kHeaderSize + payload.size());
    write_u32(out, kMagic);
    write_u16(out, kVersion);
    write_u16(out, static_cast<std::uint16_t>(type));
    write_u32(out, static_cast<std::uint32_t>(payload.size()));
    out.insert(out.end(), payload.begin(), payload.end());
    return out;
}

bool decode_client_hello(std::span<const std::uint8_t> payload, ClientHello& out, std::string& error) {
    std::size_t offset = 0;
    if (!read_string(payload, offset, out.ticket) || !read_string(payload, offset, out.client_build) ||
        offset != payload.size() || out.ticket.size() > 128U || out.client_build.size() > 64U) {
        error = "malformed ClientHello"; return false;
    }
    return true;
}
} // namespace honghuang::protocol
