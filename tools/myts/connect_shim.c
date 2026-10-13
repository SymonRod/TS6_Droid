/*
 * LD_PRELOAD shim: send a program's outgoing TCP :443 connections through an
 * HTTP CONNECT proxy, for clients that ignore HTTPS_PROXY (the TeamSpeak
 * desktop client's cpp-httplib does).
 *
 *   gcc -shared -fPIC -O2 -o connect_shim.so connect_shim.c -ldl
 *   MYTS_PROXY_PORT=8089 LD_PRELOAD=$PWD/connect_shim.so /opt/teamspeak/TeamSpeak
 *
 * Only the main process is redirected: Chromium helpers (argv contains
 * "--type=") keep their own networking. The CONNECT handshake runs blocking
 * even on non-blocking sockets and connect() then returns 0, which callers
 * waiting for EINPROGRESS accept as an immediate success.
 *
 * MYTS_SHIM_LOG=/path/file appends one line per process start and per
 * connect() (destination, redirected or not, result, proxy status line).
 */
#define _GNU_SOURCE
#include <arpa/inet.h>
#include <dlfcn.h>
#include <errno.h>
#include <fcntl.h>
#include <netinet/in.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>

static int (*real_connect)(int, const struct sockaddr *, socklen_t);
static int enabled;
static int proxy_port = 8089;
static int log_fd = -1;

#define LOG(...) do { if (log_fd >= 0) dprintf(log_fd, __VA_ARGS__); } while (0)

__attribute__((constructor)) static void init(void) {
    real_connect = dlsym(RTLD_NEXT, "connect");
    const char *port = getenv("MYTS_PROXY_PORT");
    if (port) proxy_port = atoi(port);

    char cmdline[4096] = {0};
    FILE *f = fopen("/proc/self/cmdline", "r");
    if (!f) return;
    size_t n = fread(cmdline, 1, sizeof cmdline - 1, f);
    fclose(f);
    for (size_t i = 0; i < n; i++)
        if (cmdline[i] == '\0') cmdline[i] = ' ';
    enabled = strstr(cmdline, "--type=") == NULL;

    const char *log = getenv("MYTS_SHIM_LOG");
    if (log) log_fd = open(log, O_WRONLY | O_CREAT | O_APPEND | O_CLOEXEC, 0600);
    LOG("pid=%d start enabled=%d cmd=%.120s\n", getpid(), enabled, cmdline);
}

static char proxy_status[128];

static int handshake(int fd, const char *host, int port) {
    char buf[512];
    int len = snprintf(buf, sizeof buf,
                       "CONNECT %s:%d HTTP/1.1\r\nHost: %s:%d\r\n\r\n",
                       host, port, host, port);
    if (write(fd, buf, len) != len) return -1;
    /* Read the proxy reply up to the blank line, one byte at a time so no
     * TLS bytes are consumed. */
    size_t got = 0;
    while (got < sizeof buf - 1) {
        if (read(fd, buf + got, 1) != 1) return -1;
        got++;
        if (got >= 4 && memcmp(buf + got - 4, "\r\n\r\n", 4) == 0) break;
    }
    buf[got] = '\0';
    snprintf(proxy_status, sizeof proxy_status, "%.*s", (int)strcspn(buf, "\r\n"), buf);
    return strncmp(buf + 9, "200", 3) == 0 ? 0 : -1;
}

int connect(int fd, const struct sockaddr *addr, socklen_t len) {
    if (!enabled || !addr)
        return real_connect(fd, addr, len);
    if (addr->sa_family == AF_INET6) {
        char h6[INET6_ADDRSTRLEN];
        const struct sockaddr_in6 *in6 = (const struct sockaddr_in6 *)addr;
        inet_ntop(AF_INET6, &in6->sin6_addr, h6, sizeof h6);
        int rc = real_connect(fd, addr, len);
        int e = errno;
        LOG("pid=%d fd=%d [%s]:%d direct(v6) rc=%d errno=%d\n", getpid(), fd, h6,
            ntohs(in6->sin6_port), rc, rc ? e : 0);
        errno = e;
        return rc;
    }
    if (addr->sa_family != AF_INET)
        return real_connect(fd, addr, len);
    const struct sockaddr_in *in = (const struct sockaddr_in *)addr;
    int type = 0;
    socklen_t tl = sizeof type;
    char host[INET_ADDRSTRLEN];
    inet_ntop(AF_INET, &in->sin_addr, host, sizeof host);
    if (ntohs(in->sin_port) != 443 ||
        getsockopt(fd, SOL_SOCKET, SO_TYPE, &type, &tl) != 0 ||
        type != SOCK_STREAM) {
        int rc = real_connect(fd, addr, len);
        int e = errno;
        LOG("pid=%d fd=%d %s:%d direct type=%d rc=%d errno=%d\n", getpid(), fd, host,
            ntohs(in->sin_port), type, rc, rc ? e : 0);
        errno = e;
        return rc;
    }

    struct sockaddr_in proxy = {0};
    proxy.sin_family = AF_INET;
    proxy.sin_port = htons(proxy_port);
    proxy.sin_addr.s_addr = htonl(INADDR_LOOPBACK);

    int flags = fcntl(fd, F_GETFL);
    fcntl(fd, F_SETFL, flags & ~O_NONBLOCK);
    int rc = real_connect(fd, (struct sockaddr *)&proxy, sizeof proxy);
    if (rc == 0 && handshake(fd, host, 443) != 0) {
        rc = -1;
        errno = ECONNREFUSED;
    }
    int saved = errno;
    LOG("pid=%d fd=%d %s:443 via-proxy nonblock=%d rc=%d errno=%d proxy=\"%s\"\n", getpid(),
        fd, host, !!(flags & O_NONBLOCK), rc, rc ? saved : 0, proxy_status);
    proxy_status[0] = '\0';
    fcntl(fd, F_SETFL, flags);
    errno = saved;
    return rc;
}
