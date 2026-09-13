#include "../socket_path.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>

int main(void) {
    char buf[1024];
    int rc = build_socket_path("/Users/testuser", buf, sizeof(buf));
    assert(rc == 0);
    assert(strcmp(buf, "/Users/testuser/Library/Application Support/faceunlock/faceunlock.sock") == 0);
    printf("build_socket_path normal case: PASS\n");

    char tiny[10];
    rc = build_socket_path("/Users/testuser", tiny, sizeof(tiny));
    assert(rc == -1);
    printf("build_socket_path truncation detected: PASS\n");

    printf("ALL TESTS PASSED\n");
    return 0;
}
