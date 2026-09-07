// Build-time smoke test for the LocalVQE ABI used by the app.
#include <dlfcn.h>
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

int main(int argc, char **argv) {
    if (argc != 3) return 2;
    // A broken model must not hold the dev launch indefinitely.
    alarm(30);
    void *library = dlopen(argv[1], RTLD_NOW | RTLD_LOCAL);
    if (!library) {
        fprintf(stderr, "Echo runtime load failed: %s\n", dlerror());
        return 1;
    }
    uintptr_t (*create)(const char *) = dlsym(library, "localvqe_new");
    int32_t (*process)(uintptr_t, const float *, const float *, int32_t, float *) =
        dlsym(library, "localvqe_process_frame_f32");
    void (*reset)(uintptr_t) = dlsym(library, "localvqe_reset");
    void (*release)(uintptr_t) = dlsym(library, "localvqe_free");
    int32_t (*hop_length)(uintptr_t) = dlsym(library, "localvqe_hop_length");
    if (!create || !process || !reset || !release) {
        fprintf(stderr, "Echo runtime symbols missing\n");
        dlclose(library);
        return 1;
    }
    uintptr_t context = create(argv[2]);
    if (!context) {
        fprintf(stderr, "Echo model initialization failed\n");
        dlclose(library);
        return 1;
    }
    int32_t count = hop_length ? hop_length(context) : 256;
    int status = 1;
    if (count > 0 && count <= 65536) {
        float *input = calloc((size_t)count, sizeof(float));
        float *output = calloc((size_t)count, sizeof(float));
        if (input && output) {
            reset(context);
            status = process(context, input, input, count, output) == 0 ? 0 : 1;
            for (int32_t i = 0; i < count; i++) {
                if (!isfinite(output[i])) status = 1;
            }
        }
        free(input);
        free(output);
    }
    release(context);
    dlclose(library);
    if (status) fprintf(stderr, "Echo runtime frame processing failed\n");
    return status;
}
