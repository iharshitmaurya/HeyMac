#define PAM_SM_AUTH
#include <security/pam_appl.h>
#include <security/pam_modules.h>
#include <pwd.h>
#include "socket_client.h"
#include "socket_path.h"

PAM_EXTERN int
pam_sm_authenticate(pam_handle_t *pamh, int flags, int argc, const char **argv) {
    (void)flags; (void)argc; (void)argv;

    const char *username = NULL;
    if (pam_get_user(pamh, &username, NULL) != PAM_SUCCESS || username == NULL) {
        return PAM_AUTHINFO_UNAVAIL;
    }

    struct passwd *pw = getpwnam(username);
    if (pw == NULL || pw->pw_dir == NULL) {
        return PAM_AUTHINFO_UNAVAIL;
    }

    char socket_path[1024];
    if (build_socket_path(pw->pw_dir, socket_path, sizeof(socket_path)) != 0) {
        return PAM_AUTHINFO_UNAVAIL;
    }

    if (send_and_wait(socket_path, "VERIFY\n", 120000)) {
        return PAM_SUCCESS;
    }
    return PAM_AUTHINFO_UNAVAIL;
}

PAM_EXTERN int
pam_sm_setcred(pam_handle_t *pamh, int flags, int argc, const char **argv) {
    (void)pamh; (void)flags; (void)argc; (void)argv;
    return PAM_SUCCESS;
}
