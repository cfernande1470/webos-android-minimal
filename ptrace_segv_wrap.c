#define _GNU_SOURCE
#include <sys/ptrace.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <sys/uio.h>
#include <sys/stat.h>
#include <sys/syscall.h>
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

static void dump_file(const char *path, int max_lines) {
    FILE *f = fopen(path, "r");
    if (!f) {
        fprintf(stderr, "cannot open %s: %s\n", path, strerror(errno));
        return;
    }

    char line[1024];
    int n = 0;
    while (fgets(line, sizeof(line), f)) {
        fputs(line, stdout);
        if (++n >= max_lines) break;
    }
    fclose(f);
}

static void dump_maps(pid_t pid) {
    char path[128];
    snprintf(path, sizeof(path), "/proc/%d/maps", pid);

    printf("\n--- child maps ---\n");
    dump_file(path, 10000);
}

static void dump_status(pid_t pid) {
    char path[128];
    snprintf(path, sizeof(path), "/proc/%d/status", pid);

    printf("\n--- child status ---\n");
    dump_file(path, 120);
}

static void dump_regs(pid_t pid) {
    struct user_pt_regs regs;
    struct iovec iov;

    memset(&regs, 0, sizeof(regs));
    iov.iov_base = &regs;
    iov.iov_len = sizeof(regs);

    if (ptrace(PTRACE_GETREGSET, pid, (void *)NT_PRSTATUS, &iov) != 0) {
        fprintf(stderr, "PTRACE_GETREGSET failed: %s\n", strerror(errno));
        return;
    }

    printf("\n--- AArch64 regs ---\n");
    printf("pc = 0x%llx\n", (unsigned long long)regs.pc);
    printf("sp = 0x%llx\n", (unsigned long long)regs.sp);
    printf("pstate = 0x%llx\n", (unsigned long long)regs.pstate);
    printf("lr/x30 = 0x%llx\n", (unsigned long long)regs.regs[30]);

    for (int i = 0; i < 31; i++) {
        printf("x%-2d = 0x%016llx\n", i, (unsigned long long)regs.regs[i]);
    }
}

static void show_addr_owner(pid_t pid, unsigned long long addr, const char *name) {
    char path[128];
    snprintf(path, sizeof(path), "/proc/%d/maps", pid);

    FILE *f = fopen(path, "r");
    if (!f) return;

    char line[2048];
    while (fgets(line, sizeof(line), f)) {
        unsigned long long start = 0, end = 0;
        if (sscanf(line, "%llx-%llx", &start, &end) == 2) {
            if (addr >= start && addr < end) {
                printf("\n--- %s owner ---\n", name);
                printf("%s=0x%llx offset=0x%llx in mapping:\n%s",
                       name, addr, addr - start, line);
                fclose(f);
                return;
            }
        }
    }

    printf("\n--- %s owner ---\n%s=0x%llx not found in maps\n", name, name, addr);
    fclose(f);
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
        if (ptrace(PTRACE_TRACEME, 0, NULL, NULL) != 0) {
            perror("PTRACE_TRACEME");
            _exit(127);
        }

        raise(SIGSTOP);
        execvp(argv[1], &argv[1]);
        perror("execvp");
        _exit(127);
    }

    int status = 0;
    if (waitpid(child, &status, 0) < 0) {
        perror("waitpid initial");
        return 2;
    }

    ptrace(PTRACE_SETOPTIONS, child, 0,
           PTRACE_O_TRACEEXEC | PTRACE_O_TRACECLONE | PTRACE_O_TRACEFORK | PTRACE_O_TRACEVFORK);

    printf("--- tracing pid %d ---\n", child);
    ptrace(PTRACE_CONT, child, 0, 0);

    while (1) {
        pid_t pid = waitpid(-1, &status, __WALL);
        if (pid < 0) {
            if (errno == ECHILD) break;
            perror("waitpid");
            break;
        }

        if (WIFEXITED(status)) {
            printf("--- pid %d exited rc=%d ---\n", pid, WEXITSTATUS(status));
            continue;
        }

        if (WIFSIGNALED(status)) {
            printf("--- pid %d signaled sig=%d ---\n", pid, WTERMSIG(status));
            continue;
        }

        if (!WIFSTOPPED(status)) {
            continue;
        }

        int sig = WSTOPSIG(status);
        unsigned int event = (unsigned int)status >> 16;

        if (event == PTRACE_EVENT_EXEC) {
            printf("--- pid %d exec ---\n", pid);
            ptrace(PTRACE_CONT, pid, 0, 0);
            continue;
        }

        if (event == PTRACE_EVENT_CLONE || event == PTRACE_EVENT_FORK || event == PTRACE_EVENT_VFORK) {
            unsigned long newpid = 0;
            ptrace(PTRACE_GETEVENTMSG, pid, 0, &newpid);
            printf("--- pid %d spawned %lu ---\n", pid, newpid);
            ptrace(PTRACE_CONT, pid, 0, 0);
            continue;
        }

        if (sig == SIGSEGV || sig == SIGABRT || sig == SIGILL || sig == SIGBUS) {
            printf("\n=== CRASH STOP pid=%d sig=%d ===\n", pid, sig);
            dump_status(pid);
            dump_regs(pid);

            struct user_pt_regs regs;
            struct iovec iov;
            memset(&regs, 0, sizeof(regs));
            iov.iov_base = &regs;
            iov.iov_len = sizeof(regs);

            if (ptrace(PTRACE_GETREGSET, pid, (void *)NT_PRSTATUS, &iov) == 0) {
                show_addr_owner(pid, regs.pc, "pc");
                show_addr_owner(pid, regs.regs[30], "lr");
            }

            dump_maps(pid);

            printf("\n=== END CRASH STOP ===\n");

            /* Let Android's own handler run too, if any. */
            ptrace(PTRACE_CONT, pid, 0, sig);
            continue;
        }

        ptrace(PTRACE_CONT, pid, 0, sig);
    }

    return 0;
}
