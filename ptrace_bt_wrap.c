#define _GNU_SOURCE
#include <sys/ptrace.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <sys/uio.h>
#include <linux/elf.h>
#include <asm/ptrace.h>
#include <signal.h>
#include <unistd.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifndef NT_PRSTATUS
#define NT_PRSTATUS 1
#endif

struct mapent {
    unsigned long long start, end, off;
    char perms[8];
    char path[512];
};

static int read_maps(pid_t pid, struct mapent *maps, int max) {
    char fn[64], line[1024];
    snprintf(fn, sizeof(fn), "/proc/%d/maps", pid);
    FILE *f = fopen(fn, "r");
    if (!f) return 0;

    int n = 0;
    while (n < max && fgets(line, sizeof(line), f)) {
        struct mapent *m = &maps[n];
        char dev[32], path[512] = "";
        unsigned long inode = 0;
        int got = sscanf(line, "%llx-%llx %7s %llx %31s %lu %511[^\n]",
                         &m->start, &m->end, m->perms, &m->off, dev, &inode, path);
        if (got >= 6) {
            if (got == 7) {
                while (path[0] == ' ') memmove(path, path + 1, strlen(path));
                strncpy(m->path, path, sizeof(m->path)-1);
            } else {
                m->path[0] = 0;
            }
            n++;
        }
    }
    fclose(f);
    return n;
}

static const struct mapent *find_map(struct mapent *maps, int n, unsigned long long addr) {
    for (int i = 0; i < n; i++) {
        if (addr >= maps[i].start && addr < maps[i].end) return &maps[i];
    }
    return NULL;
}

static void print_owner(const char *label, struct mapent *maps, int n, unsigned long long addr) {
    const struct mapent *m = find_map(maps, n, addr);
    if (!m) {
        printf("%s=0x%llx owner=<none>\n", label, addr);
        return;
    }

    unsigned long long file_off = m->off + (addr - m->start);
    printf("%s=0x%llx map_off=0x%llx file_off=0x%llx %s %s\n",
           label, addr, addr - m->start, file_off, m->perms, m->path);
}

static int get_regs(pid_t pid, struct user_pt_regs *regs) {
    struct iovec iov;
    memset(regs, 0, sizeof(*regs));
    iov.iov_base = regs;
    iov.iov_len = sizeof(*regs);
    return ptrace(PTRACE_GETREGSET, pid, (void *)NT_PRSTATUS, &iov);
}

static unsigned long long peek64(pid_t pid, unsigned long long addr, int *ok) {
    errno = 0;
    unsigned long long v = ptrace(PTRACE_PEEKDATA, pid, (void *)addr, 0);
    if (errno) {
        *ok = 0;
        return 0;
    }
    *ok = 1;
    return v;
}

static void dump_crash(pid_t pid, int sig) {
    struct user_pt_regs r;
    struct mapent maps[4096];
    int n = read_maps(pid, maps, 4096);

    printf("\n=== CRASH pid=%d sig=%d ===\n", pid, sig);

    if (get_regs(pid, &r) != 0) {
        printf("GETREGSET failed: %s\n", strerror(errno));
        return;
    }

    printf("pc=0x%llx sp=0x%llx fp/x29=0x%llx lr/x30=0x%llx pstate=0x%llx\n",
           (unsigned long long)r.pc,
           (unsigned long long)r.sp,
           (unsigned long long)r.regs[29],
           (unsigned long long)r.regs[30],
           (unsigned long long)r.pstate);

    for (int i = 0; i < 31; i++) {
        printf("x%-2d=0x%016llx\n", i, (unsigned long long)r.regs[i]);
    }

    printf("\n--- owners ---\n");
    print_owner("pc", maps, n, r.pc);
    print_owner("lr", maps, n, r.regs[30]);

    printf("\n--- frame chain x29 ---\n");
    unsigned long long fp = r.regs[29];
    for (int depth = 0; depth < 64; depth++) {
        if (fp == 0) break;

        int ok1 = 0, ok2 = 0;
        unsigned long long next_fp = peek64(pid, fp, &ok1);
        unsigned long long ret = peek64(pid, fp + 8, &ok2);

        if (!ok1 || !ok2) {
            printf("#%-2d fp=0x%llx unreadable\n", depth, fp);
            break;
        }

        printf("#%-2d fp=0x%llx ret=0x%llx ", depth, fp, ret);
        print_owner("ret", maps, n, ret);

        if (next_fp <= fp || next_fp - fp > 0x100000) {
            printf("stop: next_fp=0x%llx\n", next_fp);
            break;
        }

        fp = next_fp;
    }

    printf("\n--- executable maps of interest ---\n");
    for (int i = 0; i < n; i++) {
        if (strchr(maps[i].perms, 'x') &&
            (strstr(maps[i].path, "libart") ||
             strstr(maps[i].path, "libopenjdk") ||
             strstr(maps[i].path, "libandroid_runtime") ||
             strstr(maps[i].path, "libc.so") ||
             strstr(maps[i].path, "linker64") ||
             strstr(maps[i].path, "app_process64"))) {
            printf("0x%llx-0x%llx off=0x%llx %s %s\n",
                   maps[i].start, maps[i].end, maps[i].off, maps[i].perms, maps[i].path);
        }
    }

    printf("=== END CRASH ===\n");
}

int main(int argc, char **argv) {
    if (argc < 2) {
        fprintf(stderr, "usage: %s COMMAND [ARGS...]\n", argv[0]);
        return 2;
    }

    pid_t child = fork();
    if (child < 0) {
        perror("fork");
        return 2;
    }

    if (child == 0) {
        ptrace(PTRACE_TRACEME, 0, 0, 0);
        raise(SIGSTOP);
        execvp(argv[1], &argv[1]);
        perror("execvp");
        _exit(127);
    }

    int st;
    waitpid(child, &st, 0);

    ptrace(PTRACE_SETOPTIONS, child, 0,
           PTRACE_O_TRACEEXEC | PTRACE_O_TRACECLONE | PTRACE_O_TRACEFORK | PTRACE_O_TRACEVFORK);

    ptrace(PTRACE_CONT, child, 0, 0);

    while (1) {
        pid_t pid = waitpid(-1, &st, __WALL);
        if (pid < 0) {
            if (errno == ECHILD) break;
            perror("waitpid");
            break;
        }

        if (WIFEXITED(st)) {
            printf("pid %d exited rc=%d\n", pid, WEXITSTATUS(st));
            continue;
        }

        if (WIFSIGNALED(st)) {
            printf("pid %d signaled sig=%d\n", pid, WTERMSIG(st));
            continue;
        }

        if (!WIFSTOPPED(st)) continue;

        int sig = WSTOPSIG(st);
        unsigned event = (unsigned)st >> 16;

        if (event) {
            unsigned long newpid = 0;
            ptrace(PTRACE_GETEVENTMSG, pid, 0, &newpid);
            printf("ptrace event=%u pid=%d newpid=%lu\n", event, pid, newpid);
            ptrace(PTRACE_CONT, pid, 0, 0);
            continue;
        }

        if (sig == SIGSEGV || sig == SIGABRT || sig == SIGILL || sig == SIGBUS) {
            dump_crash(pid, sig);
            ptrace(PTRACE_CONT, pid, 0, sig);
            continue;
        }

        ptrace(PTRACE_CONT, pid, 0, sig);
    }

    return 0;
}
