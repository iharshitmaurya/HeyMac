CC = clang
CFLAGS = -Wall -Wextra
LDFLAGS = -bundle -lpam

MODULE = pam_faceunlock.so
SOURCES = pam_faceunlock.c socket_client.c socket_path.c

.PHONY: all test clean

all: $(MODULE)

$(MODULE): $(SOURCES) socket_client.h socket_path.h
	$(CC) $(CFLAGS) $(LDFLAGS) -o $(MODULE) $(SOURCES)

test:
	$(CC) $(CFLAGS) -o /tmp/test_socket_client tests/test_socket_client.c socket_client.c
	/tmp/test_socket_client
	$(CC) $(CFLAGS) -o /tmp/test_socket_path tests/test_socket_path.c socket_path.c
	/tmp/test_socket_path

clean:
	rm -f $(MODULE) /tmp/test_socket_client /tmp/test_socket_path
