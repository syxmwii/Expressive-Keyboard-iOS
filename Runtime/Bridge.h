#include <stdint.h>
#include <stddef.h>

typedef struct ERRuntime ERRuntime;
typedef const char *(*ERHost)(void *, const char *, const char *);
ERRuntime *ERCreate(ERHost host, void *opaque);
char *EREval(ERRuntime *runtime, const char *source, int timeout_ms, int *failed);
void ERFree(ERRuntime *runtime);
void ERFreeString(char *);
int ERInflate(const uint8_t *input, size_t input_size, uint8_t *output, size_t output_size);
