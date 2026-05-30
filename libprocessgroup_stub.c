/*
 * Diagnostic libprocessgroup.so stub for zygote minimal boot.
 * No libc dependency. Creates marker files via raw aarch64 syscalls.
 */

#define AT_FDCWD (-100)
#define O_WRONLY 1
#define O_CREAT  64
#define O_APPEND 1024

static long raw_syscall3(long n, long a, long b, long c) {
    register long x0 __asm__("x0") = a;
    register long x1 __asm__("x1") = b;
    register long x2 __asm__("x2") = c;
    register long x8 __asm__("x8") = n;
    __asm__ volatile("svc #0" : "+r"(x0) : "r"(x1), "r"(x2), "r"(x8) : "memory");
    return x0;
}

static long raw_syscall4(long n, long a, long b, long c, long d) {
    register long x0 __asm__("x0") = a;
    register long x1 __asm__("x1") = b;
    register long x2 __asm__("x2") = c;
    register long x3 __asm__("x3") = d;
    register long x8 __asm__("x8") = n;
    __asm__ volatile("svc #0" : "+r"(x0) : "r"(x1), "r"(x2), "r"(x3), "r"(x8) : "memory");
    return x0;
}

static unsigned long slen(const char *s) {
    unsigned long n = 0;
    while (s && s[n]) n++;
    return n;
}

static void mark(const char *msg) {
    const char *path = "/data/local/tmp/libprocessgroup_stub.called";
    long fd = raw_syscall4(56, AT_FDCWD, (long)path, O_WRONLY | O_CREAT | O_APPEND, 0666);
    if (fd >= 0) {
        raw_syscall3(64, fd, (long)msg, slen(msg));
        raw_syscall3(57, fd, 0, 0);
    }
}

__attribute__((visibility("default")))
int SetTaskProfiles(int tid, const void *profiles, int use_fd_cache) {
    (void)tid; (void)profiles; (void)use_fd_cache;
    mark("SetTaskProfiles called -> return 1\n");
    return 1;
}

__attribute__((visibility("default")))
int SetTaskProfilesCached(int tid, const void *profiles) {
    (void)tid; (void)profiles;
    mark("SetTaskProfilesCached called -> return 1\n");
    return 1;
}

__attribute__((visibility("default")))
int SetProcessProfiles(unsigned int uid, int pid, const void *profiles, int use_fd_cache) {
    (void)uid; (void)pid; (void)profiles; (void)use_fd_cache;
    mark("SetProcessProfiles called -> return 1\n");
    return 1;
}

__attribute__((visibility("default")))
int SetProcessProfilesCached(unsigned int uid, int pid, const void *profiles) {
    (void)uid; (void)pid; (void)profiles;
    mark("SetProcessProfilesCached called -> return 1\n");
    return 1;
}

__attribute__((visibility("default")))
void DropTaskProfilesResourceCaching(void) {
    mark("DropTaskProfilesResourceCaching called\n");
}

__attribute__((visibility("default")))
int createProcessGroup(unsigned int uid, int initialPid, int memControl) {
    (void)uid; (void)initialPid; (void)memControl;
    mark("createProcessGroup called -> return 0\n");
    return 0;
}

__attribute__((visibility("default")))
int removeProcessGroup(unsigned int uid, int pid) {
    (void)uid; (void)pid;
    return 0;
}

__attribute__((visibility("default")))
int killProcessGroup(unsigned int uid, int pid, int signal) {
    (void)uid; (void)pid; (void)signal;
    return 0;
}

__attribute__((visibility("default")))
int killProcessGroupOnce(unsigned int uid, int pid, int signal) {
    (void)uid; (void)pid; (void)signal;
    return 0;
}

__attribute__((visibility("default")))
int sendSignalToProcessGroup(unsigned int uid, int pid, int signal) {
    (void)uid; (void)pid; (void)signal;
    return 0;
}

__attribute__((visibility("default")))
int setProcessGroupSwappiness(unsigned int uid, int pid, int swappiness) {
    (void)uid; (void)pid; (void)swappiness;
    return 0;
}

__attribute__((visibility("default")))
int setProcessGroupSoftLimit(unsigned int uid, int pid, long long limit) {
    (void)uid; (void)pid; (void)limit;
    return 0;
}

__attribute__((visibility("default")))
int setProcessGroupLimit(unsigned int uid, int pid, long long limit) {
    (void)uid; (void)pid; (void)limit;
    return 0;
}

__attribute__((visibility("default")))
void removeAllProcessGroups(void) {
    mark("removeAllProcessGroups called\n");
}

__attribute__((visibility("default")))
int UsePerAppMemcg(void) {
    return 0;
}

__attribute__((visibility("default")))
const char *get_sched_policy_profile_name(int policy) {
    (void)policy;
    return "ProcessCapacityNormal";
}

__attribute__((visibility("default")))
const char *get_cpuset_policy_profile_name(int policy) {
    (void)policy;
    return "CPUSET_SP_DEFAULT";
}

__attribute__((visibility("default")))
const char *get_sched_policy_name(int policy) {
    (void)policy;
    return "SP_DEFAULT";
}

__attribute__((visibility("default")))
const char *get_cpuset_policy_name(int policy) {
    (void)policy;
    return "SP_DEFAULT";
}

__attribute__((visibility("default")))
int set_sched_policy(int tid, int policy) {
    (void)tid; (void)policy;
    return 0;
}

__attribute__((visibility("default")))
int get_sched_policy(int tid, int *policy) {
    (void)tid;
    if (policy) *policy = 0;
    return 0;
}

__attribute__((visibility("default")))
int set_cpuset_policy(int tid, int policy) {
    (void)tid; (void)policy;
    return 0;
}

__attribute__((visibility("default")))
int get_cpuset_policy(int tid, int *policy) {
    (void)tid;
    if (policy) *policy = 0;
    return 0;
}

__attribute__((visibility("default")))
int get_sched_policy_from_name(const char *name, int *policy) {
    (void)name;
    if (policy) *policy = 0;
    return 0;
}

__attribute__((visibility("default")))
int cpusets_enabled(void) {
    return 0;
}

__attribute__((visibility("default")))
int schedboost_enabled(void) {
    return 0;
}

__attribute__((visibility("default")))
int CgroupGetAttributePath(const char *attr_name, char *path, unsigned int path_len) {
    (void)attr_name;
    if (path && path_len > 0) path[0] = '\0';
    return 0;
}

__attribute__((visibility("default")))
int CgroupGetAttributePathForTask(const char *attr_name, int tid, char *path, unsigned int path_len) {
    (void)attr_name; (void)tid;
    if (path && path_len > 0) path[0] = '\0';
    return 0;
}

__attribute__((visibility("default")))
int CgroupGetControllerPath(const char *controller_name, char *path, unsigned int path_len) {
    (void)controller_name;
    if (path && path_len > 0) path[0] = '\0';
    return 0;
}

__attribute__((visibility("default")))
int CgroupGetControllerFromPath(const char *path) {
    (void)path;
    return -1;
}

__attribute__((visibility("default")))
int CgroupGetControllerCount(void) {
    return 0;
}
