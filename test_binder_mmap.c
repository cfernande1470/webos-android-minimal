#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <unistd.h>

#define BINDER_ENABLE_ONEWAY_SPAM_DETECTION 0x40046210UL

int main(void) {
    int fd = open("/dev/binder", O_RDWR | O_CLOEXEC);
    if (fd < 0) {
        printf("open_rc=-1 errno=%d %s\n", errno, strerror(errno));
        return 1;
    }

    uint32_t enable = 1;
    errno = 0;
    int rc = ioctl(fd, BINDER_ENABLE_ONEWAY_SPAM_DETECTION, &enable);
    printf("spam_ioctl_rc=%d errno=%d %s\n", rc, errno, strerror(errno));

    size_t sz = 1024 * 1024 - 8192;
    errno = 0;
    void *p = mmap(NULL, sz, PROT_READ, MAP_PRIVATE, fd, 0);
    if (p == MAP_FAILED) {
        printf("mmap_rc=-1 errno=%d %s\n", errno, strerror(errno));
        close(fd);
        return 2;
    }

    printf("mmap_rc=0 addr=%p size=%zu\n", p, sz);
    munmap(p, sz);
    close(fd);
    return 0;
}
