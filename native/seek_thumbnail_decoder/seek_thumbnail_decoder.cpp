#include "seek_thumbnail_decoder.h"

#include <algorithm>
#include <atomic>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <limits>
#include <mutex>
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
#include "libavutil/imgutils.h"
#include "libswscale/swscale.h"
}

namespace {

#if defined(_WIN32)
using LibraryHandle = HMODULE;
#else
using LibraryHandle = void*;
#endif

struct Api {
  LibraryHandle library = nullptr;
  bool ready = false;
  std::string error;

  unsigned (*avformat_version)() = nullptr;
  unsigned (*avcodec_version)() = nullptr;
  int (*avformat_network_init)() = nullptr;
  int (*avformat_open_input)(AVFormatContext**, const char*,
                             const AVInputFormat*, AVDictionary**) = nullptr;
  int (*avformat_find_stream_info)(AVFormatContext*, AVDictionary**) = nullptr;
  int (*av_find_best_stream)(AVFormatContext*, AVMediaType, int, int,
                             const AVCodec**, int) = nullptr;
  void (*avformat_close_input)(AVFormatContext**) = nullptr;
  int (*avformat_seek_file)(AVFormatContext*, int, int64_t, int64_t, int64_t,
                            int) = nullptr;
  int (*av_read_frame)(AVFormatContext*, AVPacket*) = nullptr;

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
  AVFrame* (*av_frame_alloc)() = nullptr;
  void (*av_frame_unref)(AVFrame*) = nullptr;
  void (*av_frame_free)(AVFrame**) = nullptr;
  int (*av_dict_set)(AVDictionary**, const char*, const char*, int) = nullptr;
  void (*av_dict_free)(AVDictionary**) = nullptr;
  int (*av_strerror)(int, char*, size_t) = nullptr;

  SwsContext* (*sws_getContext)(int, int, AVPixelFormat, int, int,
                                AVPixelFormat, int, SwsFilter*, SwsFilter*,
                                const double*) = nullptr;
  int (*sws_scale)(SwsContext*, const uint8_t* const[], const int[], int, int,
                   uint8_t* const[], const int[]) = nullptr;
  void (*sws_freeContext)(SwsContext*) = nullptr;
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
  LOAD(avformat_open_input)
  LOAD(avformat_find_stream_info)
  LOAD(av_find_best_stream)
  LOAD(avformat_close_input)
  LOAD(avformat_seek_file)
  LOAD(av_read_frame)
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
  LOAD(av_frame_alloc)
  LOAD(av_frame_unref)
  LOAD(av_frame_free)
  LOAD(av_dict_set)
  LOAD(av_dict_free)
  LOAD(av_strerror)
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

int64_t millisecondsToTimestamp(int64_t milliseconds, AVRational time_base) {
  if (time_base.num <= 0 || time_base.den <= 0) return milliseconds;
  const long double ticks =
      static_cast<long double>(milliseconds) * time_base.den /
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
  const long double milliseconds =
      static_cast<long double>(timestamp) * time_base.num * 1000.0L /
      time_base.den;
  return static_cast<int64_t>(std::llround(milliseconds));
}

}  // namespace

extern "C" int mirushin_seek_thumbnail_decode(
    const char* input,
    const char* http_headers,
    int64_t target_ms,
    int target_width,
    uint8_t** rgba,
    int* rgba_length,
    int* width,
    int* height,
    int64_t* decoded_ms,
    char* error,
    int error_capacity) {
  if (rgba == nullptr || rgba_length == nullptr || width == nullptr ||
      height == nullptr || decoded_ms == nullptr || input == nullptr ||
      input[0] == '\0') {
    setError(error, error_capacity, "Invalid thumbnail decoder arguments.");
    return -1;
  }
  *rgba = nullptr;
  *rgba_length = 0;
  *width = 0;
  *height = 0;
  *decoded_ms = -1;

  Api& api = ffmpeg();
  if (!api.ready) {
    setError(error, error_capacity, api.error);
    return -2;
  }

  AVFormatContext* format = nullptr;
  AVCodecContext* codec_context = nullptr;
  AVPacket* packet = nullptr;
  AVFrame* frame = nullptr;
  SwsContext* scaler = nullptr;
  AVDictionary* options = nullptr;
  uint8_t* output = nullptr;
  int result = -3;
  std::string failure;
  const AVCodec* codec = nullptr;
  int video_index = -1;
  AVStream* stream = nullptr;
  int64_t target_timestamp = 0;
  bool decoded = false;
  int packets_read = 0;
  int output_width = 0;
  int output_height = 0;
  size_t output_size = 0;
  uint8_t* destination_data[4] = {nullptr, nullptr, nullptr, nullptr};
  int destination_lines[4] = {0, 0, 0, 0};

  api.av_dict_set(&options, "rw_timeout", "2500000", 0);
  api.av_dict_set(&options, "reconnect", "1", 0);
  api.av_dict_set(&options, "reconnect_streamed", "1", 0);
  api.av_dict_set(&options, "reconnect_delay_max", "1", 0);
  if (http_headers != nullptr && http_headers[0] != '\0') {
    api.av_dict_set(&options, "headers", http_headers, 0);
  }

  int status = api.avformat_open_input(&format, input, nullptr, &options);
  api.av_dict_free(&options);
  if (status < 0) {
    failure = avError(api, "Open input", status);
    goto cleanup;
  }
  status = api.avformat_find_stream_info(format, nullptr);
  if (status < 0) {
    failure = avError(api, "Read stream info", status);
    goto cleanup;
  }

  video_index = api.av_find_best_stream(
      format, AVMEDIA_TYPE_VIDEO, -1, -1, &codec, 0);
  if (video_index < 0 || codec == nullptr) {
    failure = "No decodable video stream was found.";
    goto cleanup;
  }
  stream = format->streams[video_index];
  codec_context = api.avcodec_alloc_context3(codec);
  if (codec_context == nullptr) {
    failure = "Allocate decoder context failed.";
    goto cleanup;
  }
  status = api.avcodec_parameters_to_context(codec_context, stream->codecpar);
  if (status < 0) {
    failure = avError(api, "Copy codec parameters", status);
    goto cleanup;
  }
  status = api.avcodec_open2(codec_context, codec, nullptr);
  if (status < 0) {
    failure = avError(api, "Open decoder", status);
    goto cleanup;
  }

  packet = api.av_packet_alloc();
  frame = api.av_frame_alloc();
  if (packet == nullptr || frame == nullptr) {
    failure = "Allocate decoder frame failed.";
    goto cleanup;
  }

  target_timestamp =
      stream->start_time == AV_NOPTS_VALUE ? 0 : stream->start_time;
  if (target_ms > 0) {
    target_timestamp += millisecondsToTimestamp(target_ms, stream->time_base);
    status = api.avformat_seek_file(
        format, video_index, std::numeric_limits<int64_t>::min(),
        target_timestamp, target_timestamp, AVSEEK_FLAG_BACKWARD);
    if (status >= 0) api.avcodec_flush_buffers(codec_context);
  }

  while (!decoded && packets_read < 512 && api.av_read_frame(format, packet) >= 0) {
    packets_read += 1;
    if (packet->stream_index != video_index) {
      api.av_packet_unref(packet);
      continue;
    }
    status = api.avcodec_send_packet(codec_context, packet);
    api.av_packet_unref(packet);
    if (status < 0) continue;
    while ((status = api.avcodec_receive_frame(codec_context, frame)) >= 0) {
      const int64_t timestamp = frame->best_effort_timestamp;
      if (target_ms <= 0 || timestamp == AV_NOPTS_VALUE ||
          timestamp >= target_timestamp) {
        decoded = true;
        break;
      }
      api.av_frame_unref(frame);
    }
  }
  if (!decoded || frame->width <= 0 || frame->height <= 0) {
    failure = "No video frame was decoded near the requested timestamp.";
    goto cleanup;
  }

  output_width = std::max(1, target_width);
  output_height = std::max(
      1, static_cast<int>(std::llround(
             static_cast<long double>(frame->height) * output_width /
             frame->width)));
  if (output_height > 720) {
    failure = "Decoded frame aspect ratio is invalid.";
    goto cleanup;
  }
  output_size = static_cast<size_t>(output_width) * output_height * 4;
  if (output_size > static_cast<size_t>(std::numeric_limits<int>::max())) {
    failure = "Decoded frame is too large.";
    goto cleanup;
  }
  output = static_cast<uint8_t*>(std::malloc(output_size));
  if (output == nullptr) {
    failure = "Allocate thumbnail pixels failed.";
    goto cleanup;
  }
  scaler = api.sws_getContext(
      frame->width, frame->height, static_cast<AVPixelFormat>(frame->format),
      output_width, output_height, AV_PIX_FMT_RGBA, SWS_FAST_BILINEAR, nullptr,
      nullptr, nullptr);
  if (scaler == nullptr) {
    failure = "Create thumbnail scaler failed.";
    goto cleanup;
  }
  destination_data[0] = output;
  destination_lines[0] = output_width * 4;
  status = api.sws_scale(scaler, frame->data, frame->linesize, 0, frame->height,
                         destination_data, destination_lines);
  if (status <= 0) {
    failure = "Scale thumbnail frame failed.";
    goto cleanup;
  }

  *rgba = output;
  *rgba_length = static_cast<int>(output_size);
  *width = output_width;
  *height = output_height;
  *decoded_ms = timestampToMilliseconds(frame->best_effort_timestamp,
                                         stream->time_base);
  output = nullptr;
  result = 0;

cleanup:
  if (output != nullptr) std::free(output);
  if (scaler != nullptr) api.sws_freeContext(scaler);
  if (frame != nullptr) api.av_frame_free(&frame);
  if (packet != nullptr) api.av_packet_free(&packet);
  if (codec_context != nullptr) api.avcodec_free_context(&codec_context);
  if (format != nullptr) api.avformat_close_input(&format);
  if (result != 0) setError(error, error_capacity, failure);
  return result;
}

extern "C" void mirushin_seek_thumbnail_free(uint8_t* data) {
  std::free(data);
}
