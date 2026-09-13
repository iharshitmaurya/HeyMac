#include "../socket_owner.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <sys/stat.h>
#include <stdlib.h>

int main(void) {
    char tmpl[] = "/tmp/faceunlock_owner_test.XXXXXX";
    char *dir = mkdtemp(tmpl);
    assert(dir != NULL);

    char sock_path[1024];
    snprintf(sock_path, sizeof(sock_path), "%s/test.sock", dir);

    int fd = socket(AF_UNIX, SOCK_STREAM, 0);
    assert(fd >= 0);
    struct sockaddr_un addr;
    memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;
    strncpy(addr.sun_path, sock_path, sizeof(addr.sun_path) - 1);
    assert(bind(fd, (struct sockaddr *)&addr, sizeof(addr)) == 0);

    uid_t me = getuid();
    assert(verify_socket_ownership(sock_path, me) == 1);
    printf("verify_socket_ownership real socket, correct uid: PASS\n");

    assert(verify_socket_ownership(sock_path, me + 1) == 0);
    printf("verify_socket_ownership real socket, wrong uid: PASS\n");

    close(fd);
    unlink(sock_path);

    assert(verify_socket_ownership(sock_path, me) == 0);
    printf("verify_socket_ownership missing path: PASS\n");

    char regular_path[1024];
    snprintf(regular_path, sizeof(regular_path), "%s/not_a_socket", dir);
    FILE *f = fopen(regular_path, "w");
    assert(f != NULL);
    fclose(f);
    assert(verify_socket_ownership(regular_path, me) == 0);
    printf("verify_socket_ownership regular file rejected: PASS\n");

    unlink(regular_path);
    rmdir(dir);

    printf("ALL TESTS PASSED\n");
    return 0;
}
