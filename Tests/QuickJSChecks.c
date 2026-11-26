#include "../Runtime/Bridge.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static const char *host(void *opaque, const char *method, const char *arguments) {
    int *calls = opaque;
    if (strcmp(method, "commit") == 0 && strcmp(arguments, "[\"5\"]") == 0) (*calls)++;
    return "null";
}

static void run(ERRuntime *runtime, const char *script, const char *expected) {
    int failed;
    char *result = EREval(runtime, script, 120, &failed);
    assert(!failed && result && strcmp(result, expected) == 0);
    ERFreeString(result);
}

static void load(ERRuntime *runtime, const char *path) {
    FILE *input = fopen(path, "rb");
    assert(input);
    fseek(input, 0, SEEK_END);
    size_t length = (size_t)ftell(input);
    rewind(input);
    char *source = calloc(length + 1, 1);
    assert(source && fread(source, 1, length, input) == length);
    int failed;
    char *result = EREval(runtime, source, 120, &failed);
    assert(!failed);
    ERFreeString(result);
    free(source);
    fclose(input);
}

int main(void) {
    int calls = 0;
    ERRuntime *runtime = ERCreate(host, &calls);
    assert(runtime);
    load(runtime, "KeyboardData/bootstrap.js");
    run(runtime, "typeof kb.tone", "function");
    load(runtime, "KeyboardData/plugins/calculator.js");
    run(runtime, "__expressiveDispatch('$catalog').panels[0].id", "calc");
    run(runtime, "__expressiveDispatch('$render', 0).length", "4");
    run(runtime, "__expressiveDispatch('$panelPick', [0, '2'])", "undefined");
    run(runtime, "__expressiveDispatch('$panelPick', [0, '+'])", "undefined");
    run(runtime, "__expressiveDispatch('$panelPick', [0, '3'])", "undefined");
    run(runtime, "__expressiveDispatch('$panelPick', [2, null])", "undefined");
    assert(calls == 1);
    int failed;
    char *result = EREval(runtime, "while (true) {}", 20, &failed);
    assert(failed);
    ERFreeString(result);
    ERFree(runtime);
    puts("Passed the bundled calculator callbacks and QuickJS execution deadline.");
}
