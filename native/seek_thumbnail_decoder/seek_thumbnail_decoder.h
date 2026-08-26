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

// Reusable decoder sessions. A session owns libavformat/libavcodec state and
// is safe to cancel from another thread while open/decode is blocked.
MIRUSHIN_THUMBNAIL_EXPORT void* mirushin_seek_thumbnail_session_create(void);
MIRUSHIN_THUMBNAIL_EXPORT void
mirushin_seek_thumbnail_session_reset_cancel(void* session);
MIRUSHIN_THUMBNAIL_EXPORT int mirushin_seek_thumbnail_session_open(
    void* session,
    const char* input,
    const char* http_headers,
    char* error,
    int error_capacity);
MIRUSHIN_THUMBNAIL_EXPORT int mirushin_seek_thumbnail_session_decode(
    void* session,
    int64_t target_ms,
    int target_width,
    uint8_t** rgba,
    int* rgba_length,
    int* width,
    int* height,
    int64_t* decoded_ms,
    int* coded_width,
    int* coded_height,
    int* sar_num,
    int* sar_den,
    int* rotation_degrees,
    double* display_aspect_ratio,
    char* error,
    int error_capacity);
MIRUSHIN_THUMBNAIL_EXPORT void
mirushin_seek_thumbnail_session_cancel(void* session);
MIRUSHIN_THUMBNAIL_EXPORT void
mirushin_seek_thumbnail_session_destroy(void* session);

// Shared production geometry helper, also exported for native regression
// smoke tests. Rotation is normalized to 0/90/180/270 degrees.
MIRUSHIN_THUMBNAIL_EXPORT int mirushin_seek_thumbnail_output_size(
    int coded_width,
    int coded_height,
    int sar_num,
    int sar_den,
    int rotation_degrees,
    int target_width,
    int* output_width,
    int* output_height,
    double* display_aspect_ratio);

MIRUSHIN_THUMBNAIL_EXPORT void mirushin_seek_thumbnail_free(uint8_t* data);

#ifdef __cplusplus
}
#endif
