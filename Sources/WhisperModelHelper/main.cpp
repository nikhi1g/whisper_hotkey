#include <whisper.h>
#include <ggml-backend.h>

#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>

#include <algorithm>
#include <cerrno>
#include <cmath>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <chrono>
#include <cctype>
#include <iostream>
#include <limits>
#include <map>
#include <memory>
#include <sstream>
#include <string>
#include <unordered_map>
#include <vector>

namespace {

constexpr std::size_t kMaximumCommandBytes = 65'536;
constexpr std::size_t kMaximumWaveBytes = 64 * 1024 * 1024;
constexpr std::size_t kMaximumResultBytes = 1'048'576;
constexpr std::size_t kMaximumWords = 4'096;
constexpr std::size_t kMaximumSegments = 1'024;
constexpr std::size_t kMaximumTokensPerWord = 256;
constexpr float kAdaptiveMinimumAverageLogProbability = -0.55f;
constexpr float kAdaptiveMaximumWeakTokenFraction = 0.05f;
constexpr float kAdaptiveMaximumNoSpeechProbability = 0.50f;

// A vocabulary-biasing prompt (e.g. the internal dictionary) only has real
// speech to bias when the clip actually contains audible signal. When a clip
// is silence or bare room noise, the prompt has nothing legitimate to help
// recognize, and whisper's decoder can instead "continue" the prompt as if it
// were prior transcript, echoing prompt entries verbatim into the output.
// Real dictated speech (even quietly spoken) sits roughly an order of
// magnitude above this normalized RMS floor; below it, we suppress the
// prompt so decoding falls back to its unprimed behavior rather than risking
// a confident hallucination of prompt vocabulary.
constexpr float kMinimumPromptSignalRms = 0.02f;

struct Options {
    std::string model_path;
    int threads = 4;
    int beam_size = 5;
    bool require_coreml = false;
    whisper_sampling_strategy strategy = WHISPER_SAMPLING_BEAM_SEARCH;
    bool adaptive = false;

    int protocol_version = 1;
    std::string request_id;
    std::string request_pass = "primaryFullSession";
    std::string requested_strategy = "beam";
    bool emit_timestamps = false;
    bool emit_token_data = false;
    long long sample_start = -1;
    long long sample_end = -1;
};

struct TimedWordInfo {
    std::string text;
    float start_seconds = 0.0f;
    float end_seconds = 0.0f;
    float posterior = 0.0f;
    std::vector<int> token_ids;
    std::vector<float> token_log_probabilities;
};

struct SegmentInfo {
    std::string text;
    float start_seconds = 0.0f;
    float end_seconds = 0.0f;
    std::vector<std::size_t> word_indices;
};

struct DecodeResult {
    std::string text;
    float average_log_probability = -std::numeric_limits<float>::infinity();
    float weak_token_fraction = 1.0f;
    float maximum_no_speech_probability = 1.0f;
    bool has_repetition = false;
    std::vector<TimedWordInfo> words;
    std::vector<SegmentInfo> segments;
};

std::string json_escape(const std::string & value) {
    static const char hex[] = "0123456789abcdef";
    std::string escaped;
    escaped.reserve(value.size() + 16);
    for (const unsigned char byte : value) {
        switch (byte) {
            case '"': escaped += "\\\""; break;
            case '\\': escaped += "\\\\"; break;
            case '\b': escaped += "\\b"; break;
            case '\f': escaped += "\\f"; break;
            case '\n': escaped += "\\n"; break;
            case '\r': escaped += "\\r"; break;
            case '\t': escaped += "\\t"; break;
            default:
                if (byte < 0x20) {
                    escaped += "\\u00";
                    escaped += hex[(byte >> 4) & 0x0f];
                    escaped += hex[byte & 0x0f];
                } else {
                    escaped.push_back(static_cast<char>(byte));
                }
        }
    }
    return escaped;
}

void emit_ready() {
    std::cout << "{\"event\":\"ready\"}" << std::endl;
}

void emit_result_legacy(
    const Options & options,
    const DecodeResult & result,
    bool adaptive_fallback,
    long long sample_start,
    long long sample_end
) {
    const float sequence_score = std::max(
        0.0f,
        1.0f - result.weak_token_fraction
    );

    std::cout << "{\"protocolVersion\":" << options.protocol_version << ","
              << "\"event\":\"result\",";
    std::cout << "\"requestID\":\""
              << json_escape(options.request_id) << "\",";
    std::cout << "\"engine\":\"whisperTurbo\",";
    std::cout << "\"pass\":\""
              << json_escape(options.request_pass) << "\",";
    std::cout << "\"text\":\""
              << json_escape(result.text) << "\",";
    std::cout << "\"window\":{"
              << "\"startSample\":" << sample_start << ","
              << "\"endSample\":" << sample_end << ","
              << "\"sampleRate\":16000},";
    std::cout << "\"latencyMs\":0.0,";
    std::cout << "\"sequenceScore\":" << sequence_score << ",";
    std::cout << "\"averageLogProbability\":"
              << result.average_log_probability << ",";
    std::cout << "\"noSpeechProbability\":"
              << result.maximum_no_speech_probability << ",";
    std::cout << "\"weakTokenFraction\":"
              << result.weak_token_fraction << ",";
    std::cout << "\"repetitionDetected\":"
              << (result.has_repetition ? "true" : "false") << ",";

    std::cout << "\"words\":";
    if (options.emit_token_data) {
        std::cout << "[";
        for (std::size_t index = 0; index < result.words.size(); ++index) {
            const TimedWordInfo & word = result.words[index];
            if (index > 0) {
                std::cout << ",";
            }
            std::cout << "{\"text\":\"" << json_escape(word.text)
                      << "\",";
            if (std::isfinite(word.start_seconds)) {
                std::cout << "\"startSeconds\":" << word.start_seconds << ",";
            } else {
                std::cout << "\"startSeconds\":null,";
            }
            if (std::isfinite(word.end_seconds)) {
                std::cout << "\"endSeconds\":" << word.end_seconds << ",";
            } else {
                std::cout << "\"endSeconds\":null,";
            }
            if (std::isfinite(word.posterior)) {
                std::cout << "\"confidence\":" << word.posterior;
            } else {
                std::cout << "\"confidence\":null";
            }
            std::cout << "}";
        }
        std::cout << "]";
    } else {
        std::cout << "[]";
    }

    std::cout << ",\"metadata\":{"
              << "\"adaptiveFallback\":"
              << (adaptive_fallback ? "true" : "false")
              << ",\"requestedStrategy\":\"";
    const char * resolved_strategy = "beam";
    if (options.adaptive) {
        resolved_strategy = "adaptive";
    } else if (options.strategy == WHISPER_SAMPLING_GREEDY) {
        resolved_strategy = "greedy";
    }
    std::cout << resolved_strategy << "\",";
    std::cout << "\"emitTimestamps\":"
              << (options.emit_timestamps ? "true" : "false")
              << ",\"emitTokenData\":"
              << (options.emit_token_data ? "true" : "false");

    if (options.emit_timestamps) {
        std::cout << ",\"segments\":";
        std::cout << "[";
        for (std::size_t index = 0; index < result.segments.size(); ++index) {
            const SegmentInfo & segment = result.segments[index];
            if (index > 0) {
                std::cout << ",";
            }
            std::cout << "{\"text\":\""
                      << json_escape(segment.text) << "\",";
            if (std::isfinite(segment.start_seconds)) {
                std::cout << "\"startSeconds\":" << segment.start_seconds << ",";
            } else {
                std::cout << "\"startSeconds\":null,";
            }
            if (std::isfinite(segment.end_seconds)) {
                std::cout << "\"endSeconds\":" << segment.end_seconds;
            } else {
                std::cout << "\"endSeconds\":null";
            }
            std::cout << "}";
        }
        std::cout << "]";
    } else {
        std::cout << ",\"segments\":null";
    }

    std::cout << "}}" << std::endl;
}

int emit_error(
    const std::string & code,
    const std::string & message,
    int status
);

std::string model_identifier(const Options & options) {
    const std::size_t slash = options.model_path.find_last_of('/');
    return slash == std::string::npos
        ? options.model_path
        : options.model_path.substr(slash + 1);
}

std::string session_identifier(const Options & options) {
    // Swift normally sends a UUID request ID.  Keep a valid deterministic
    // fallback for older callers that used a human-readable request label.
    if (options.request_id.size() == 36
        && options.request_id[8] == '-'
        && options.request_id[13] == '-'
        && options.request_id[18] == '-'
        && options.request_id[23] == '-') {
        return options.request_id;
    }
    return "00000000-0000-0000-0000-000000000000";
}

const char * resolved_strategy(
    const Options & options,
    bool adaptive_fallback
) {
    if (!options.requested_strategy.empty()) {
        return options.requested_strategy.c_str();
    }
    (void) adaptive_fallback;
    return options.strategy == WHISPER_SAMPLING_GREEDY
        ? "greedy"
        : "beam";
}

std::size_t utf8_character_count(const std::string & value) {
    std::size_t count = 0;
    for (std::size_t index = 0; index < value.size(); ++index) {
        const unsigned char byte = static_cast<unsigned char>(value[index]);
        if ((byte & 0xc0U) != 0x80U) {
            ++count;
        }
    }
    return count;
}

void append_json_float(std::ostringstream * output, float value) {
    if (std::isfinite(value)) {
        *output << value;
    } else {
        *output << "null";
    }
}

void append_json_double(std::ostringstream * output, double value) {
    if (std::isfinite(value)) {
        *output << value;
    } else {
        *output << "null";
    }
}

void append_word_id(
    std::ostringstream * output,
    const Options & options,
    std::size_t word_index
) {
    *output << "{\"session_id\":\""
            << json_escape(session_identifier(options))
            << "\",\"provider_decode_id\":\""
            << json_escape(options.request_id.empty() ? "helper" : options.request_id)
            << "\",\"word_index\":" << word_index << '}';
}

void append_json_word(
    std::ostringstream * output,
    const Options & options,
    const TimedWordInfo & word,
    std::size_t word_index
) {
    *output << "{\"id\":";
    append_word_id(output, options, word_index);
    *output << ",\"text\":\"" << json_escape(word.text)
            << "\",\"start_seconds\":";
    append_json_float(output, word.start_seconds);
    *output << ",\"end_seconds\":";
    append_json_float(output, word.end_seconds);
    *output << ",\"raw_evidence\":{\"token_ids\":[";
    for (std::size_t index = 0; index < word.token_ids.size(); ++index) {
        if (index > 0) {
            *output << ',';
        }
        *output << word.token_ids[index];
    }
    *output << "],\"token_log_probabilities\":[";
    for (std::size_t index = 0;
         index < word.token_log_probabilities.size();
         ++index) {
        if (index > 0) {
            *output << ',';
        }
        append_json_float(output, word.token_log_probabilities[index]);
    }
    *output << ']';
    unsigned int availability = 0;
    if (!word.token_ids.empty()) {
        availability |= 1U;
    }
    if (!word.token_log_probabilities.empty()) {
        availability |= 2U;
    }
    const float posterior = std::max(
        0.0f,
        std::min(1.0f, word.posterior)
    );
    if (std::isfinite(word.posterior)) {
        *output << ",\"posterior\":";
        append_json_float(output, posterior);
        availability |= 4U;
    }
    *output << ",\"availability\":" << availability << "}}";
}

int emit_result(
    const Options & options,
    const DecodeResult & result,
    bool adaptive_fallback,
    long long sample_start,
    long long sample_end,
    const std::string & prompt,
    double latency_ms
) {
    if (options.protocol_version < 2) {
        emit_result_legacy(
            options,
            result,
            adaptive_fallback,
            sample_start,
            sample_end
        );
        return 0;
    }

    const float sequence_score = std::max(
        0.0f,
        1.0f - result.weak_token_fraction
    );
    std::ostringstream output;
    output << "{\"protocol_version\":2,\"event\":\"result\",";
    output << "\"request_id\":\"" << json_escape(options.request_id)
           << "\",\"result\":{";
    output << "\"session_id\":\"" << json_escape(session_identifier(options))
           << "\",\"generation\":0,\"engine\":\"whisperTurbo\",";
    output << "\"model\":{\"identifier\":\""
           << json_escape(model_identifier(options))
           << "\",\"compute_units\":\"metal\"},";
    output << "\"pass\":\"" << json_escape(options.request_pass)
           << "\",\"text\":\"" << json_escape(result.text)
           << "\",\"words\":";
    if (options.emit_token_data) {
        output << '[';
        for (std::size_t index = 0;
             index < result.words.size() && index < kMaximumWords;
             ++index) {
            if (index > 0) {
                output << ',';
            }
            append_json_word(&output, options, result.words[index], index);
        }
        output << ']';
    } else {
        output << "[]";
    }
    output << ",\"segments\":[";
    if (options.emit_timestamps) {
        for (std::size_t index = 0;
             index < result.segments.size() && index < kMaximumSegments;
             ++index) {
            const SegmentInfo & segment = result.segments[index];
            if (index > 0) {
                output << ',';
            }
            output << "{\"text\":\"" << json_escape(segment.text)
                   << "\",\"start_seconds\":";
            append_json_float(&output, segment.start_seconds);
            output << ",\"end_seconds\":";
            append_json_float(&output, segment.end_seconds);
            output << ",\"word_ids\":[";
            for (std::size_t word = 0;
                 word < segment.word_indices.size();
                 ++word) {
                if (word > 0) {
                    output << ',';
                }
                append_word_id(&output, options, segment.word_indices[word]);
            }
            output << "]}";
        }
    }
    output << "],\"alternatives\":[]";
    output << ",\"utterance_evidence\":{";
    output << "\"sequence_score\":";
    append_json_float(&output, sequence_score);
    output << ",\"average_log_probability\":";
    append_json_float(&output, result.average_log_probability);
    output << ",\"no_speech_probability\":";
    append_json_float(&output, result.maximum_no_speech_probability);
    output << ",\"maximum_no_speech_probability\":";
    append_json_float(&output, result.maximum_no_speech_probability);
    output << ",\"weak_token_fraction\":";
    append_json_float(&output, result.weak_token_fraction);
    output << ",\"repetition_detected\":"
           << (result.has_repetition ? "true" : "false") << '}';
    output << ",\"timing\":{\"audio_duration_seconds\":";
    append_json_double(
        &output,
        sample_end > sample_start
            ? static_cast<double>(sample_end - sample_start) / 16'000.0
            : 0.0
    );
    output << ",\"decode_duration_seconds\":";
    append_json_double(&output, latency_ms / 1'000.0);
    output << "},\"completeness\":\"finalSession\"";
    output << ",\"pass_metadata\":{";
    output << "\"strategy\":\""
           << resolved_strategy(options, adaptive_fallback)
           << "\",\"beam_size\":" << options.beam_size
           << ",\"used_prompt\":" << (!prompt.empty() ? "true" : "false")
           << ",\"prompt_character_count\":"
           << utf8_character_count(prompt)
           << ",\"protocol_version\":2,\"request_id\":\""
           << json_escape(options.request_id)
           << "\",\"adaptive_fallback\":"
           << (adaptive_fallback ? "true" : "false") << "}}}";

    const std::string line = output.str();
    if (line.size() > kMaximumResultBytes) {
        return emit_error(
            "result_too_large",
            "recognition result exceeded the protocol bound",
            71
        );
    }
    std::cout << line << std::endl;
    return 0;
}

int emit_error(
    const std::string & code,
    const std::string & message,
    int status
) {
    std::cout << "{\"event\":\"error\",\"code\":\""
              << json_escape(code)
              << "\",\"message\":\""
              << json_escape(message)
              << "\"}" << std::endl;
    return status;
}

bool parse_positive_int(const char * value, int * output) {
    if (value == nullptr || *value == '\0') {
        return false;
    }
    char * end = nullptr;
    errno = 0;
    const long parsed = std::strtol(value, &end, 10);
    if (errno != 0 || end == value || *end != '\0'
        || parsed <= 0 || parsed > std::numeric_limits<int>::max()) {
        return false;
    }
    *output = static_cast<int>(parsed);
    return true;
}

bool parse_non_negative_long_long(const char * value, long long * output) {
    if (value == nullptr || *value == '\0') {
        return false;
    }
    char * end = nullptr;
    errno = 0;
    const long long parsed = std::strtoll(value, &end, 10);
    if (errno != 0 || end == value || *end != '\0' || parsed < 0) {
        return false;
    }
    *output = parsed;
    return true;
}

bool parse_bool_value(const char * value, bool * output) {
    if (value == nullptr || *value == '\0') {
        return false;
    }
    if (std::strcmp(value, "true") == 0 || std::strcmp(value, "1") == 0) {
        *output = true;
        return true;
    }
    if (std::strcmp(value, "false") == 0 || std::strcmp(value, "0") == 0) {
        *output = false;
        return true;
    }
    return false;
}

bool parse_options(int argc, char ** argv, Options * options) {
    for (int index = 1; index < argc; ++index) {
        const std::string argument(argv[index]);
        if (argument == "--model" && index + 1 < argc) {
            options->model_path = argv[++index];
        } else if (argument == "--threads" && index + 1 < argc) {
            if (!parse_positive_int(argv[++index], &options->threads)) {
                return false;
            }
        } else if (argument == "--beam-size" && index + 1 < argc) {
            if (!parse_positive_int(argv[++index], &options->beam_size)) {
                return false;
            }
        } else if (argument == "--strategy" && index + 1 < argc) {
            const std::string strategy(argv[++index]);
            options->requested_strategy = strategy;
            if (strategy == "beam") {
                options->strategy = WHISPER_SAMPLING_BEAM_SEARCH;
            } else if (strategy == "greedy") {
                options->strategy = WHISPER_SAMPLING_GREEDY;
            } else if (strategy == "adaptive") {
                options->strategy = WHISPER_SAMPLING_GREEDY;
                options->adaptive = true;
            } else {
                return false;
            }
        } else if (argument == "--require-coreml") {
            options->require_coreml = true;
        } else {
            return false;
        }
    }
    return !options->model_path.empty();
}

void append_utf8(std::string * output, std::uint32_t scalar) {
    if (scalar <= 0x7f) {
        output->push_back(static_cast<char>(scalar));
    } else if (scalar <= 0x7ff) {
        output->push_back(static_cast<char>(0xc0 | (scalar >> 6)));
        output->push_back(static_cast<char>(0x80 | (scalar & 0x3f)));
    } else if (scalar <= 0xffff) {
        output->push_back(static_cast<char>(0xe0 | (scalar >> 12)));
        output->push_back(
            static_cast<char>(0x80 | ((scalar >> 6) & 0x3f))
        );
        output->push_back(static_cast<char>(0x80 | (scalar & 0x3f)));
    } else {
        output->push_back(static_cast<char>(0xf0 | (scalar >> 18)));
        output->push_back(
            static_cast<char>(0x80 | ((scalar >> 12) & 0x3f))
        );
        output->push_back(
            static_cast<char>(0x80 | ((scalar >> 6) & 0x3f))
        );
        output->push_back(static_cast<char>(0x80 | (scalar & 0x3f)));
    }
}

int hex_value(char character) {
    if (character >= '0' && character <= '9') {
        return character - '0';
    }
    if (character >= 'a' && character <= 'f') {
        return character - 'a' + 10;
    }
    if (character >= 'A' && character <= 'F') {
        return character - 'A' + 10;
    }
    return -1;
}

class JSONParser {
public:
    explicit JSONParser(const std::string & input) : input_(input) {}

    bool parse_object(std::map<std::string, std::string> * fields) {
        skip_space();
        if (!consume('{')) {
            return false;
        }
        skip_space();
        if (consume('}')) {
            return at_end();
        }
        while (true) {
            std::string key;
            std::string value;
            if (!parse_string(&key)) {
                return false;
            }
            skip_space();
            if (!consume(':')) {
                return false;
            }
            skip_space();
            if (!parse_string(&value)) {
                return false;
            }
            (*fields)[key] = value;
            skip_space();
            if (consume('}')) {
                return at_end();
            }
            if (!consume(',')) {
                return false;
            }
            skip_space();
        }
    }

private:
    bool parse_string(std::string * output) {
        if (!consume('"')) {
            return false;
        }
        while (position_ < input_.size()) {
            const unsigned char character = input_[position_++];
            if (character == '"') {
                return true;
            }
            if (character < 0x20) {
                return false;
            }
            if (character != '\\') {
                output->push_back(static_cast<char>(character));
                continue;
            }
            if (position_ >= input_.size()) {
                return false;
            }
            const char escape = input_[position_++];
            switch (escape) {
                case '"': output->push_back('"'); break;
                case '\\': output->push_back('\\'); break;
                case '/': output->push_back('/'); break;
                case 'b': output->push_back('\b'); break;
                case 'f': output->push_back('\f'); break;
                case 'n': output->push_back('\n'); break;
                case 'r': output->push_back('\r'); break;
                case 't': output->push_back('\t'); break;
                case 'u': {
                    std::uint32_t scalar = 0;
                    if (!parse_hex_quad(&scalar)) {
                        return false;
                    }
                    if (scalar >= 0xd800 && scalar <= 0xdbff) {
                        if (position_ + 2 > input_.size()
                            || input_[position_] != '\\'
                            || input_[position_ + 1] != 'u') {
                            return false;
                        }
                        position_ += 2;
                        std::uint32_t low = 0;
                        if (!parse_hex_quad(&low)
                            || low < 0xdc00 || low > 0xdfff) {
                            return false;
                        }
                        scalar = 0x10000
                            + ((scalar - 0xd800) << 10)
                            + (low - 0xdc00);
                    } else if (scalar >= 0xdc00 && scalar <= 0xdfff) {
                        return false;
                    }
                    append_utf8(output, scalar);
                    break;
                }
                default:
                    return false;
            }
        }
        return false;
    }

    bool parse_hex_quad(std::uint32_t * output) {
        if (position_ + 4 > input_.size()) {
            return false;
        }
        std::uint32_t value = 0;
        for (int index = 0; index < 4; ++index) {
            const int digit = hex_value(input_[position_++]);
            if (digit < 0) {
                return false;
            }
            value = (value << 4) | static_cast<std::uint32_t>(digit);
        }
        *output = value;
        return true;
    }

    void skip_space() {
        while (position_ < input_.size()) {
            const char character = input_[position_];
            if (character != ' ' && character != '\t'
                && character != '\r' && character != '\n') {
                break;
            }
            ++position_;
        }
    }

    bool consume(char character) {
        if (position_ >= input_.size()
            || input_[position_] != character) {
            return false;
        }
        ++position_;
        return true;
    }

    bool at_end() {
        skip_space();
        return position_ == input_.size();
    }

    const std::string & input_;
    std::size_t position_ = 0;
};

std::uint16_t read_u16(
    const std::vector<std::uint8_t> & bytes,
    std::size_t offset
) {
    return static_cast<std::uint16_t>(bytes[offset])
        | (static_cast<std::uint16_t>(bytes[offset + 1]) << 8);
}

std::uint32_t read_u32(
    const std::vector<std::uint8_t> & bytes,
    std::size_t offset
) {
    return static_cast<std::uint32_t>(bytes[offset])
        | (static_cast<std::uint32_t>(bytes[offset + 1]) << 8)
        | (static_cast<std::uint32_t>(bytes[offset + 2]) << 16)
        | (static_cast<std::uint32_t>(bytes[offset + 3]) << 24);
}

bool has_chunk_id(
    const std::vector<std::uint8_t> & bytes,
    std::size_t offset,
    const char expected[4]
) {
    return offset + 4 <= bytes.size()
        && std::memcmp(bytes.data() + offset, expected, 4) == 0;
}

bool load_private_wave(
    const std::string & path,
    std::vector<float> * samples,
    std::string * error_code,
    std::string * error_message
) {
    if (path.empty() || path.front() != '/') {
        *error_code = "invalid_audio";
        *error_message = "audio path must be absolute";
        return false;
    }
    const int descriptor = open(
        path.c_str(),
        O_RDONLY | O_CLOEXEC | O_NOFOLLOW
    );
    if (descriptor < 0) {
        *error_code = "audio_unavailable";
        *error_message = "private audio could not be opened";
        return false;
    }

    struct stat status {};
    if (fstat(descriptor, &status) != 0
        || !S_ISREG(status.st_mode)
        || status.st_uid != geteuid()
        || (status.st_mode & 0077) != 0
        || status.st_size < 44
        || static_cast<std::uint64_t>(status.st_size) > kMaximumWaveBytes) {
        close(descriptor);
        *error_code = "insecure_audio";
        *error_message = "audio file failed privacy validation";
        return false;
    }

    std::vector<std::uint8_t> bytes(
        static_cast<std::size_t>(status.st_size)
    );
    std::size_t offset = 0;
    while (offset < bytes.size()) {
        const ssize_t count = read(
            descriptor,
            bytes.data() + offset,
            bytes.size() - offset
        );
        if (count <= 0) {
            close(descriptor);
            *error_code = "audio_read_failed";
            *error_message = "audio file could not be read";
            return false;
        }
        offset += static_cast<std::size_t>(count);
    }
    close(descriptor);

    if (!has_chunk_id(bytes, 0, "RIFF")
        || !has_chunk_id(bytes, 8, "WAVE")) {
        *error_code = "invalid_audio";
        *error_message = "audio is not a WAV file";
        return false;
    }

    bool found_format = false;
    bool found_data = false;
    std::uint16_t format_tag = 0;
    std::uint16_t channels = 0;
    std::uint16_t bits_per_sample = 0;
    std::uint32_t sample_rate = 0;
    std::size_t data_offset = 0;
    std::size_t data_size = 0;
    offset = 12;
    while (offset + 8 <= bytes.size()) {
        const std::uint32_t chunk_size = read_u32(bytes, offset + 4);
        const std::size_t payload = offset + 8;
        if (chunk_size > bytes.size() - payload) {
            *error_code = "invalid_audio";
            *error_message = "WAV chunk is truncated";
            return false;
        }
        if (has_chunk_id(bytes, offset, "fmt ") && chunk_size >= 16) {
            format_tag = read_u16(bytes, payload);
            channels = read_u16(bytes, payload + 2);
            sample_rate = read_u32(bytes, payload + 4);
            bits_per_sample = read_u16(bytes, payload + 14);
            found_format = true;
        } else if (has_chunk_id(bytes, offset, "data")) {
            data_offset = payload;
            data_size = chunk_size;
            found_data = true;
        }
        const std::size_t padded_size = static_cast<std::size_t>(
            chunk_size
        ) + (chunk_size & 1U);
        if (padded_size > bytes.size() - payload) {
            break;
        }
        offset = payload + padded_size;
    }

    if (!found_format || !found_data || format_tag != 1
        || channels != 1 || sample_rate != 16'000
        || bits_per_sample != 16 || data_size % 2 != 0) {
        *error_code = "unsupported_audio";
        *error_message = "audio must be 16 kHz mono PCM16 WAV";
        return false;
    }

    samples->reserve(data_size / 2);
    for (std::size_t index = 0; index < data_size; index += 2) {
        const std::uint16_t raw = read_u16(bytes, data_offset + index);
        const std::int16_t value = static_cast<std::int16_t>(raw);
        samples->push_back(static_cast<float>(value) / 32768.0f);
    }
    if (samples->empty()) {
        *error_code = "no_speech";
        *error_message = "audio contained no samples";
        return false;
    }
    return true;
}

// Root-mean-square level of the decoded PCM, normalized to [0, 1]. Used to
// decide whether a clip has enough audible signal for a vocabulary-biasing
// prompt to be safe (see kMinimumPromptSignalRms).
float signal_rms(const std::vector<float> & samples) {
    if (samples.empty()) {
        return 0.0f;
    }
    double sum_squares = 0.0;
    for (const float sample : samples) {
        sum_squares += static_cast<double>(sample) * sample;
    }
    return static_cast<float>(
        std::sqrt(sum_squares / static_cast<double>(samples.size()))
    );
}

void discard_whisper_log(
    enum ggml_log_level,
    const char *,
    void *
) {}

std::vector<std::string> normalized_words(const std::string & text) {
    std::vector<std::string> words;
    std::string current;
    for (const unsigned char character : text) {
        if ((character >= 'a' && character <= 'z')
            || (character >= '0' && character <= '9')) {
            current.push_back(static_cast<char>(character));
        } else if (character >= 'A' && character <= 'Z') {
            current.push_back(
                static_cast<char>(character - 'A' + 'a')
            );
        } else if (!current.empty()) {
            words.push_back(std::move(current));
            current.clear();
        }
    }
    if (!current.empty()) {
        words.push_back(std::move(current));
    }
    return words;
}

bool has_repeated_ngram(const std::string & text) {
    constexpr std::size_t ngram_size = 3;
    const std::vector<std::string> words = normalized_words(text);
    if (words.size() < ngram_size * 2) {
        return false;
    }
    std::unordered_map<std::string, int> counts;
    for (std::size_t index = 0;
         index + ngram_size <= words.size();
         ++index) {
        std::string key;
        for (std::size_t offset = 0; offset < ngram_size; ++offset) {
            if (!key.empty()) {
                key.push_back('\n');
            }
            key += words[index + offset];
        }
        if (++counts[key] >= 3) {
            return true;
        }
    }
    return false;
}

DecodeResult collect_result(
    const Options & options,
    whisper_context * context
) {
    DecodeResult result;
    double log_probability_sum = 0;
    int token_count = 0;
    int weak_token_count = 0;
    float maximum_no_speech = 0;
    const whisper_token end_of_text = whisper_token_eot(context);
    const int segment_count = whisper_full_n_segments(context);

    auto starts_word = [](const std::string & token) {
        return !token.empty()
            && std::isspace(static_cast<unsigned char>(token.front()));
    };

    for (int segment = 0; segment < segment_count; ++segment) {
        const char * text = whisper_full_get_segment_text(
            context,
            segment
        );
        if (text != nullptr) {
            result.text += text;
        }
        maximum_no_speech = std::max(
            maximum_no_speech,
            whisper_full_get_segment_no_speech_prob(context, segment)
        );
        const int segment_tokens = whisper_full_n_tokens(
            context,
            segment
        );
        SegmentInfo segment_info;
        if (options.emit_timestamps) {
            const int segment_start = whisper_full_get_segment_t0(context, segment);
            const int segment_end = whisper_full_get_segment_t1(context, segment);
            segment_info.text = text == nullptr ? "" : text;
            segment_info.start_seconds = static_cast<float>(segment_start) / 100.0f;
            segment_info.end_seconds = static_cast<float>(segment_end) / 100.0f;
        }

        TimedWordInfo active_word;
        double active_log_probability_sum = 0.0;
        int active_token_count = 0;
        bool has_active_word = false;
        auto flush_word = [&]() {
            if (!has_active_word || active_word.text.empty()) {
                return;
            }
            if (result.words.size() < kMaximumWords) {
                if (active_token_count > 0) {
                    active_word.posterior = static_cast<float>(std::exp(
                        active_log_probability_sum / active_token_count
                    ));
                }
                const std::size_t word_index = result.words.size();
                result.words.push_back(std::move(active_word));
                if (options.emit_timestamps) {
                    segment_info.word_indices.push_back(word_index);
                }
            }
            active_word = TimedWordInfo();
            active_log_probability_sum = 0.0;
            active_token_count = 0;
            has_active_word = false;
        };

        for (int token = 0; token < segment_tokens; ++token) {
            const whisper_token_data data = whisper_full_get_token_data(
                context,
                segment,
                token
            );
            if (data.id >= end_of_text || !std::isfinite(data.plog)) {
                continue;
            }
            log_probability_sum += data.plog;
            ++token_count;
            if (data.p < 0.20f) {
                ++weak_token_count;
            }
            if (options.emit_token_data) {
                const char * token_text = whisper_full_get_token_text(
                    context,
                    segment,
                    token
                );
                const std::string token_value =
                    token_text == nullptr ? "" : token_text;
                if (token_value.empty()) {
                    continue;
                }
                if (has_active_word && starts_word(token_value)) {
                    flush_word();
                }
                if (!has_active_word) {
                    active_word.start_seconds =
                        static_cast<float>(data.t0) / 100.0f;
                    active_word.end_seconds =
                        static_cast<float>(data.t1) / 100.0f;
                    has_active_word = true;
                }
                std::size_t first_non_space = 0;
                if (active_word.text.empty()) {
                    while (first_non_space < token_value.size()
                           && std::isspace(static_cast<unsigned char>(
                               token_value[first_non_space]
                           ))) {
                        ++first_non_space;
                    }
                }
                active_word.text += token_value.substr(first_non_space);
                active_word.end_seconds =
                    static_cast<float>(data.t1) / 100.0f;
                if (active_word.token_ids.size() < kMaximumTokensPerWord) {
                    active_word.token_ids.push_back(data.id);
                    active_word.token_log_probabilities.push_back(data.plog);
                }
                active_log_probability_sum += data.plog;
                ++active_token_count;
            }
        }
        flush_word();
        if (options.emit_timestamps) {
            if (result.segments.size() < kMaximumSegments) {
                result.segments.push_back(std::move(segment_info));
            }
        }
    }
    if (token_count > 0) {
        result.average_log_probability = static_cast<float>(
            log_probability_sum / token_count
        );
        result.weak_token_fraction = static_cast<float>(
            weak_token_count
        ) / token_count;
    } else {
        result.average_log_probability = -100.0f;
    }
    result.maximum_no_speech_probability = maximum_no_speech;
    result.has_repetition = has_repeated_ngram(result.text);
    return result;
}

whisper_full_params decoding_params(
    const Options & options,
    whisper_sampling_strategy strategy,
    const std::string & prompt,
    bool fast_first_pass
) {
    whisper_full_params params = whisper_full_default_params(strategy);
    params.n_threads = options.threads;
    params.translate = false;
    params.no_context = true;
    params.initial_prompt = prompt.empty() ? nullptr : prompt.c_str();
    params.carry_initial_prompt = false;
    params.no_timestamps = !(
        options.emit_timestamps || options.emit_token_data
    );
    params.token_timestamps = options.emit_token_data;
    params.print_special = false;
    params.print_progress = false;
    params.print_realtime = false;
    params.print_timestamps = false;
    params.language = "en";
    params.detect_language = false;
    params.suppress_nst = true;
    params.beam_search.beam_size = options.beam_size;
    if (fast_first_pass) {
        params.greedy.best_of = 1;
        params.temperature_inc = -1.0f;
    }
    return params;
}

bool is_confident(const DecodeResult & result) {
    return !result.text.empty()
        && result.average_log_probability
            >= kAdaptiveMinimumAverageLogProbability
        && result.weak_token_fraction
            <= kAdaptiveMaximumWeakTokenFraction
        && result.maximum_no_speech_probability
            <= kAdaptiveMaximumNoSpeechProbability
        && !result.has_repetition;
}

bool decode(
    whisper_context * context,
    const Options & options,
    const std::string & prompt,
    const std::vector<float> & samples,
    whisper_sampling_strategy strategy,
    bool fast_first_pass,
    DecodeResult * result
) {
    const whisper_full_params params = decoding_params(
        options,
        strategy,
        prompt,
        fast_first_pass
    );
    if (whisper_full(
        context,
        params,
        samples.data(),
        static_cast<int>(samples.size())
    ) != 0) {
        return false;
    }
    *result = collect_result(options, context);
    return true;
}

}  // namespace

int main(int argc, char ** argv) {
    Options options;
    if (!parse_options(argc, argv, &options)) {
        return emit_error(
            "invalid_arguments",
            "helper arguments are invalid",
            64
        );
    }
    const int configured_beam_size = options.beam_size;
    const whisper_sampling_strategy configured_strategy = options.strategy;
    const bool configured_adaptive = options.adaptive;
    const std::string configured_requested_strategy = options.requested_strategy;

    whisper_log_set(discard_whisper_log, nullptr);
    ggml_backend_load_all();
    const char * system_info = whisper_print_system_info();
    if (options.require_coreml
        && (system_info == nullptr
            || std::string(system_info).find("COREML = 1")
                == std::string::npos)) {
        return emit_error(
            "coreml_unavailable",
            "Whisper helper was not built with Core ML",
            69
        );
    }
    whisper_context_params context_params =
        whisper_context_default_params();
    context_params.use_gpu = true;
    context_params.flash_attn = true;

    std::unique_ptr<whisper_context, decltype(&whisper_free)> context(
        whisper_init_from_file_with_params(
            options.model_path.c_str(),
            context_params
        ),
        &whisper_free
    );
    if (!context) {
        return emit_error(
            "model_load_failed",
            "Selected Whisper model could not be loaded",
            70
        );
    }
    emit_ready();

    std::string command_line;
    while (std::getline(std::cin, command_line)) {
        if (command_line.size() > kMaximumCommandBytes) {
            return emit_error(
                "invalid_command",
                "command was too large",
                65
            );
        }
        std::map<std::string, std::string> command;
        JSONParser parser(command_line);
        if (!parser.parse_object(&command)
            || command["command"] != "transcribe"
            || command["audioPath"].empty()) {
            return emit_error(
                "invalid_command",
                "expected a transcribe command",
                65
            );
        }

        std::vector<float> samples;
        std::string error_code;
        std::string error_message;
        if (!load_private_wave(
            command["audioPath"],
            &samples,
            &error_code,
            &error_message
        )) {
            emit_error(error_code, error_message, 66);
            continue;
        }

        options.request_id.clear();
        options.request_pass = "primaryFullSession";
        options.requested_strategy = configured_requested_strategy;
        options.beam_size = configured_beam_size;
        options.strategy = configured_strategy;
        options.adaptive = configured_adaptive;
        options.emit_timestamps = false;
        options.emit_token_data = false;

        const std::string protocol_version = command["protocolVersion"];
        options.protocol_version = 1;
        if (!protocol_version.empty()) {
            long long parsed_protocol_version = 0;
            if (!parse_non_negative_long_long(protocol_version.c_str(), &parsed_protocol_version)
                || parsed_protocol_version <= 0
                || parsed_protocol_version > 2) {
                emit_error("invalid_command", "invalid protocolVersion", 65);
                continue;
            }
            options.protocol_version = static_cast<int>(parsed_protocol_version);
        }

        options.request_id = command["requestID"];
        const std::string requested_pass = command["pass"];
        if (!requested_pass.empty()) {
            options.request_pass = requested_pass;
        }

        const std::string requested_strategy = command["strategy"];
        if (!requested_strategy.empty()) {
            options.requested_strategy = requested_strategy;
            if (requested_strategy == "beam") {
                options.strategy = WHISPER_SAMPLING_BEAM_SEARCH;
                options.adaptive = false;
            } else if (requested_strategy == "greedy") {
                options.strategy = WHISPER_SAMPLING_GREEDY;
                options.adaptive = false;
            } else if (requested_strategy == "adaptive") {
                options.strategy = WHISPER_SAMPLING_GREEDY;
                options.adaptive = true;
            } else {
                emit_error("invalid_command", "unsupported strategy", 65);
                continue;
            }
        }

        const std::string requested_beam_size = command["beamSize"];
        if (!requested_beam_size.empty()) {
            int beam_size = 0;
            if (!parse_positive_int(requested_beam_size.c_str(), &beam_size)
                || beam_size < 1 || beam_size > 16) {
                emit_error("invalid_command", "invalid beamSize", 65);
                continue;
            }
            options.beam_size = beam_size;
        }

        if (!parse_bool_value(command["emitTimestamps"].c_str(),
                             &options.emit_timestamps)) {
            options.emit_timestamps = false;
        }
        if (!parse_bool_value(command["emitTokenData"].c_str(),
                             &options.emit_token_data)) {
            options.emit_token_data = false;
        }

        long long sample_start = -1;
        if (!command["sampleStart"].empty()
            && !parse_non_negative_long_long(
                command["sampleStart"].c_str(),
                &sample_start
            )) {
            emit_error("invalid_command", "invalid sampleStart", 65);
            continue;
        }
        sample_start = -1;
        if (!command["sampleStart"].empty()) {
            parse_non_negative_long_long(
                command["sampleStart"].c_str(),
                &sample_start
            );
        }

        long long sample_end = -1;
        if (!command["sampleEnd"].empty()
            && !parse_non_negative_long_long(
                command["sampleEnd"].c_str(),
                &sample_end
            )) {
            emit_error("invalid_command", "invalid sampleEnd", 65);
            continue;
        }
        sample_end = -1;
        if (!command["sampleEnd"].empty()) {
            parse_non_negative_long_long(
                command["sampleEnd"].c_str(),
                &sample_end
            );
        }

        std::vector<float> request_samples = samples;
        if (sample_start >= 0 || sample_end >= 0) {
            if (sample_start < 0) {
                sample_start = 0;
            }
            if (sample_end < 0) {
                sample_end = static_cast<long long>(samples.size());
            }
            if (sample_start >= sample_end
                || sample_end > static_cast<long long>(samples.size())) {
                emit_error("invalid_command", "sample range is out of bounds", 65);
                continue;
            }
            request_samples.assign(
                samples.begin() + sample_start,
                samples.begin() + sample_end
            );
            options.sample_start = sample_start;
            options.sample_end = sample_end;
        } else {
            options.sample_start = 0;
            options.sample_end = static_cast<long long>(samples.size());
        }

        std::vector<float> & active_samples = request_samples;

        // Suppress the vocabulary-biasing prompt for clips that are too
        // quiet to plausibly contain recognizable speech. With no genuine
        // speech to bias, the prompt has nothing legitimate to help
        // recognize and can instead be echoed verbatim into the transcript
        // by the decoder. See kMinimumPromptSignalRms.
        const std::string requested_prompt = command["prompt"];
        const std::string prompt =
            signal_rms(active_samples) >= kMinimumPromptSignalRms
                ? requested_prompt
                : std::string();
        const auto decode_started = std::chrono::steady_clock::now();
        DecodeResult result;
        if (!decode(
            context.get(),
            options,
            prompt,
            active_samples,
            options.strategy,
            options.adaptive,
            &result
        )) {
            emit_error(
                "inference_failed",
                "local inference failed",
                70
            );
            continue;
        }

        bool adaptive_fallback = false;
        if (options.adaptive && !is_confident(result)) {
            adaptive_fallback = true;
            if (!decode(
                context.get(),
                options,
                prompt,
                active_samples,
                WHISPER_SAMPLING_BEAM_SEARCH,
                false,
                &result
            )) {
                emit_error(
                    "inference_failed",
                    "local fallback inference failed",
                    70
                );
                continue;
            }
        }

        const double latency_ms = static_cast<double>(
            std::chrono::duration_cast<std::chrono::microseconds>(
                std::chrono::steady_clock::now() - decode_started
            ).count()
        ) / 1'000.0;
        if (emit_result(
            options,
            result,
            adaptive_fallback,
            options.sample_start,
            options.sample_end,
            prompt,
            latency_ms
        ) != 0) {
            continue;
        }
    }
    return 0;
}
