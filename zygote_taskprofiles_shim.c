/*
 * LD_PRELOAD shim for libprocessgroup task profiles.
 * libandroid_runtime imports plain C symbols:
 *   SetTaskProfiles
 *   DropTaskProfilesResourceCaching
 *
 * Keep this dependency-free.
 */

__attribute__((visibility("default")))
int SetTaskProfiles(int tid, const void *profiles, int use_fd_cache) {
    (void)tid;
    (void)profiles;
    (void)use_fd_cache;
    return 1;
}

__attribute__((visibility("default")))
void DropTaskProfilesResourceCaching(void) {
}
