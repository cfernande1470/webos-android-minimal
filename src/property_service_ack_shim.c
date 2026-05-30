#include <sys/socket.h>
#include <sys/un.h>
#include <sys/stat.h>
#include <sys/poll.h>
#include <signal.h>
#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <errno.h>
#include <limits.h>

#define PROP_NAME_MAX 32
#define PROP_VALUE_MAX 92

#define PROP_MSG_SETPROP 1
#define PROP_MSG_SETPROP2 0x00020001

#define PROP_SUCCESS 0
#define PROP_ERROR_READ_CMD 0x0004
#define PROP_ERROR_READ_DATA 0x0008
#define PROP_ERROR_INVALID_NAME 0x0010
#define PROP_ERROR_INVALID_VALUE 0x0014
#define PROP_ERROR_INVALID_CMD 0x001B

struct prop_entry {
    char *name;
    char *value;
};

static struct prop_entry *props;
static size_t prop_count;
static size_t prop_cap;
static const char *state_path;

static void die(const char *m) {
    perror(m);
    exit(1);
}

static void *xrealloc(void *ptr, size_t size) {
    void *out = realloc(ptr, size);
    if (!out) die("realloc");
    return out;
}

static char *xstrdup(const char *s) {
    char *out = strdup(s);
    if (!out) die("strdup");
    return out;
}

static int poll_in(int fd, int timeout_ms) {
    struct pollfd pfd = { .fd = fd, .events = POLLIN };

    for (;;) {
        int r = poll(&pfd, 1, timeout_ms);
        if (r < 0 && errno == EINTR) continue;
        return r;
    }
}

static int read_full(int fd, void *buf, size_t len) {
    char *p = buf;
    size_t done = 0;

    while (done < len) {
        if (poll_in(fd, 2000) <= 0) return -1;

        ssize_t n = read(fd, p + done, len - done);
        if (n < 0 && errno == EINTR) continue;
        if (n <= 0) return -1;
        done += (size_t)n;
    }

    return 0;
}

static int read_u32(int fd, uint32_t *out) {
    return read_full(fd, out, sizeof(*out));
}

static int read_string(int fd, char **out) {
    uint32_t len;
    char *s;

    if (read_u32(fd, &len) < 0) return -1;
    if (len > 0xffff) return -1;

    s = calloc((size_t)len + 1, 1);
    if (!s) die("calloc");

    if (len > 0 && read_full(fd, s, len) < 0) {
        free(s);
        return -1;
    }

    *out = s;
    return 0;
}

static void send_u32(int fd, uint32_t value) {
    ssize_t ignored = write(fd, &value, sizeof(value));
    (void)ignored;
}

static int legal_prop_name(const char *name) {
    size_t len;
    int last_dot = 1;

    if (!name || !*name) return 0;
    len = strlen(name);
    if (name[0] == '.' || name[len - 1] == '.') return 0;

    for (size_t i = 0; i < len; i++) {
        char c = name[i];
        int dot = c == '.';
        int ok = (c >= 'a' && c <= 'z') ||
                 (c >= 'A' && c <= 'Z') ||
                 (c >= '0' && c <= '9') ||
                 c == '_' || c == '-' || c == '@' || c == ':' || dot;
        if (!ok) return 0;
        if (dot && last_dot) return 0;
        last_dot = dot;
    }

    return 1;
}

static uint32_t validate_property(const char *name, const char *value) {
    if (!legal_prop_name(name)) return PROP_ERROR_INVALID_NAME;
    if (strlen(value) >= PROP_VALUE_MAX && strncmp(name, "ro.", 3) != 0) {
        return PROP_ERROR_INVALID_VALUE;
    }
    return PROP_SUCCESS;
}

static int find_prop(const char *name) {
    for (size_t i = 0; i < prop_count; i++) {
        if (strcmp(props[i].name, name) == 0) return (int)i;
    }
    return -1;
}

static void remember_property(const char *name, const char *value) {
    int idx = find_prop(name);

    if (idx >= 0) {
        free(props[idx].value);
        props[idx].value = xstrdup(value);
        return;
    }

    if (prop_count == prop_cap) {
        prop_cap = prop_cap ? prop_cap * 2 : 64;
        props = xrealloc(props, prop_cap * sizeof(*props));
    }

    props[prop_count].name = xstrdup(name);
    props[prop_count].value = xstrdup(value);
    prop_count++;
}

static void load_state(void) {
    FILE *f;
    char line[8192];

    if (!state_path) return;
    f = fopen(state_path, "r");
    if (!f) return;

    while (fgets(line, sizeof(line), f)) {
        char *eq;
        char *nl = strchr(line, '\n');
        if (nl) *nl = '\0';
        if (line[0] == '#' || line[0] == '\0') continue;
        eq = strchr(line, '=');
        if (!eq) continue;
        *eq++ = '\0';
        if (legal_prop_name(line)) remember_property(line, eq);
    }

    fclose(f);
}

static void save_state(void) {
    char tmp[PATH_MAX];
    FILE *f;

    if (!state_path) return;
    snprintf(tmp, sizeof(tmp), "%s.tmp", state_path);

    f = fopen(tmp, "w");
    if (!f) return;

    fprintf(f, "# webos-android-minimal property-service snapshot\n");
    for (size_t i = 0; i < prop_count; i++) {
        fprintf(f, "%s=%s\n", props[i].name, props[i].value);
    }

    if (fclose(f) == 0) {
        rename(tmp, state_path);
    } else {
        unlink(tmp);
    }
}

static void handle_legacy_setprop(int fd) {
    char name[PROP_NAME_MAX];
    char value[PROP_VALUE_MAX];
    uint32_t result;

    if (read_full(fd, name, sizeof(name)) < 0 ||
        read_full(fd, value, sizeof(value)) < 0) {
        return;
    }

    name[PROP_NAME_MAX - 1] = '\0';
    value[PROP_VALUE_MAX - 1] = '\0';

    result = validate_property(name, value);
    if (result == PROP_SUCCESS) {
        remember_property(name, value);
        save_state();
        fprintf(stderr, "setprop legacy %s=%s\n", name, value);
    } else {
        fprintf(stderr, "reject legacy setprop %s=%s result=0x%x\n", name, value, result);
    }
}

static void handle_setprop2(int fd) {
    char *name = NULL;
    char *value = NULL;
    uint32_t result;

    if (read_string(fd, &name) < 0 || read_string(fd, &value) < 0) {
        free(name);
        free(value);
        send_u32(fd, PROP_ERROR_READ_DATA);
        return;
    }

    result = validate_property(name, value);
    if (result == PROP_SUCCESS) {
        remember_property(name, value);
        save_state();
        fprintf(stderr, "setprop2 %s=%s\n", name, value);
    } else {
        fprintf(stderr, "reject setprop2 %s=%s result=0x%x\n", name, value, result);
    }

    send_u32(fd, result);
    free(name);
    free(value);
}

static void handle_client(int fd) {
    uint32_t cmd;

    if (read_u32(fd, &cmd) < 0) {
        send_u32(fd, PROP_ERROR_READ_CMD);
        return;
    }

    switch (cmd) {
    case PROP_MSG_SETPROP:
        handle_legacy_setprop(fd);
        break;
    case PROP_MSG_SETPROP2:
        handle_setprop2(fd);
        break;
    default:
        fprintf(stderr, "invalid property command 0x%x\n", cmd);
        send_u32(fd, PROP_ERROR_INVALID_CMD);
        break;
    }
}

int main(int argc, char **argv) {
    const char *path = argc > 1 ? argv[1] : "/dev/socket/property_service";

    state_path = argc > 2 ? argv[2] : "/tmp/webos-android-minimal.properties";
    signal(SIGPIPE, SIG_IGN);
    load_state();

    int fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd < 0) die("socket");

    unlink(path);

    struct sockaddr_un addr;
    memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;

    if (strlen(path) >= sizeof(addr.sun_path)) {
        fprintf(stderr, "socket path too long: %s\n", path);
        return 2;
    }

    strcpy(addr.sun_path, path);

    if (bind(fd, (struct sockaddr *)&addr, sizeof(addr)) < 0) die("bind");
    chmod(path, 0666);

    if (listen(fd, 16) < 0) die("listen");

    fprintf(stderr, "property shim listening on %s state=%s\n", path, state_path);

    for (;;) {
        int c = accept(fd, NULL, NULL);
        if (c < 0) {
            if (errno == EINTR) continue;
            continue;
        }

        handle_client(c);
        close(c);
    }
}
