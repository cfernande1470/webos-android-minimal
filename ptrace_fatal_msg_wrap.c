#define _GNU_SOURCE
#include <sys/ptrace.h>
#include <sys/wait.h>
#include <sys/uio.h>
#include <sys/types.h>
#include <asm/ptrace.h>
#include <elf.h>
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

struct bp {
    const char *name;
    const char *soname;
    unsigned long file_off;
    unsigned long addr;
    unsigned long orig_word;
    int armed;
};

static struct bp bps[] = {
    { "ZygoteFailure@plt", "libandroid_runtime.so", 0x1fadd0, 0, 0, 0 },
    { "JNI::FatalError",   "libart.so",             0x4be390, 0, 0, 0 },
};

static int all_armed(void) {
    for (unsigned i = 0; i < sizeof(bps)/sizeof(bps[0]); i++) {
        if (!bps[i].armed) return 0;
    }
    return 1;
}

static int get_regs(pid_t pid, struct user_pt_regs *regs) {
    struct iovec io = { regs, sizeof(*regs) };
    return ptrace(PTRACE_GETREGSET, pid, (void*)NT_PRSTATUS, &io);
}

static int read_mem(pid_t pid, unsigned long addr, void *buf, size_t len) {
    size_t done = 0;
    while (done < len) {
        errno = 0;
        unsigned long w = ptrace(PTRACE_PEEKDATA, pid, (void*)(addr + done), 0);
        if (errno) return -1;
        size_t n = sizeof(w);
        if (done + n > len) n = len - done;
        memcpy((char*)buf + done, &w, n);
        done += n;
    }
    return 0;
}

static void dump_cstr(pid_t pid, const char *label, unsigned long addr) {
    char buf[513];
    memset(buf, 0, sizeof(buf));

    if (!addr || read_mem(pid, addr, buf, sizeof(buf) - 1) != 0) {
        printf("%s: <unreadable 0x%lx>\n", label, addr);
        return;
    }

    for (int i = 0; i < (int)sizeof(buf) - 1; i++) {
        unsigned char c = buf[i];
        if (c == 0) break;
        if (c < 32 || c > 126) buf[i] = '.';
    }

    printf("%s @0x%lx: %s\n", label, addr, buf);
}

static void dump_std_string_guess(pid_t pid, const char *label, unsigned long addr) {
    unsigned char obj[64];
    unsigned long words[8];

    printf("%s object @0x%lx\n", label, addr);

    if (!addr || read_mem(pid, addr, obj, sizeof(obj)) != 0) {
        printf("  <unreadable>\n");
        return;
    }

    printf("  raw:");
    for (int i = 0; i < 64; i++) printf(" %02x", obj[i]);
    printf("\n");

    printf("  inline-printable: ");
    for (int i = 0; i < 64; i++) {
        unsigned char c = obj[i];
        putchar((c >= 32 && c <= 126) ? c : '.');
    }
    printf("\n");

    memcpy(words, obj, sizeof(words));

    for (int i = 0; i < 8; i++) {
        if (words[i] > 0x10000UL) {
            char tmp[257];
            memset(tmp, 0, sizeof(tmp));

            if (read_mem(pid, words[i], tmp, sizeof(tmp) - 1) == 0) {
                int printable = 0;
                for (int j = 0; j < 160 && tmp[j]; j++) {
                    if (tmp[j] >= 32 && tmp[j] <= 126) printable++;
                }

                if (printable >= 6) {
                    for (int j = 0; j < (int)sizeof(tmp) - 1; j++) {
                        unsigned char c = tmp[j];
                        if (c == 0) break;
                        if (c < 32 || c > 126) tmp[j] = '.';
                    }
                    printf("  ptr[%d] @0x%lx: %s\n", i, words[i], tmp);
                }
            }
        }
    }
}

static int find_map_addr(pid_t pid, const char *soname, unsigned long file_off, unsigned long *addr_out) {
    char path[64], line[1024];

    snprintf(path, sizeof(path), "/proc/%d/maps", pid);
    FILE *f = fopen(path, "r");
    if (!f) return 0;

    while (fgets(line, sizeof(line), f)) {
        unsigned long start, end, off;
        char perms[8] = "";
        char mapname[768] = "";

        int n = sscanf(line, "%lx-%lx %7s %lx %*s %*s %767s",
                       &start, &end, perms, &off, mapname);

        if (n >= 4 && strchr(perms, 'x') && strstr(mapname, soname)) {
            unsigned long size = end - start;
            if (file_off >= off && file_off < off + size) {
                *addr_out = start + (file_off - off);
                fclose(f);
                return 1;
            }
        }
    }

    fclose(f);
    return 0;
}

static void try_arm(pid_t pid) {
    for (unsigned i = 0; i < sizeof(bps)/sizeof(bps[0]); i++) {
        struct bp *b = &bps[i];
        if (b->armed) continue;

        unsigned long addr = 0;
        if (!find_map_addr(pid, b->soname, b->file_off, &addr)) continue;

        errno = 0;
        unsigned long orig = ptrace(PTRACE_PEEKTEXT, pid, (void*)addr, 0);
        if (errno) continue;

        unsigned long patched = (orig & ~0xffffffffUL) | 0xd4200000UL; /* brk #0 */

        if (ptrace(PTRACE_POKETEXT, pid, (void*)addr, (void*)patched) != 0) {
            continue;
        }

        b->addr = addr;
        b->orig_word = orig;
        b->armed = 1;

        printf("ARMED %s %s file_off=0x%lx addr=0x%lx orig=0x%lx\n",
               b->name, b->soname, b->file_off, b->addr, b->orig_word);
        fflush(stdout);
    }
}

static struct bp *hit_bp(unsigned long pc) {
    for (unsigned i = 0; i < sizeof(bps)/sizeof(bps[0]); i++) {
        if (!bps[i].armed) continue;
        if (pc == bps[i].addr || pc == bps[i].addr + 4) return &bps[i];
    }
    return NULL;
}

static void set_opts(pid_t pid) {
    ptrace(PTRACE_SETOPTIONS, pid, 0,
           PTRACE_O_TRACEEXEC |
           PTRACE_O_TRACECLONE |
           PTRACE_O_TRACEFORK |
           PTRACE_O_TRACEVFORK |
           PTRACE_O_TRACESYSGOOD);
}

static void resume_pid(pid_t pid, int sig) {
    if (all_armed()) {
        ptrace(PTRACE_CONT, pid, 0, sig);
    } else {
        ptrace(PTRACE_SYSCALL, pid, 0, sig);
    }
}

int main(int argc, char **argv) {
    if (argc < 2) {
        fprintf(stderr, "usage: %s command [args...]\n", argv[0]);
        return 2;
    }

    pid_t child = fork();

    if (child == 0) {
        ptrace(PTRACE_TRACEME, 0, 0, 0);
        raise(SIGSTOP);
        execvp(argv[1], &argv[1]);
        perror("execvp");
        _exit(127);
    }

    int st;
    waitpid(child, &st, 0);
    set_opts(child);
    resume_pid(child, 0);

    while (1) {
        pid_t pid = waitpid(-1, &st, __WALL);

        if (pid < 0) {
            if (errno == EINTR) continue;
            perror("waitpid");
            break;
        }

        if (WIFEXITED(st) || WIFSIGNALED(st)) {
            if (pid == child) break;
            continue;
        }

        if (!WIFSTOPPED(st)) {
            resume_pid(pid, 0);
            continue;
        }

        int sig = WSTOPSIG(st);
        int event = st >> 16;

        if (event) {
            unsigned long newpid = 0;
            ptrace(PTRACE_GETEVENTMSG, pid, 0, &newpid);
            if (newpid > 0) set_opts((pid_t)newpid);
        }

        try_arm(pid);

        struct user_pt_regs regs;
        memset(&regs, 0, sizeof(regs));

        if (get_regs(pid, &regs) == 0) {
            struct bp *b = hit_bp((unsigned long)regs.pc);

            if (b) {
                printf("\n=== HIT %s pid=%d pc=0x%llx addr=0x%lx ===\n",
                       b->name, pid, (unsigned long long)regs.pc, b->addr);

                printf("x0=0x%llx x1=0x%llx x2=0x%llx x3=0x%llx\n",
                       (unsigned long long)regs.regs[0],
                       (unsigned long long)regs.regs[1],
                       (unsigned long long)regs.regs[2],
                       (unsigned long long)regs.regs[3]);

                if (strcmp(b->name, "JNI::FatalError") == 0) {
                    dump_cstr(pid, "FatalError msg x1", regs.regs[1]);
                } else {
                    dump_cstr(pid, "ZygoteFailure process x1", regs.regs[1]);
                    dump_std_string_guess(pid, "ZygoteFailure message x3", regs.regs[3]);
                }

                printf("=== END HIT ===\n");
                fflush(stdout);
                return 0;
            }
        }

        if (sig == SIGTRAP || sig == (SIGTRAP | 0x80)) {
            resume_pid(pid, 0);
        } else {
            resume_pid(pid, sig);
        }
    }

    return 1;
}
