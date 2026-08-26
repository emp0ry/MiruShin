#include "seek_thumbnail_decoder.h"

#include <algorithm>
#include <atomic>
#include <cmath>
#include <cstdlib>
#include <cstring>
#include <limits>
#include <new>
#include <string>

#if defined(_WIN32)
#include <windows.h>
#else
#include <dlfcn.h>
#endif

extern "C" {
#include "libavcodec/avcodec.h"
#include "libavformat/avformat.h"
#include "libavutil/dict.h"
#include "libavutil/error.h"
#include "libavutil/frame.h"
#include "libswscale/swscale.h"
}

namespace {

#if defined(_WIN32)
using LibraryHandle = HMODULE;
#else
using LibraryHandle = void*;
#endif

enum DecodeStatus {
  kOk = 0,
  kInvalidArguments = -1,
  kRuntimeUnavailable = -2,
  kOpenInputFailed = -10,
  kStreamInfoFailed = -11,
  kNoVideoTrack = -12,
  kUnsupportedCodec = -13,
  kSeekFailed = -14,
  kNoFrame = -15,
  kScaleFailed = -16,
  kCancelled = -20,
};

struct Api {
  LibraryHandle library = nullptr;
  bool ready = false;
  std::string error;

  unsigned (*avformat_version)() = nullptr;
  unsigned (*avcodec_version)() = nullptr;
  int (*avformat_network_init)() = nullptr;
  AVFormatContext* (*avformat_alloc_context)() = nullptr;
  int (*avformat_open_input)(AVFormatContext**, const char*,
                             const AVInputFormat*, AVDictionary**) = nullptr;
  int (*avformat_find_stream_info)(AVFormatContext*, AVDictionary**) = nullptr;
  int (*av_find_best_stream)(AVFormatContext*, AVMediaType, int, int,
                             const AVCodec**, int) = nullptr;
  void (*avformat_close_input)(AVFormatContext**) = nullptr;
  int (*avformat_seek_file)(AVFormatContext*, int, int64_t, int64_t, int64_t,
                            int) = nullptr;
  int (*av_seek_frame)(AVFormatContext*, int, int64_t, int) = nullptr;
  int (*av_read_frame)(AVFormatContext*, AVPacket*) = nullptr;
  AVRational (*av_guess_sample_aspect_ratio)(AVFormatContext*, AVStream*,
                                              AVFrame*) = nullptr;

  AVCodecContext* (*avcodec_alloc_context3)(const AVCodec*) = nullptr;
  int (*avcodec_parameters_to_context)(AVCodecContext*,
                                       const AVCodecParameters*) = nullptr;
  int (*avcodec_open2)(AVCodecContext*, const AVCodec*, AVDictionary**) =
      nullptr;
  int (*avcodec_send_packet)(AVCodecContext*, const AVPacket*) = nullptr;
  int (*avcodec_receive_frame)(AVCodecContext*, AVFrame*) = nullptr;
  void (*avcodec_flush_buffers)(AVCodecContext*) = nullptr;
  void (*avcodec_free_context)(AVCodecContext**) = nullptr;

  AVPacket* (*av_packet_alloc)() = nullptr;
  void (*av_packet_unref)(AVPacket*) = nullptr;
  void (*av_packet_free)(AVPacket**) = nullptr;
  const AVPacketSideData* (*av_packet_side_data_get)(
      const AVPacketSideData*, int, AVPacketSideDataType) = nullptr;
  AVFrame* (*av_frame_alloc)() = nullptr;
  void (*av_frame_unref)(AVFrame*) = nullptr;
  void (*av_frame_free)(AVFrame**) = nullptr;
  AVFrameSideData* (*av_frame_get_side_data)(const AVFrame*,
                                              AVFrameSideDataType) = nullptr;
  int (*av_dict_set)(AVDictionary**, const char*, const char*, int) = nullptr;
  void (*av_dict_free)(AVDictionary**) = nullptr;
  int (*av_strerror)(int, char*, size_t) = nullptr;
  double (*av_display_rotation_get)(const int32_t matrix[9]) = nullptr;

  SwsContext* (*sws_getContext)(int, int, AVPixelFormat, int, int,
                                AVPixelFormat, int, SwsFilter*, SwsFilter*,
                                const double*) = nullptr;
  int (*sws_scale)(SwsContext*, const uint8_t* const[], const int[], int, int,
                   uint8_t* const[], const int[]) = nullptr;
  void (*sws_freeContext)(SwsContext*) = nullptr;
};

struct DecoderSession {
  std::atomic<bool> cancelled{false};
  AVFormatContext* format = nullptr;
  AVCodecContext* codec = nullptr;
  AVPacket* packet = nullptr;
  AVFrame* frame = nullptr;
  AVStream* stream = nullptr;
  int video_index = -1;
};

void* symbol(LibraryHandle library, const char* name) {
#if defined(_WIN32)
  return reinterpret_cast<void*>(GetProcAddress(library, name));
#else
  return dlsym(library, name);
#endif
}

LibraryHandle openLibrary() {
#if defined(_WIN32)
  return LoadLibraryW(L"ffmpeg-8.dll");
#elif defined(__APPLE__)
  return dlopen(nullptr, RTLD_NOW | RTLD_LOCAL);
#else
  LibraryHandle handle = dlopen("libffmpeg.so", RTLD_NOW | RTLD_LOCAL);
  if (handle == nullptr) {
    handle = dlopen("libffmpeg.so.8", RTLD_NOW | RTLD_LOCAL);
  }
  return handle;
#endif
}

template <typename T>
bool loadSymbol(Api& api, T& destination, const char* name) {
  destination = reinterpret_cast<T>(symbol(api.library, name));
  if (destination != nullptr) return true;
  api.error = std::string("Missing FFmpeg symbol: ") + name;
  return false;
}

Api loadApi() {
  Api api;
  api.library = openLibrary();
  if (api.library == nullptr) {
    api.error = "The existing FFmpeg runtime could not be loaded.";
    return api;
  }
#define LOAD(name)                         \
  if (!loadSymbol(api, api.name, #name)) { \
    return api;                            \
  }
  LOAD(avformat_version)
  LOAD(avcodec_version)
  LOAD(avformat_network_init)
  LOAD(avformat_alloc_context)
  LOAD(avformat_open_input)
  LOAD(avformat_find_stream_info)
  LOAD(av_find_best_stream)
  LOAD(avformat_close_input)
  LOAD(avformat_seek_file)
  LOAD(av_seek_frame)
  LOAD(av_read_frame)
  LOAD(av_guess_sample_aspect_ratio)
  LOAD(avcodec_alloc_context3)
  LOAD(avcodec_parameters_to_context)
  LOAD(avcodec_open2)
  LOAD(avcodec_send_packet)
  LOAD(avcodec_receive_frame)
  LOAD(avcodec_flush_buffers)
  LOAD(avcodec_free_context)
  LOAD(av_packet_alloc)
  LOAD(av_packet_unref)
  LOAD(av_packet_free)
  LOAD(av_packet_side_data_get)
  LOAD(av_frame_alloc)
  LOAD(av_frame_unref)
  LOAD(av_frame_free)
  LOAD(av_frame_get_side_data)
  LOAD(av_dict_set)
  LOAD(av_dict_free)
  LOAD(av_strerror)
  LOAD(av_display_rotation_get)
  LOAD(sws_getContext)
  LOAD(sws_scale)
  LOAD(sws_freeContext)
#undef LOAD

  const unsigned format_major = api.avformat_version() >> 16;
  const unsigned codec_major = api.avcodec_version() >> 16;
  if (format_major != LIBAVFORMAT_VERSION_MAJOR ||
      codec_major != LIBAVCODEC_VERSION_MAJOR) {
    api.error = "The installed FFmpeg ABI is incompatible with the bridge.";
    return api;
  }
  api.avformat_network_init();
  api.ready = true;
  return api;
}

Api& ffmpeg() {
  static Api api = loadApi();
  return api;
}

void setError(char* output, int capacity, const std::string& value) {
  if (output == nullptr || capacity <= 0) return;
  const size_t count = std::min(value.size(), static_cast<size_t>(capacity - 1));
  std::memcpy(output, value.data(), count);
  output[count] = '\0';
}

std::string avError(Api& api, const char* operation, int code) {
  char detail[AV_ERROR_MAX_STRING_SIZE] = {};
  api.av_strerror(code, detail, sizeof(detail));
  return std::string(operation) + " failed: " + detail;
}

int interruptCallback(void* opaque) {
  const auto* session = static_cast<const DecoderSession*>(opaque);
  return session != nullptr && session->cancelled.load() ? 1 : 0;
}

void closeSession(DecoderSession* session) {
  if (session == nullptr) return;
  Api& api = ffmpeg();
  if (session->frame != nullptr) api.av_frame_free(&session->frame);
  if (session->packet != nullptr) api.av_packet_free(&session->packet);
  if (session->codec != nullptr) api.avcodec_free_context(&session->codec);
  if (session->format != nullptr) api.avformat_close_input(&session->format);
  session->stream = nullptr;
  session->video_index = -1;
}

int64_t millisecondsToTimestamp(int64_t milliseconds, AVRational time_base) {
  if (time_base.num <= 0 || time_base.den <= 0) return milliseconds;
  const long double ticks = static_cast<long double>(milliseconds) *
                            time_base.den /
                            (static_cast<long double>(time_base.num) * 1000.0L);
  if (ticks >= static_cast<long double>(std::numeric_limits<int64_t>::max())) {
    return std::numeric_limits<int64_t>::max();
  }
  return static_cast<int64_t>(std::llround(ticks));
}

int64_t timestampToMilliseconds(int64_t timestamp, AVRational time_base) {
  if (timestamp == AV_NOPTS_VALUE || time_base.num <= 0 || time_base.den <= 0) {
    return -1;
  }
  const long double milliseconds = static_cast<long double>(timestamp) *
                                   time_base.num * 1000.0L / time_base.den;
  return static_cast<int64_t>(std::llround(milliseconds));
}

int normalizedRotation(double value) {
  if (!std::isfinite(value)) return 0;
  int rotation = static_cast<int>(std::llround(value / 90.0)) * 90;
  rotation %= 360;
  if (rotation < 0) rotation += 360;
  return rotation;
}

int frameRotation(Api& api, AVStream* stream, AVFrame* frame) {
  const int32_t* matrix = nullptr;
  const AVFrameSideData* frame_side =
      api.av_frame_get_side_data(frame, AV_FRAME_DATA_DISPLAYMATRIX);
  if (frame_side != nullptr && frame_side->size >= 9 * sizeof(int32_t)) {
    matrix = reinterpret_cast<const int32_t*>(frame_side->data);
  }
  if (matrix == nullptr && stream != nullptr && stream->codecpar != nullptr) {
    const AVPacketSideData* packet_side = api.av_packet_side_data_get(
        stream->codecpar->coded_side_data, stream->codecpar->nb_coded_side_data,
        AV_PKT_DATA_DISPLAYMATRIX);
    if (packet_side != nullptr && packet_side->size >= 9 * sizeof(int32_t)) {
      matrix = reinterpret_cast<const int32_t*>(packet_side->data);
    }
  }
  return matrix == nullptr
             ? 0
             : normalizedRotation(api.av_display_rotation_get(matrix));
}

void rotateRgba(const uint8_t* source, int source_width, int source_height,
                int rotation, uint8_t* destination) {
  for (int y = 0; y < source_height; ++y) {
    for (int x = 0; x < source_width; ++x) {
      int destination_x = x;
      int destination_y = y;
      int destination_width = source_width;
      if (rotation == 90) {
        destination_x = source_height - 1 - y;
        destination_y = x;
        destination_width = source_height;
      } else if (rotation == 180) {
        destination_x = source_width - 1 - x;
        destination_y = source_height - 1 - y;
      } else if (rotation == 270) {
        destination_x = y;
        destination_y = source_width - 1 - x;
        destination_width = source_height;
      }
      const size_t source_offset =
          (static_cast<size_t>(y) * source_width + x) * 4;
      const size_t destination_offset =
          (static_cast<size_t>(destination_y) * destination_width +
           destination_x) * 4;
      std::memcpy(destination + destination_offset, source + source_offset, 4);
    }
  }
}

}  // namespace

extern "C" int mirushin_seek_thumbnail_output_size(
    int coded_width, int coded_height, int sar_num, int sar_den,
    int rotation_degrees, int target_width, int* output_width,
    int* output_height, double* display_aspect_ratio) {
  if (coded_width <= 0 || coded_height <= 0 || target_width <= 0 ||
      output_width == nullptr || output_height == nullptr ||
      display_aspect_ratio == nullptr) {
    return kInvalidArguments;
  }
  if (sar_num <= 0 || sar_den <= 0) {
    sar_num = 1;
    sar_den = 1;
  }
  long double aspect = static_cast<long double>(coded_width) * sar_num /
                       (static_cast<long double>(coded_height) * sar_den);
  const int rotation = ((rotation_degrees % 360) + 360) % 360;
  if (rotation == 90 || rotation == 270) aspect = 1.0L / aspect;
  if (!std::isfinite(static_cast<double>(aspect)) || aspect <= 0.01L ||
      aspect > 100.0L) {
    return kInvalidArguments;
  }
  const int output_h = std::max(
      1, static_cast<int>(std::llround(static_cast<long double>(target_width) /
                                       aspect)));
  if (output_h > 1440) return kInvalidArguments;
  *output_width = target_width;
  *output_height = output_h;
  *display_aspect_ratio = static_cast<double>(aspect);
  return kOk;
}

extern "C" void* mirushin_seek_thumbnail_session_create(void) {
  if (!ffmpeg().ready) return nullptr;
  return new (std::nothrow) DecoderSession();
}

extern "C" void mirushin_seek_thumbnail_session_reset_cancel(void* handle) {
  auto* session = static_cast<DecoderSession*>(handle);
  if (session != nullptr) session->cancelled.store(false);
}

extern "C" void mirushin_seek_thumbnail_session_cancel(void* handle) {
  auto* session = static_cast<DecoderSession*>(handle);
  if (session != nullptr) session->cancelled.store(true);
}

extern "C" int mirushin_seek_thumbnail_session_open(
    void* handle, const char* input, const char* http_headers, char* error,
    int error_capacity) {
  auto* session = static_cast<DecoderSession*>(handle);
  if (session == nullptr || input == nullptr || input[0] == '\0') {
    setError(error, error_capacity, "Invalid thumbnail decoder arguments.");
    return kInvalidArguments;
  }
  Api& api = ffmpeg();
  if (!api.ready) {
    setError(error, error_capacity, api.error);
    return kRuntimeUnavailable;
  }
  closeSession(session);
  if (session->cancelled.load()) return kCancelled;

  session->format = api.avformat_alloc_context();
  if (session->format == nullptr) {
    setError(error, error_capacity, "Allocate input context failed.");
    return kOpenInputFailed;
  }
  session->format->interrupt_callback.callback = interruptCallback;
  session->format->interrupt_callback.opaque = session;
  AVDictionary* options = nullptr;
  api.av_dict_set(&options, "rw_timeout", "1800000", 0);
  api.av_dict_set(&options, "reconnect", "1", 0);
  api.av_dict_set(&options, "reconnect_streamed", "1", 0);
  api.av_dict_set(&options, "reconnect_delay_max", "1", 0);
  if (http_headers != nullptr && http_headers[0] != '\0') {
    api.av_dict_set(&options, "headers", http_headers, 0);
  }
  int status =
      api.avformat_open_input(&session->format, input, nullptr, &options);
  api.av_dict_free(&options);
  if (status < 0) {
    const bool cancelled = session->cancelled.load();
    setError(error, error_capacity,
             cancelled ? "Thumbnail decode cancelled."
                       : avError(api, "Open input", status));
    closeSession(session);
    return cancelled ? kCancelled : kOpenInputFailed;
  }
  status = api.avformat_find_stream_info(session->format, nullptr);
  if (status < 0) {
    const bool cancelled = session->cancelled.load();
    setError(error, error_capacity,
             cancelled ? "Thumbnail decode cancelled."
                       : avError(api, "Read stream info", status));
    closeSession(session);
    return cancelled ? kCancelled : kStreamInfoFailed;
  }

  const AVCodec* codec = nullptr;
  session->video_index = api.av_find_best_stream(
      session->format, AVMEDIA_TYPE_VIDEO, -1, -1, &codec, 0);
  if (session->video_index < 0) {
    setError(error, error_capacity, "No video track was found.");
    closeSession(session);
    return kNoVideoTrack;
  }
  if (codec == nullptr) {
    setError(error, error_capacity, "The video codec is unsupported.");
    closeSession(session);
    return kUnsupportedCodec;
  }
  session->stream = session->format->streams[session->video_index];
  session->codec = api.avcodec_alloc_context3(codec);
  if (session->codec == nullptr) {
    setError(error, error_capacity, "Allocate decoder context failed.");
    closeSession(session);
    return kUnsupportedCodec;
  }
  status =
      api.avcodec_parameters_to_context(session->codec, session->stream->codecpar);
  if (status < 0 || api.avcodec_open2(session->codec, codec, nullptr) < 0) {
    setError(error, error_capacity, "The video codec could not be opened.");
    closeSession(session);
    return kUnsupportedCodec;
  }
  session->packet = api.av_packet_alloc();
  session->frame = api.av_frame_alloc();
  if (session->packet == nullptr || session->frame == nullptr) {
    setError(error, error_capacity, "Allocate decoder frame failed.");
    closeSession(session);
    return kOpenInputFailed;
  }
  return kOk;
}

extern "C" int mirushin_seek_thumbnail_session_decode(
    void* handle, int64_t target_ms, int target_width, uint8_t** rgba,
    int* rgba_length, int* width, int* height, int64_t* decoded_ms,
    int* coded_width, int* coded_height, int* sar_num, int* sar_den,
    int* rotation_degrees, double* display_aspect_ratio, char* error,
    int error_capacity) {
  auto* session = static_cast<DecoderSession*>(handle);
  if (session == nullptr || session->format == nullptr ||
      session->codec == nullptr || session->stream == nullptr ||
      session->packet == nullptr || session->frame == nullptr ||
      rgba == nullptr || rgba_length == nullptr || width == nullptr ||
      height == nullptr || decoded_ms == nullptr || coded_width == nullptr ||
      coded_height == nullptr || sar_num == nullptr || sar_den == nullptr ||
      rotation_degrees == nullptr || display_aspect_ratio == nullptr) {
    setError(error, error_capacity, "Invalid thumbnail decoder session.");
    return kInvalidArguments;
  }
  *rgba = nullptr;
  *rgba_length = 0;
  *width = 0;
  *height = 0;
  *decoded_ms = -1;
  *coded_width = 0;
  *coded_height = 0;
  *sar_num = 1;
  *sar_den = 1;
  *rotation_degrees = 0;
  *display_aspect_ratio = 0;
  if (session->cancelled.load()) return kCancelled;

  Api& api = ffmpeg();
  api.av_packet_unref(session->packet);
  api.av_frame_unref(session->frame);
  const int64_t stream_start = session->stream->start_time == AV_NOPTS_VALUE
                                   ? 0
                                   : session->stream->start_time;
  const int64_t target_timestamp =
      stream_start + millisecondsToTimestamp(std::max<int64_t>(0, target_ms),
                                              session->stream->time_base);
  int status = api.avformat_seek_file(
      session->format, session->video_index,
      std::numeric_limits<int64_t>::min(), target_timestamp, target_timestamp,
      AVSEEK_FLAG_BACKWARD);
  if (status < 0) {
    status = api.av_seek_frame(session->format, session->video_index,
                               target_timestamp, AVSEEK_FLAG_BACKWARD);
  }
  if (status < 0 && target_ms > 0) {
    setError(error, error_capacity, avError(api, "Seek", status));
    return kSeekFailed;
  }
  api.avcodec_flush_buffers(session->codec);

  const int64_t acceptable_timestamp =
      target_timestamp -
      millisecondsToTimestamp(1500, session->stream->time_base);
  bool decoded = false;
  int packets_read = 0;
  while (!decoded && packets_read < 1024) {
    if (session->cancelled.load()) return kCancelled;
    status = api.av_read_frame(session->format, session->packet);
    if (status < 0) break;
    ++packets_read;
    if (session->packet->stream_index != session->video_index) {
      api.av_packet_unref(session->packet);
      continue;
    }
    status = api.avcodec_send_packet(session->codec, session->packet);
    api.av_packet_unref(session->packet);
    if (status < 0) continue;
    while ((status = api.avcodec_receive_frame(session->codec, session->frame)) >=
           0) {
      const int64_t timestamp = session->frame->best_effort_timestamp;
      if (timestamp == AV_NOPTS_VALUE || timestamp >= acceptable_timestamp) {
        decoded = true;
        break;
      }
      api.av_frame_unref(session->frame);
    }
  }
  if (session->cancelled.load()) return kCancelled;
  if (!decoded || session->frame->width <= 0 || session->frame->height <= 0) {
    setError(error, error_capacity,
             "No video frame was decoded with the available segment context.");
    return kNoFrame;
  }

  AVRational sample_aspect = api.av_guess_sample_aspect_ratio(
      session->format, session->stream, session->frame);
  if (sample_aspect.num <= 0 || sample_aspect.den <= 0) {
    sample_aspect = session->frame->sample_aspect_ratio;
  }
  if (sample_aspect.num <= 0 || sample_aspect.den <= 0) {
    sample_aspect = AVRational{1, 1};
  }
  const int rotation = frameRotation(api, session->stream, session->frame);
  int output_width = 0;
  int output_height = 0;
  double display_aspect = 0;
  if (mirushin_seek_thumbnail_output_size(
          session->frame->width, session->frame->height, sample_aspect.num,
          sample_aspect.den, rotation, target_width, &output_width,
          &output_height, &display_aspect) != kOk) {
    setError(error, error_capacity, "Decoded frame display aspect is invalid.");
    return kScaleFailed;
  }

  const bool swaps_axes = rotation == 90 || rotation == 270;
  const int scaled_width = swaps_axes ? output_height : output_width;
  const int scaled_height = swaps_axes ? output_width : output_height;
  const size_t output_size =
      static_cast<size_t>(output_width) * output_height * 4;
  const size_t scaled_size =
      static_cast<size_t>(scaled_width) * scaled_height * 4;
  if (output_size > static_cast<size_t>(std::numeric_limits<int>::max()) ||
      scaled_size > static_cast<size_t>(std::numeric_limits<int>::max())) {
    setError(error, error_capacity, "Decoded frame is too large.");
    return kScaleFailed;
  }

  uint8_t* scaled = static_cast<uint8_t*>(std::malloc(scaled_size));
  if (scaled == nullptr) {
    setError(error, error_capacity, "Allocate thumbnail pixels failed.");
    return kScaleFailed;
  }
  SwsContext* scaler = api.sws_getContext(
      session->frame->width, session->frame->height,
      static_cast<AVPixelFormat>(session->frame->format), scaled_width,
      scaled_height, AV_PIX_FMT_RGBA, SWS_FAST_BILINEAR, nullptr, nullptr,
      nullptr);
  if (scaler == nullptr) {
    std::free(scaled);
    setError(error, error_capacity, "Create thumbnail scaler failed.");
    return kScaleFailed;
  }
  uint8_t* destination_data[4] = {scaled, nullptr, nullptr, nullptr};
  int destination_lines[4] = {scaled_width * 4, 0, 0, 0};
  status = api.sws_scale(scaler, session->frame->data,
                         session->frame->linesize, 0, session->frame->height,
                         destination_data, destination_lines);
  api.sws_freeContext(scaler);
  if (status <= 0) {
    std::free(scaled);
    setError(error, error_capacity, "Scale thumbnail frame failed.");
    return kScaleFailed;
  }

  uint8_t* output = scaled;
  if (rotation != 0) {
    output = static_cast<uint8_t*>(std::malloc(output_size));
    if (output == nullptr) {
      std::free(scaled);
      setError(error, error_capacity, "Allocate rotated thumbnail failed.");
      return kScaleFailed;
    }
    rotateRgba(scaled, scaled_width, scaled_height, rotation, output);
    std::free(scaled);
  }

  *rgba = output;
  *rgba_length = static_cast<int>(output_size);
  *width = output_width;
  *height = output_height;
  *decoded_ms = timestampToMilliseconds(
      session->frame->best_effort_timestamp, session->stream->time_base);
  *coded_width = session->frame->width;
  *coded_height = session->frame->height;
  *sar_num = sample_aspect.num;
  *sar_den = sample_aspect.den;
  *rotation_degrees = rotation;
  *display_aspect_ratio = display_aspect;
  return kOk;
}

extern "C" void mirushin_seek_thumbnail_session_destroy(void* handle) {
  auto* session = static_cast<DecoderSession*>(handle);
  if (session == nullptr) return;
  session->cancelled.store(true);
  closeSession(session);
  delete session;
}

extern "C" int mirushin_seek_thumbnail_decode(
    const char* input, const char* http_headers, int64_t target_ms,
    int target_width, uint8_t** rgba, int* rgba_length, int* width, int* height,
    int64_t* decoded_ms, char* error, int error_capacity) {
  auto* session = static_cast<DecoderSession*>(
      mirushin_seek_thumbnail_session_create());
  if (session == nullptr) {
    setError(error, error_capacity, ffmpeg().error);
    return kRuntimeUnavailable;
  }
  mirushin_seek_thumbnail_session_reset_cancel(session);
  int status = mirushin_seek_thumbnail_session_open(
      session, input, http_headers, error, error_capacity);
  if (status == kOk) {
    int coded_width = 0;
    int coded_height = 0;
    int sar_num = 1;
    int sar_den = 1;
    int rotation = 0;
    double display_aspect = 0;
    status = mirushin_seek_thumbnail_session_decode(
        session, target_ms, target_width, rgba, rgba_length, width, height,
        decoded_ms, &coded_width, &coded_height, &sar_num, &sar_den, &rotation,
        &display_aspect, error, error_capacity);
  }
  mirushin_seek_thumbnail_session_destroy(session);
  return status;
}

extern "C" void mirushin_seek_thumbnail_free(uint8_t* data) {
  std::free(data);
}
