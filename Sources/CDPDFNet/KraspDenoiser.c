#include "KraspDenoiser.h"
#include "vendor/c-api.h"
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

struct KraspDenoiser {
    void *library;
    const SherpaOnnxOnlineSpeechDenoiser *engine;
    __typeof__(&SherpaOnnxDestroyOnlineSpeechDenoiser) destroy;
    __typeof__(&SherpaOnnxOnlineSpeechDenoiserReset) reset;
    __typeof__(&SherpaOnnxOnlineSpeechDenoiserRun) run;
    __typeof__(&SherpaOnnxDestroyDenoisedAudio) free_audio;
};

KraspDenoiser *krasp_denoiser_create(const char *library, const char *model, char *error, int32_t capacity) {
    KraspDenoiser *s = calloc(1, sizeof(*s));
    if (!s) return NULL;
    s->library = dlopen(library, RTLD_NOW | RTLD_LOCAL);
    if (!s->library) {
        snprintf(error, capacity, "Cannot load DPDFNet runtime: %s", dlerror());
        free(s);
        return NULL;
    }
    __typeof__(&SherpaOnnxCreateOnlineSpeechDenoiser) create = dlsym(s->library, "SherpaOnnxCreateOnlineSpeechDenoiser");
    __typeof__(&SherpaOnnxOnlineSpeechDenoiserGetSampleRate) rate = dlsym(s->library, "SherpaOnnxOnlineSpeechDenoiserGetSampleRate");
    __typeof__(&SherpaOnnxOnlineSpeechDenoiserGetFrameShiftInSamples) hop = dlsym(s->library, "SherpaOnnxOnlineSpeechDenoiserGetFrameShiftInSamples");
    s->destroy = dlsym(s->library, "SherpaOnnxDestroyOnlineSpeechDenoiser");
    s->reset = dlsym(s->library, "SherpaOnnxOnlineSpeechDenoiserReset");
    s->run = dlsym(s->library, "SherpaOnnxOnlineSpeechDenoiserRun");
    s->free_audio = dlsym(s->library, "SherpaOnnxDestroyDenoisedAudio");
    if (!create || !rate || !hop || !s->destroy || !s->reset || !s->run || !s->free_audio) {
        snprintf(error, capacity, "DPDFNet runtime is missing streaming functions");
        krasp_denoiser_destroy(s);
        return NULL;
    }
    SherpaOnnxOnlineSpeechDenoiserConfig config = {0};
    config.model.dpdfnet.model = model;
    config.model.num_threads = 1;
    config.model.provider = "cpu";
    s->engine = create(&config);
    if (!s->engine || rate(s->engine) != 48000 || hop(s->engine) != 480) {
        snprintf(error, capacity, "Cannot initialize the 48 kHz DPDFNet model");
        krasp_denoiser_destroy(s);
        return NULL;
    }
    return s;
}

void krasp_denoiser_destroy(KraspDenoiser *s) {
    if (!s) return;
    if (s->engine) s->destroy(s->engine);
    if (s->library) dlclose(s->library);
    free(s);
}

void krasp_denoiser_reset(KraspDenoiser *s) {
    if (s && s->engine) s->reset(s->engine);
}

int32_t krasp_denoiser_process(KraspDenoiser *s, const float *input, float *output) {
    if (!s || !s->engine) return -1;
    const SherpaOnnxDenoisedAudio *audio = s->run(s->engine, input, 480, 48000);
    if (!audio) return 0;
    int32_t n = audio->n;
    if (audio->sample_rate != 48000 || (n != 0 && n != 480)) n = -1;
    if (n > 0) memcpy(output, audio->samples, n * sizeof(float));
    s->free_audio(audio);
    return n;
}
