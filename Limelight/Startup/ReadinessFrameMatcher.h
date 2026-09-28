#ifndef READINESS_FRAME_MATCHER_H
#define READINESS_FRAME_MATCHER_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#define READINESS_FRAME_WIDTH 64
#define READINESS_FRAME_HEIGHT 36
#define READINESS_FRAME_BYTES_PER_PIXEL 4

// Input frames are packed RGBA8. The RGB thresholds intentionally mirror the
// Android PixelCopy matcher; alpha is ignored.
bool ReadinessFrameMatcherMatches(const uint8_t *referenceRGBA,
                                  const uint8_t *streamRGBA,
                                  size_t width,
                                  size_t height);

#endif
