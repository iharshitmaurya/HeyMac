#include "socket_owner.h"
#include <sys/stat.h>

int verify_socket_ownership(const char *path, uid_t expected_uid) {
    struct stat st;
    if (lstat(path, &st) != 0) return 0;
    if (!S_ISSOCK(st.st_mode)) return 0;
    if (st.st_uid != expected_uid) return 0;
    return 1;
}
