#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#include "../Limelight/Startup/ReadinessFrameMatcher.h"

static uint8_t reference[READINESS_FRAME_WIDTH * READINESS_FRAME_HEIGHT * READINESS_FRAME_BYTES_PER_PIXEL];
static uint8_t stream[READINESS_FRAME_WIDTH * READINESS_FRAME_HEIGHT * READINESS_FRAME_BYTES_PER_PIXEL];

static void testIdenticalFramesAndInvalidInput(void) {
    memset(reference, 127, sizeof(reference));
    memcpy(stream, reference, sizeof(stream));
    assert(ReadinessFrameMatcherMatches(reference, stream, READINESS_FRAME_WIDTH, READINESS_FRAME_HEIGHT));
    assert(!ReadinessFrameMatcherMatches(NULL, stream, READINESS_FRAME_WIDTH, READINESS_FRAME_HEIGHT));
    assert(!ReadinessFrameMatcherMatches(reference, stream, 0, READINESS_FRAME_HEIGHT));
    assert(!ReadinessFrameMatcherMatches(reference, stream, SIZE_MAX, 2));
}

static void testMeanDifferenceBoundary(void) {
    memset(reference, 0, sizeof(reference));
    memset(stream, 0, sizeof(stream));
    size_t pixelCount = READINESS_FRAME_WIDTH * READINESS_FRAME_HEIGHT;
    for (size_t i = 0; i < pixelCount; i++) {
        stream[i * 4] = 22;
        stream[i * 4 + 1] = 22;
        stream[i * 4 + 2] = 22;
        stream[i * 4 + 3] = 255;
    }
    assert(ReadinessFrameMatcherMatches(reference, stream, READINESS_FRAME_WIDTH, READINESS_FRAME_HEIGHT));
    for (size_t i = 0; i < pixelCount; i++) {
        stream[i * 4] = 23;
        stream[i * 4 + 1] = 23;
        stream[i * 4 + 2] = 23;
    }
    assert(!ReadinessFrameMatcherMatches(reference, stream, READINESS_FRAME_WIDTH, READINESS_FRAME_HEIGHT));
}

static void testDifferingPixelBoundary(void) {
    size_t pixelCount = READINESS_FRAME_WIDTH * READINESS_FRAME_HEIGHT;
    memset(reference, 0, sizeof(reference));
    memset(stream, 0, sizeof(stream));

    for (size_t i = 0; i < pixelCount / 8; i++) {
        stream[i * 4] = 56;
        stream[i * 4 + 1] = 56;
        stream[i * 4 + 2] = 56;
    }
    assert(ReadinessFrameMatcherMatches(reference, stream, READINESS_FRAME_WIDTH, READINESS_FRAME_HEIGHT));

    stream[(pixelCount / 8) * 4] = 56;
    stream[(pixelCount / 8) * 4 + 1] = 56;
    stream[(pixelCount / 8) * 4 + 2] = 56;
    assert(!ReadinessFrameMatcherMatches(reference, stream, READINESS_FRAME_WIDTH, READINESS_FRAME_HEIGHT));
}

int main(void) {
    testIdenticalFramesAndInvalidInput();
    testMeanDifferenceBoundary();
    testDifferingPixelBoundary();
    puts("Readiness frame matcher tests passed");
    return 0;
}
