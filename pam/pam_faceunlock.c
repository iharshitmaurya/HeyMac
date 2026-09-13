#define PAM_SM_AUTH
#include <security/pam_appl.h>
#include <security/pam_modules.h>
#include <pwd.h>
#include <syslog.h>
#include "socket_client.h"
#include "socket_path.h"
#include "socket_owner.h"

/* Daemon answers almost instantly (no polling) and bounds each connection to
 * 5s internally, so 10s leaves generous slack for connection setup without
 * making a wedged daemon block sudo for anywhere near as long as before. */
#define VERIFY_TIMEOUT_MS 10000

PAM_EXTERN int
pam_sm_authenticate(pam_handle_t *pamh, int flags, int argc, const char **argv) {
    (void)flags; (void)argc; (void)argv;

    const char *username = NULL;
    if (pam_get_user(pamh, &username, NULL) != PAM_SUCCESS || username == NULL) {
        syslog(LOG_AUTHPRIV | LOG_DEBUG, "pam_faceunlock: pam_get_user failed");
        return PAM_AUTHINFO_UNAVAIL;
    }

    struct passwd *pw = getpwnam(username);
    if (pw == NULL || pw->pw_dir == NULL) {
        syslog(LOG_AUTHPRIV | LOG_DEBUG, "pam_faceunlock: getpwnam failed");
        return PAM_AUTHINFO_UNAVAIL;
    }

    char socket_path[1024];
    if (build_socket_path(pw->pw_dir, socket_path, sizeof(socket_path)) != 0) {
        syslog(LOG_AUTHPRIV | LOG_DEBUG, "pam_faceunlock: build_socket_path failed");
        return PAM_AUTHINFO_UNAVAIL;
    }

    if (!verify_socket_ownership(socket_path, pw->pw_uid)) {
        syslog(LOG_AUTHPRIV | LOG_DEBUG, "pam_faceunlock: socket ownership check failed");
        return PAM_AUTHINFO_UNAVAIL;
    }

    if (send_and_wait(socket_path, "VERIFY\n", VERIFY_TIMEOUT_MS)) {
        return PAM_SUCCESS;
    }
    syslog(LOG_AUTHPRIV | LOG_DEBUG, "pam_faceunlock: daemon did not confirm match");
    return PAM_AUTHINFO_UNAVAIL;
}

PAM_EXTERN int
pam_sm_setcred(pam_handle_t *pamh, int flags, int argc, const char **argv) {
    (void)pamh; (void)flags; (void)argc; (void)argv;
    return PAM_SUCCESS;
}
