#include "socket_path.h"
#include <stdio.h>

int build_socket_path(const char *home_dir, char *out_path, size_t out_size) {
    int n = snprintf(out_path, out_size, "%s/Library/Application Support/faceunlock/faceunlock.sock", home_dir);
    if (n < 0 || (size_t)n >= out_size) return -1;
    return 0;
}
