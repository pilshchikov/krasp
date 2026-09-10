#include <assert.h>
#include <stdlib.h>
#include <stdio.h>
#include <fcntl.h>
#include <unistd.h>

static int testFD;
static int OpenTestRing(const char* path, int flags, ...) {
    (void)path;
    (void)flags;
    return dup(testFD);
}

#define open OpenTestRing
#include "../../HAL/KraspHAL/KraspHAL.c"
#undef open

int main(void) {
    char path[] = "/tmp/krasp-ring-test-XXXXXX";
    testFD = mkstemp(path);
    assert(testFD >= 0);
    unlink(path);

    // A writer may have created the file without sizing it yet.
    OpenRingIfNeeded();
    assert(gRing == NULL);
    assert(ftruncate(testFD, (off_t)gRingByteCount - 1) == 0);
    OpenRingIfNeeded();
    assert(gRing == NULL);

    KraspSharedRing* ring = calloc(1, gRingByteCount);
    assert(ring != NULL);
    ring->magic = KRASP_RING_MAGIC;
    ring->version = KRASP_RING_VERSION;
    ring->capacityFrames = KRASP_RING_CAPACITY_FRAMES;
    assert(ftruncate(testFD, (off_t)gRingByteCount) == 0);
    assert(pwrite(testFD, ring, gRingByteCount, 0) == (ssize_t)gRingByteCount);
    OpenRingIfNeeded();
    assert(gRing != NULL);
    munmap(gRing, gRingByteCount);
    gRing = ring;

    float output[4];
    ring->samples[0] = 0.25f;
    ring->samples[1] = 0.5f;
    ring->writeIndex = 2;
    gReadIndex = 0;
    ReadRing(output, 4);
    assert(output[0] == 0 && output[1] == 0);
    assert(output[2] == 0.25f && output[3] == 0.5f);
    ReadRing(output, 4);
    assert(output[0] == 0 && output[3] == 0);

    gReadIndex = KRASP_RING_CAPACITY_FRAMES - 1;
    ring->writeIndex = gReadIndex + 2;
    ring->samples[KRASP_RING_CAPACITY_FRAMES - 1] = 0.75f;
    ReadRing(output, 2);
    assert(output[0] == 0.75f && output[1] == 0.25f);

    free(ring);
    gRing = NULL;
    close(testFD);
    puts("HAL ring tests passed");
    return 0;
}
