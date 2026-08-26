#pragma once

#include <stdint.h>

#if defined(_WIN32)
#define MIRUSHIN_THUMBNAIL_EXPORT __declspec(dllexport)
#else
#define MIRUSHIN_THUMBNAIL_EXPORT __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C" {
#endif

// Decodes one frame into a newly allocated tightly-packed RGBA buffer.
// Returns zero on success. The caller owns *rgba and must release it with
// mirushin_seek_thumbnail_free.
MIRUSHIN_THUMBNAIL_EXPORT int mirushin_seek_thumbnail_decode(
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
    int error_capacity);

MIRUSHIN_THUMBNAIL_EXPORT void mirushin_seek_thumbnail_free(uint8_t* data);

#ifdef __cplusplus
}
#endif
