#ifndef SOCKET_OWNER_H
#define SOCKET_OWNER_H

#include <sys/types.h>

/* Verifies that path is a Unix domain socket (not a symlink, regular file,
 * etc.) owned by expected_uid. Returns 1 if so, 0 otherwise (including if
 * path doesn't exist or lstat fails). Uses lstat, not stat, so a symlink
 * planted by another user is rejected rather than followed. */
int verify_socket_ownership(const char *path, uid_t expected_uid);

#endif
