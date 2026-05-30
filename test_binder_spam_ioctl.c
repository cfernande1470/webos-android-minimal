#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/ioctl.h>
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
    printf("ioctl_rc=%d errno=%d %s\n", rc, errno, strerror(errno));

    close(fd);
    return rc == 0 ? 0 : 2;
}
