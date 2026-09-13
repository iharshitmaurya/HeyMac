#ifndef SOCKET_PATH_H
#define SOCKET_PATH_H

#include <stddef.h>

/* Writes "<home_dir>/Library/Application Support/faceunlock/faceunlock.sock"
 * into out_path. Returns 0 on success, -1 if out_path was too small
 * (truncated) -- never writes a truncated path as if it succeeded. */
int build_socket_path(const char *home_dir, char *out_path, size_t out_size);

#endif
