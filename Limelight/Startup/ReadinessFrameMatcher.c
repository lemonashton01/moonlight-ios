#include "ReadinessFrameMatcher.h"

static unsigned int absoluteDifference(uint8_t left, uint8_t right) {
    return left > right ? (unsigned int)(left - right) : (unsigned int)(right - left);
}

bool ReadinessFrameMatcherMatches(const uint8_t *referenceRGBA,
                                  const uint8_t *streamRGBA,
                                  size_t width,
                                  size_t height) {
    if (referenceRGBA == NULL || streamRGBA == NULL || width == 0 || height == 0 ||
        width > SIZE_MAX / height) {
        return false;
    }

    size_t pixelCount = width * height;
    if (pixelCount > SIZE_MAX / READINESS_FRAME_BYTES_PER_PIXEL) {
        return false;
    }

    uint64_t totalDifference = 0;
    size_t differingPixels = 0;
    for (size_t i = 0; i < pixelCount; i++) {
        size_t offset = i * READINESS_FRAME_BYTES_PER_PIXEL;
        unsigned int pixelDifference =
            (absoluteDifference(referenceRGBA[offset], streamRGBA[offset]) +
             absoluteDifference(referenceRGBA[offset + 1], streamRGBA[offset + 1]) +
             absoluteDifference(referenceRGBA[offset + 2], streamRGBA[offset + 2])) / 3;
        totalDifference += pixelDifference;
        if (pixelDifference > 55) {
            differingPixels++;
        }
    }

    // Integer division and the exact boundary match ReadinessFrameMatcher on Android.
    return totalDifference / pixelCount <= 22 && differingPixels <= pixelCount / 8;
}
