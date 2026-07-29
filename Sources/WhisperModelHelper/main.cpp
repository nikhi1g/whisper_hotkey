#include <whisper.h>
#include <ggml-backend.h>

#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>

#include <cerrno>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <iostream>
#include <limits>
#include <map>
#include <memory>
#include <string>
#include <vector>

namespace {

constexpr std::size_t kMaximumCommandBytes = 65'536;
constexpr std::size_t kMaximumWaveBytes = 64 * 1024 * 1024;

struct Options {
    std::string model_path;
    int threads = 4;
    int beam_size = 5;
    whisper_sampling_strategy strategy = WHISPER_SAMPLING_BEAM_SEARCH;
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

void emit_result(const std::string & text) {
    std::cout << "{\"event\":\"result\",\"text\":\""
              << json_escape(text)
              << "\"}" << std::endl;
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
            if (strategy == "beam") {
                options->strategy = WHISPER_SAMPLING_BEAM_SEARCH;
            } else if (strategy == "greedy") {
                options->strategy = WHISPER_SAMPLING_GREEDY;
            } else {
                return false;
            }
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

void discard_whisper_log(
    enum ggml_log_level,
    const char *,
    void *
) {}

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

    whisper_log_set(discard_whisper_log, nullptr);
    ggml_backend_load_all();
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

        whisper_full_params params = whisper_full_default_params(
            options.strategy
        );
        params.n_threads = options.threads;
        params.translate = false;
        params.no_context = true;
        params.no_timestamps = true;
        params.print_special = false;
        params.print_progress = false;
        params.print_realtime = false;
        params.print_timestamps = false;
        params.language = "en";
        params.detect_language = false;
        params.suppress_nst = true;
        params.beam_search.beam_size = options.beam_size;

        if (whisper_full(
            context.get(),
            params,
            samples.data(),
            static_cast<int>(samples.size())
        ) != 0) {
            emit_error(
                "inference_failed",
                "local inference failed",
                70
            );
            continue;
        }

        std::string transcript;
        const int segment_count = whisper_full_n_segments(context.get());
        for (int index = 0; index < segment_count; ++index) {
            const char * text = whisper_full_get_segment_text(
                context.get(),
                index
            );
            if (text != nullptr) {
                transcript += text;
            }
        }
        if (transcript.empty()) {
            emit_error(
                "no_speech",
                "no speech was detected",
                67
            );
            continue;
        }
        emit_result(transcript);
    }
    return 0;
}
