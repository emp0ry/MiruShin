#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdocumentation"
#include <mdk/Player.h>
#pragma clang diagnostic pop

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cmath>
#include <condition_variable>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <memory>
#include <mutex>
#include <string>
#include <vector>

#define MIRUSHIN_EXPORT extern "C" __attribute__((visibility("default"), used))

namespace {

struct DecodeResultState {
  std::atomic<bool> cancelled{false};
  std::mutex resultMutex;
  std::condition_variable resultReady;
  bool finished = false;
  int status = -15;
  std::vector<uint8_t> pixels;
  int width = 0;
  int height = 0;
  int codedWidth = 0;
  int codedHeight = 0;
  int64_t decodedMs = -1;
};

struct ThumbnailSession {
  std::atomic<bool> cancelled{false};
  std::atomic<bool> prepared{false};
  std::mutex activeMutex;
  std::shared_ptr<DecodeResultState> activeResult;
  std::unique_ptr<mdk::Player> player;
};

void writeError(const char* message, char* output, int32_t capacity) {
  if (!output || capacity <= 0) return;
  std::strncpy(output, message, static_cast<size_t>(capacity - 1));
  output[capacity - 1] = '\0';
}

void finish(const std::shared_ptr<DecodeResultState>& result, int status) {
  {
    std::lock_guard<std::mutex> lock(result->resultMutex);
    if (result->finished) return;
    result->status = status;
    result->finished = true;
  }
  result->resultReady.notify_all();
}

void cancelActiveResult(ThumbnailSession* session) {
  std::shared_ptr<DecodeResultState> result;
  {
    std::lock_guard<std::mutex> lock(session->activeMutex);
    result = session->activeResult;
  }
  if (!result) return;
  result->cancelled.store(true);
  result->resultReady.notify_all();
}

void clearActiveResult(
    ThumbnailSession* session,
    const std::shared_ptr<DecodeResultState>& result) {
  std::lock_guard<std::mutex> lock(session->activeMutex);
  if (session->activeResult == result) session->activeResult.reset();
}

void configureHeaders(mdk::Player& player, const char* headers) {
  if (headers && headers[0] != '\0') {
    player.setProperty("avio.headers", headers);
  }
  player.setProperty("avformat.strict", "experimental");
  player.setProperty("avformat.safe", "0");
  player.setProperty("avformat.extension_picky", "0");
  player.setProperty("avformat.allowed_segment_extensions", "ALL");
  player.setProperty("avio.rw_timeout", "1800000");
  player.setProperty("buffer.range", "0+4000");
}

}  // namespace

MIRUSHIN_EXPORT void* mirushin_seek_thumbnail_session_create() {
  return new (std::nothrow) ThumbnailSession();
}

MIRUSHIN_EXPORT void mirushin_seek_thumbnail_session_reset_cancel(void* value) {
  if (!value) return;
  static_cast<ThumbnailSession*>(value)->cancelled.store(false);
}

MIRUSHIN_EXPORT void mirushin_seek_thumbnail_session_cancel(void* value) {
  if (!value) return;
  auto* session = static_cast<ThumbnailSession*>(value);
  session->cancelled.store(true);
  cancelActiveResult(session);
}

MIRUSHIN_EXPORT int32_t mirushin_seek_thumbnail_session_open(
    void* value,
    const char* input,
    const char* headers,
    char* error,
    int32_t errorCapacity) {
  if (!value || !input || input[0] == '\0') return -10;
  auto* session = static_cast<ThumbnailSession*>(value);
  try {
    session->player = std::unique_ptr<mdk::Player>(new mdk::Player());
    session->player->setMute(true);
    session->player->setVolume(0);
    configureHeaders(*session->player, headers);
    session->player->setMedia(input);
    session->player->setActiveTracks(mdk::MediaType::Audio, {});
    session->prepared.store(false);
    return 0;
  } catch (...) {
    writeError("MDK thumbnail input open failed.", error, errorCapacity);
    session->player.reset();
    return -10;
  }
}

MIRUSHIN_EXPORT int32_t mirushin_seek_thumbnail_session_decode(
    void* value,
    int64_t targetMs,
    int32_t targetWidth,
    uint8_t** rgba,
    int32_t* rgbaLength,
    int32_t* width,
    int32_t* height,
    int64_t* decodedMs,
    int32_t* codedWidth,
    int32_t* codedHeight,
    int32_t* sarNum,
    int32_t* sarDen,
    int32_t* rotationDegrees,
    double* displayAspectRatio,
    char* error,
    int32_t errorCapacity) {
  if (!value || !rgba || !rgbaLength || !width || !height || !decodedMs ||
      !codedWidth || !codedHeight || !sarNum || !sarDen ||
      !rotationDegrees || !displayAspectRatio) {
    return -1;
  }
  *rgba = nullptr;
  *rgbaLength = 0;
  auto* session = static_cast<ThumbnailSession*>(value);
  if (!session->player || session->cancelled.load()) return -20;

  const auto result = std::make_shared<DecodeResultState>();
  {
    std::lock_guard<std::mutex> lock(session->activeMutex);
    session->activeResult = result;
    if (session->cancelled.load()) result->cancelled.store(true);
  }
  if (result->cancelled.load()) {
    clearActiveResult(session, result);
    return -20;
  }

  const int outputWidth = std::max(1, static_cast<int>(targetWidth));
  session->player->onFrame<mdk::VideoFrame>(
      [result, outputWidth](mdk::VideoFrame& frame, int) -> int {
        if (result->cancelled.load() || !frame) return 0;
        const int sourceWidth = frame.width();
        const int sourceHeight = frame.height();
        if (sourceWidth <= 0 || sourceHeight <= 0) {
          finish(result, -15);
          return 0;
        }
        const int outputHeight = std::max(
            1, static_cast<int>(std::lround(
                   static_cast<double>(sourceHeight) * outputWidth /
                   sourceWidth)));
        mdk::VideoFrame converted =
            frame.to(mdk::PixelFormat::RGBA, outputWidth, outputHeight);
        const uint8_t* data = converted ? converted.bufferData(0) : nullptr;
        const int stride = converted ? converted.bytesPerLine(0) : 0;
        if (!data || std::abs(stride) < outputWidth * 4) {
          finish(result, -16);
          return 0;
        }
        std::vector<uint8_t> pixels(
            static_cast<size_t>(outputWidth * outputHeight * 4));
        for (int row = 0; row < outputHeight; ++row) {
          const int sourceRow = stride >= 0 ? row : outputHeight - 1 - row;
          std::memcpy(
              pixels.data() + static_cast<size_t>(row * outputWidth * 4),
              data + static_cast<ptrdiff_t>(sourceRow) * std::abs(stride),
              static_cast<size_t>(outputWidth * 4));
        }
        {
          std::lock_guard<std::mutex> lock(result->resultMutex);
          if (result->finished || result->cancelled.load()) return 0;
          result->pixels = std::move(pixels);
          result->width = outputWidth;
          result->height = outputHeight;
          result->codedWidth = sourceWidth;
          result->codedHeight = sourceHeight;
          const double timestamp = frame.timestamp();
          result->decodedMs = std::isfinite(timestamp)
              ? static_cast<int64_t>(std::llround(timestamp * 1000.0))
              : -1;
          result->status = 0;
          result->finished = true;
        }
        result->resultReady.notify_all();
        return 0;
      });

  const int64_t requestedPosition = std::max<int64_t>(1, targetMs);
  if (session->prepared.load()) {
    const bool accepted = session->player->seek(
        requestedPosition,
        [result](int64_t position) {
          if (position < 0) finish(result, -14);
        });
    if (!accepted) finish(result, -14);
  } else {
    session->player->prepare(
        requestedPosition,
        [result](int64_t position, bool* boost) {
          if (boost) *boost = true;
          if (position < 0) {
            finish(result, -10);
            return false;
          }
          return true;
        });
  }

  {
    std::unique_lock<std::mutex> lock(result->resultMutex);
    result->resultReady.wait_for(
        lock, std::chrono::seconds(6), [result] {
          return result->finished || result->cancelled.load();
        });
  }
  session->player->onFrame<mdk::VideoFrame>(
      std::function<int(mdk::VideoFrame&, int)>());
  clearActiveResult(session, result);

  if (session->cancelled.load() || result->cancelled.load()) return -20;
  std::lock_guard<std::mutex> lock(result->resultMutex);
  if (!result->finished || result->status != 0) {
    writeError("MDK thumbnail frame decode failed.", error, errorCapacity);
    return result->finished ? result->status : -15;
  }
  session->prepared.store(true);
  const size_t byteCount = result->pixels.size();
  auto* output = static_cast<uint8_t*>(std::malloc(byteCount));
  if (!output) return -16;
  std::memcpy(output, result->pixels.data(), byteCount);
  *rgba = output;
  *rgbaLength = static_cast<int32_t>(byteCount);
  *width = result->width;
  *height = result->height;
  *decodedMs = result->decodedMs >= 0 ? result->decodedMs : targetMs;
  *codedWidth = result->codedWidth;
  *codedHeight = result->codedHeight;
  *sarNum = 1;
  *sarDen = 1;
  *rotationDegrees = 0;
  *displayAspectRatio = static_cast<double>(result->width) / result->height;
  return 0;
}

MIRUSHIN_EXPORT void mirushin_seek_thumbnail_session_destroy(void* value) {
  if (!value) return;
  auto* session = static_cast<ThumbnailSession*>(value);
  session->cancelled.store(true);
  cancelActiveResult(session);
  if (session->player) {
    session->player->onFrame<mdk::VideoFrame>(
        std::function<int(mdk::VideoFrame&, int)>());
    session->player.reset();
  }
  delete session;
}
