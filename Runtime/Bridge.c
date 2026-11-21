#include "Bridge.h"
#include "quickjs/quickjs.h"
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <zlib.h>

struct ERRuntime {
    JSRuntime *runtime;
    JSContext *context;
    ERHost callback;
    void *opaque;
    int64_t deadline;
};

static int64_t now_ms(void) {
    struct timespec time;
    clock_gettime(CLOCK_MONOTONIC, &time);
    return (int64_t)time.tv_sec * 1000 + time.tv_nsec / 1000000;
}

static int interrupt(JSRuntime *runtime, void *opaque) {
    (void)runtime;
    return now_ms() >= ((ERRuntime *)opaque)->deadline;
}

static JSValue host(JSContext *ctx, JSValueConst self, int argc, JSValueConst *argv) {
    (void)self;
    ERRuntime *runtime = JS_GetContextOpaque(ctx);
    if (argc != 2) return JS_ThrowTypeError(ctx, "Invalid host call");
    size_t length = 0;
    const char *method = JS_ToCString(ctx, argv[0]);
    const char *payload = JS_ToCStringLen(ctx, &length, argv[1]);
    const char *answer = NULL;
    if (method && payload && length <= 262144 && !interrupt(runtime->runtime, runtime))
        answer = runtime->callback(runtime->opaque, method, payload);
    JSValue result = JS_NewString(ctx, answer ? answer : "null");
    JS_FreeCString(ctx, method);
    JS_FreeCString(ctx, payload);
    return result;
}

ERRuntime *ERCreate(ERHost callback, void *opaque) {
    ERRuntime *instance = calloc(1, sizeof(*instance));
    if (!instance) return NULL;
    instance->runtime = JS_NewRuntime();
    if (!instance->runtime) { free(instance); return NULL; }
    JS_SetInterruptHandler(instance->runtime, interrupt, instance);
    JS_SetMemoryLimit(instance->runtime, 8 * 1024 * 1024);
    JS_SetMaxStackSize(instance->runtime, 128 * 1024);
    instance->context = JS_NewContext(instance->runtime);
    if (!instance->context) { JS_FreeRuntime(instance->runtime); free(instance); return NULL; }
    instance->callback = callback;
    instance->opaque = opaque;
    JS_SetContextOpaque(instance->context, instance);
    JSValue global = JS_GetGlobalObject(instance->context);
    JS_SetPropertyStr(instance->context, global, "__expressiveHost", JS_NewCFunction(instance->context, host, "__expressiveHost", 2));
    JS_FreeValue(instance->context, global);
    return instance;
}

char *EREval(ERRuntime *instance, const char *source, int timeout_ms, int *failed) {
    JSContext *ctx = instance->context;
    instance->deadline = now_ms() + timeout_ms;
    JSValue result = JS_Eval(ctx, source, strlen(source), "plugin.js", JS_EVAL_TYPE_GLOBAL);
    *failed = JS_IsException(result);
    JSContext *jobs;
    while (!*failed && !interrupt(instance->runtime, instance) &&
           JS_IsJobPending(instance->runtime)) {
        if (JS_ExecutePendingJob(instance->runtime, &jobs) < 0) {
            JS_FreeValue(ctx, result);
            result = JS_EXCEPTION;
            *failed = 1;
        }
    }
    if (*failed) result = JS_GetException(ctx);
    const char *str = JS_ToCString(ctx, result);
    char *copy = str ? strdup(str) : NULL;
    JS_FreeCString(ctx, str);
    JS_FreeValue(ctx, result);
    return copy;
}

void ERFree(ERRuntime *instance) {
    if (!instance) return;
    JS_FreeContext(instance->context);
    JS_FreeRuntime(instance->runtime);
    free(instance);
}
void ERFreeString(char *str) { free(str); }

int ERInflate(const uint8_t *input, size_t input_size, uint8_t *output, size_t output_size) {
    if (input_size > 8000000 || output_size > 8000000) return 0;
    z_stream stream = {0};
    stream.next_in = (Bytef *)input;
    stream.avail_in = (uInt)input_size;
    stream.next_out = output;
    stream.avail_out = (uInt)output_size;
    if (inflateInit2(&stream, -MAX_WBITS) != Z_OK) return 0;
    int result = inflate(&stream, Z_FINISH);
    inflateEnd(&stream);
    return result == Z_STREAM_END && stream.total_out == output_size;
}
