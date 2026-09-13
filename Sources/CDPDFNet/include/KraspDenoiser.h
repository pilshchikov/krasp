#ifndef KRASP_DENOISER_H
#define KRASP_DENOISER_H
#include <stdint.h>
typedef struct KraspDenoiser KraspDenoiser;
KraspDenoiser *krasp_denoiser_create(const char *library, const char *model, char *error, int32_t error_capacity);
void krasp_denoiser_destroy(KraspDenoiser *state);
void krasp_denoiser_reset(KraspDenoiser *state);
// One 480-sample hop. Returns 0 during warmup, 480 on success, -1 on failure.
int32_t krasp_denoiser_process(KraspDenoiser *state, const float *input, float *output);
#endif
