#include "../socket_client.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <sys/wait.h>
#include <unistd.h>
#include <signal.h>

/* Forks a one-shot Unix socket server at socket_path that accepts a single
 * connection, reads whatever is sent, then writes `reply` (or, if reply is
 * NULL, never replies, to simulate a hang). Returns the child pid. */
static pid_t spawn_mock_server(const char *socket_path, const char *reply) {
    pid_t pid = fork();
    if (pid != 0) return pid; /* parent returns immediately */

    unlink(socket_path);
    int fd = socket(AF_UNIX, SOCK_STREAM, 0);
    struct sockaddr_un addr;
    memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;
    strncpy(addr.sun_path, socket_path, sizeof(addr.sun_path) - 1);
    bind(fd, (struct sockaddr *)&addr, sizeof(addr));
    listen(fd, 1);

    int client = accept(fd, NULL, NULL);
    char buf[64];
    read(client, buf, sizeof(buf));

    if (reply != NULL) write(client, reply, strlen(reply));

    close(client);
    close(fd);
    unlink(socket_path);
    _exit(0);
}

static void reap(pid_t pid) {
    int status;
    waitpid(pid, &status, 0);
}

static void test_ok_reply_returns_true(void) {
    const char *path = "/tmp/test_socket_client_ok.sock";
    pid_t pid = spawn_mock_server(path, "OK\n");
    usleep(100000); /* let the server bind/listen */
    int result = send_and_wait(path, "VERIFY\n", 2000);
    reap(pid);
    assert(result == 1);
    printf("test_ok_reply_returns_true: PASS\n");
}

static void test_fail_reply_returns_false(void) {
    const char *path = "/tmp/test_socket_client_fail.sock";
    pid_t pid = spawn_mock_server(path, "FAIL\n");
    usleep(100000);
    int result = send_and_wait(path, "VERIFY\n", 2000);
    reap(pid);
    assert(result == 0);
    printf("test_fail_reply_returns_false: PASS\n");
}

static void test_no_listener_returns_false(void) {
    const char *path = "/tmp/test_socket_client_nonexistent.sock";
    unlink(path);
    int result = send_and_wait(path, "VERIFY\n", 500);
    assert(result == 0);
    printf("test_no_listener_returns_false: PASS\n");
}

static void test_timeout_returns_false(void) {
    const char *path = "/tmp/test_socket_client_timeout.sock";
    /* Server accepts and reads, but never replies -- client must time out, not hang. */
    pid_t pid = spawn_mock_server(path, NULL);
    usleep(100000);
    int result = send_and_wait(path, "VERIFY\n", 500);
    reap(pid);
    assert(result == 0);
    printf("test_timeout_returns_false: PASS\n");
}

int main(void) {
    signal(SIGPIPE, SIG_IGN);
    test_ok_reply_returns_true();
    test_fail_reply_returns_false();
    test_no_listener_returns_false();
    test_timeout_returns_false();
    printf("ALL TESTS PASSED\n");
    return 0;
}
