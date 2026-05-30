#include <sys/socket.h>
#include <sys/un.h>
#include <sys/stat.h>
#include <sys/mman.h>
#include <sys/poll.h>
#include <fcntl.h>
#include <signal.h>
#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <errno.h>
#include <limits.h>
#include <stdatomic.h>

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

static const char *prop_area_path;

#define PROP_AREA_MAGIC 0x504f5250
#define PROP_AREA_VERSION 0xfc6ed0ab
#define PROP_AREA_SIZE (128 * 1024)
#define PROP_ALIGN4(v) (((v) + 3u) & ~3u)

struct prop_bt {
    uint8_t namelen;
    uint8_t reserved[3];
    uint32_t prop;
    uint32_t left;
    uint32_t right;
    uint32_t children;
    char name[];
};

struct prop_info_area {
    uint32_t serial;
    union {
        char value[PROP_VALUE_MAX];
        struct {
            char error_message[56];
            uint32_t offset;
        } long_property;
    };
    char name[];
};

struct prop_area {
    uint32_t bytes_used;
    uint32_t serial;
    uint32_t magic;
    uint32_t version;
    uint32_t reserved[28];
    char data[];
};

static struct prop_area *mapped_prop_area;
static size_t mapped_prop_area_size;

static inline uint32_t load_u32(const uint32_t *p) {
    return __atomic_load_n(p, __ATOMIC_RELAXED);
}

static inline void store_u32(uint32_t *p, uint32_t v) {
    __atomic_store_n(p, v, __ATOMIC_RELEASE);
}

static void die(const char *m) {
    perror(m);
    exit(1);
}

static int streqn(const char *a, uint32_t alen, const char *b, uint32_t blen) {
    int ret = strncmp(a, b, alen < blen ? alen : blen);
    if (ret != 0) return ret;
    if (alen < blen) return -1;
    if (alen > blen) return 1;
    return 0;
}

static struct prop_bt *to_prop_bt(uint32_t off) {
    if (!mapped_prop_area || off == 0) return off == 0 ? (struct prop_bt *)(mapped_prop_area->data) : NULL;
    if (off >= mapped_prop_area_size - sizeof(*mapped_prop_area)) return NULL;
    return (struct prop_bt *)(mapped_prop_area->data + off);
}

static struct prop_bt *root_node(void) {
    return to_prop_bt(0);
}

static struct prop_bt *new_prop_bt(const char *name, uint32_t namelen, uint32_t *off) {
    size_t size = PROP_ALIGN4(sizeof(struct prop_bt) + namelen + 1);
    if (mapped_prop_area->bytes_used + size > mapped_prop_area_size - sizeof(*mapped_prop_area)) {
        return NULL;
    }

    *off = mapped_prop_area->bytes_used;
    mapped_prop_area->bytes_used += (uint32_t)size;

    struct prop_bt *bt = (struct prop_bt *)(mapped_prop_area->data + *off);
    memset(bt, 0, size);
    bt->namelen = (uint8_t)namelen;
    memcpy(bt->name, name, namelen);
    bt->name[namelen] = '\0';
    return bt;
}

static struct prop_info_area *new_prop_info(const char *name, uint32_t namelen, const char *value, uint32_t valuelen, uint32_t *off) {
    if (valuelen >= PROP_VALUE_MAX) return NULL;

    size_t size = PROP_ALIGN4(sizeof(struct prop_info_area) + namelen + 1);
    if (mapped_prop_area->bytes_used + size > mapped_prop_area_size - sizeof(*mapped_prop_area)) {
        return NULL;
    }

    *off = mapped_prop_area->bytes_used;
    mapped_prop_area->bytes_used += (uint32_t)size;

    struct prop_info_area *pi = (struct prop_info_area *)(mapped_prop_area->data + *off);
    memset(pi, 0, size);
    memcpy(pi->name, name, namelen);
    pi->name[namelen] = '\0';
    pi->serial = valuelen << 24;
    memcpy(pi->value, value, valuelen);
    pi->value[valuelen] = '\0';
    return pi;
}

static struct prop_bt *find_prop_bt(struct prop_bt *bt, const char *name, uint32_t namelen, int alloc_if_needed) {
    struct prop_bt *current = bt;
    while (current) {
        int ret = streqn(name, namelen, current->name, current->namelen);
        if (ret == 0) return current;

        uint32_t *link = ret < 0 ? &current->left : &current->right;
        uint32_t next = load_u32(link);
        if (next != 0) {
            current = (struct prop_bt *)(mapped_prop_area->data + next);
            continue;
        }
        if (!alloc_if_needed) return NULL;

        uint32_t new_off;
        struct prop_bt *new_bt = new_prop_bt(name, namelen, &new_off);
        if (!new_bt) return NULL;
        store_u32(link, new_off);
        return new_bt;
    }
    return NULL;
}

static struct prop_info_area *find_property(const char *name, uint32_t namelen, const char *value, uint32_t valuelen, int alloc_if_needed) {
    if (!mapped_prop_area) return NULL;

    const char *remaining_name = name;
    struct prop_bt *current = root_node();
    while (1) {
        const char *sep = strchr(remaining_name, '.');
        int want_subtree = (sep != NULL);
        uint32_t substr_size = want_subtree ? (uint32_t)(sep - remaining_name) : (uint32_t)strlen(remaining_name);
        if (!substr_size) return NULL;

        uint32_t children_off = load_u32(&current->children);
        struct prop_bt *root = children_off ? (struct prop_bt *)(mapped_prop_area->data + children_off) : NULL;
        if (!root && alloc_if_needed) {
            uint32_t new_off;
            root = new_prop_bt(remaining_name, substr_size, &new_off);
            if (root) store_u32(&current->children, new_off);
        }
        if (!root) return NULL;

        current = find_prop_bt(root, remaining_name, substr_size, alloc_if_needed);
        if (!current) return NULL;
        if (!want_subtree) break;
        remaining_name = sep + 1;
    }

    uint32_t prop_off = load_u32(&current->prop);
    if (prop_off) {
        return (struct prop_info_area *)(mapped_prop_area->data + prop_off);
    }
    if (!alloc_if_needed) return NULL;

    uint32_t new_off;
    struct prop_info_area *pi = new_prop_info(name, namelen, value, valuelen, &new_off);
    if (pi) store_u32(&current->prop, new_off);
    return pi;
}

static int map_property_area(void) {
    int fd = open(prop_area_path, O_RDWR | O_CLOEXEC);
    if (fd < 0) {
        fd = open(prop_area_path, O_RDWR | O_CREAT | O_CLOEXEC, 0444);
        if (fd < 0) return -1;
        if (ftruncate(fd, PROP_AREA_SIZE) < 0) {
            close(fd);
            return -1;
        }
    }

    struct stat st;
    if (fstat(fd, &st) < 0) {
        close(fd);
        return -1;
    }
    if ((size_t)st.st_size < sizeof(struct prop_area)) {
        if (ftruncate(fd, PROP_AREA_SIZE) < 0) {
            close(fd);
            return -1;
        }
    }

    mapped_prop_area_size = PROP_AREA_SIZE;
    void *mem = mmap(NULL, mapped_prop_area_size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    close(fd);
    if (mem == MAP_FAILED) return -1;

    mapped_prop_area = (struct prop_area *)mem;
    if (mapped_prop_area->magic != PROP_AREA_MAGIC || mapped_prop_area->version != PROP_AREA_VERSION) {
        memset(mapped_prop_area, 0, mapped_prop_area_size);
        mapped_prop_area->magic = PROP_AREA_MAGIC;
        mapped_prop_area->version = PROP_AREA_VERSION;
        mapped_prop_area->bytes_used = 0;
    }
    return 0;
}

static void bump_property_area_serial(void) {
    if (!mapped_prop_area) return;
    __atomic_fetch_add(&mapped_prop_area->serial, 1, __ATOMIC_RELEASE);
}

static void sync_property_area_entry(const char *name, const char *value) {
    uint32_t namelen = (uint32_t)strlen(name);
    uint32_t valuelen = (uint32_t)strlen(value);
    if (!mapped_prop_area || namelen == 0 || valuelen >= PROP_VALUE_MAX) return;

    struct prop_info_area *pi = find_property(name, namelen, value, valuelen, 0);
    if (!pi) {
        pi = find_property(name, namelen, value, valuelen, 1);
        if (!pi) return;
    } else {
        uint32_t serial = load_u32(&pi->serial);
        serial |= 1;
        store_u32(&pi->serial, serial);
        __atomic_thread_fence(__ATOMIC_RELEASE);
        memcpy(pi->value, value, valuelen + 1);
        store_u32(&pi->serial, (valuelen << 24) | ((serial + 1) & 0x00ffffff));
    }

    bump_property_area_serial();
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
    size_t token_len = 0;

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
        if (dot) {
            if (token_len == 0 || token_len > 255) return 0;
            token_len = 0;
        } else {
            token_len++;
        }
        last_dot = dot;
    }

    if (token_len == 0 || token_len > 255) return 0;
    return 1;
}

static uint32_t validate_property(const char *name, const char *value) {
    if (!legal_prop_name(name)) return PROP_ERROR_INVALID_NAME;
    if (strlen(value) >= PROP_VALUE_MAX && strncmp(name, "ro.", 3) != 0) {
        return PROP_ERROR_INVALID_VALUE;
    }
    return PROP_SUCCESS;
}

static void remember_property(const char *name, const char *value) {
    sync_property_area_entry(name, value);
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

    prop_area_path = argc > 2 ? argv[2] : "/dev/__properties__/u:object_r:default_prop:s0";
    signal(SIGPIPE, SIG_IGN);

    if (map_property_area() < 0) {
        fprintf(stderr, "warning: property area not available at %s; getprop will stay stale\n", prop_area_path);
    }

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

    fprintf(stderr, "property shim listening on %s area=%s\n", path, prop_area_path);

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
