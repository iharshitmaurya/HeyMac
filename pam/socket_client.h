#ifndef SOCKET_CLIENT_H
#define SOCKET_CLIENT_H

/* Connects to the Unix domain socket at socket_path, writes request, waits up
 * to timeout_ms for a reply starting with "OK". Returns 1 on an "OK" reply,
 * 0 on anything else (FAIL, timeout, connection failure, no reply). */
int send_and_wait(const char *socket_path, const char *request, int timeout_ms);

#endif
