#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <time.h>

#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#include <winsock2.h>
#include <ws2tcpip.h>
typedef int socklen_t;
#else
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <unistd.h>
#include <errno.h>
#include <fcntl.h>
#endif

#define LUDP_MAGIC      0xDA01
#define PKT_DATA        0x01
#define PKT_CMD         0x02
#define PKT_NACK        0x03
#define PKT_CMD_ACK     0x04
#define PKT_CMD_CPL     0x05
#define PKT_CREDIT      0x06

#ifdef _WIN32
#define PRIu64_FMT "%I64u"
#else
#define PRIu64_FMT "%llu"
#endif

#define CMD_START       0x0001
#define CMD_STOP        0x0002

#define LUDP_HDR_LEN    16
#define MAX_PKT_SIZE    65536
#define DEFAULT_PORT    1234
#define DEFAULT_WINDOW  1024
#define DEFAULT_DURATION 10
#define CREDIT_INTERVAL 8
#define CMD_TIMEOUT_MS  500
#define CMD_RETRIES     5

typedef struct {
    uint64_t packets_received;
    uint64_t packets_processed;
    uint64_t packets_out_of_order;
    uint64_t bytes_received;
    uint64_t gap_count;
    uint32_t last_seq;
} stats_t;

static int sock_fd = -1;
static struct sockaddr_in fpga_addr;
static uint32_t expected_seq = 0;
static uint32_t abs_credit = DEFAULT_WINDOW;
static uint32_t highest_seq = 0;
static uint32_t window_size = DEFAULT_WINDOW;
static stats_t stats = {0};
static int running = 1;
static uint32_t next_cmd_id = 1;

static uint64_t get_time_ms(void) {
#ifdef _WIN32
    return (uint64_t)GetTickCount();
#else
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (uint64_t)ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
#endif
}

static int send_to_fpga(const uint8_t *pkt, int len) {
    return sendto(sock_fd, (const char *)pkt, len, 0,
                  (struct sockaddr *)&fpga_addr, sizeof(fpga_addr));
}

static void build_cmd(uint8_t *buf, uint16_t opcode, uint32_t arg1,
                      uint16_t arg2, uint8_t flags, uint32_t cmd_id) {
    buf[0]  = LUDP_MAGIC & 0xFF;
    buf[1]  = (LUDP_MAGIC >> 8) & 0xFF;
    buf[2]  = PKT_CMD;
    buf[3]  = flags;
    buf[4]  = cmd_id & 0xFF;
    buf[5]  = (cmd_id >> 8) & 0xFF;
    buf[6]  = (cmd_id >> 16) & 0xFF;
    buf[7]  = (cmd_id >> 24) & 0xFF;
    buf[8]  = opcode & 0xFF;
    buf[9]  = (opcode >> 8) & 0xFF;
    buf[10] = arg1 & 0xFF;
    buf[11] = (arg1 >> 8) & 0xFF;
    buf[12] = (arg1 >> 16) & 0xFF;
    buf[13] = (arg1 >> 24) & 0xFF;
    buf[14] = arg2 & 0xFF;
    buf[15] = (arg2 >> 8) & 0xFF;
}

static void build_credit(uint8_t *buf, uint32_t credit) {
    buf[0]  = LUDP_MAGIC & 0xFF;
    buf[1]  = (LUDP_MAGIC >> 8) & 0xFF;
    buf[2]  = PKT_CREDIT;
    buf[3]  = 0;
    buf[4]  = credit & 0xFF;
    buf[5]  = (credit >> 8) & 0xFF;
    buf[6]  = (credit >> 16) & 0xFF;
    buf[7]  = (credit >> 24) & 0xFF;
    buf[8]  = 0; buf[9] = 0; buf[10] = 0; buf[11] = 0;
    buf[12] = 0; buf[13] = 0; buf[14] = 0; buf[15] = 0;
}

static void send_credit(uint32_t credit) {
    uint8_t pkt[16];
    build_credit(pkt, credit);
    send_to_fpga(pkt, 16);
    abs_credit = credit;
}

static int wait_for_cmd_ack(uint32_t cmd_id, int timeout_ms) {
    uint8_t buf[MAX_PKT_SIZE];
    struct sockaddr_in from_addr;
    socklen_t from_len = sizeof(from_addr);
    uint64_t deadline = get_time_ms() + timeout_ms;

    while (get_time_ms() < deadline) {
        int n = recvfrom(sock_fd, (char *)buf, MAX_PKT_SIZE, 0,
                         (struct sockaddr *)&from_addr, &from_len);
        if (n < 0) {
#ifdef _WIN32
            int err = WSAGetLastError();
            if (err == WSAEWOULDBLOCK) {
                Sleep(1);
                continue;
            }
#else
            if (errno == EAGAIN || errno == EWOULDBLOCK) {
                usleep(1000);
                continue;
            }
#endif
            continue;
        }
        if (n < LUDP_HDR_LEN) continue;

        uint16_t magic = buf[0] | (buf[1] << 8);
        if (magic != LUDP_MAGIC) continue;

        uint8_t pkt_type = buf[2];
        if (pkt_type == PKT_CMD_ACK || pkt_type == PKT_CMD_CPL) {
            uint32_t rx_cmd_id = buf[4] | (buf[5] << 8) | (buf[6] << 16) | (buf[7] << 24);
            if (rx_cmd_id == cmd_id) return 1;
        }
    }
    return 0;
}

static int send_cmd_wait_ack(uint16_t opcode, const char *name) {
    for (int attempt = 0; attempt < CMD_RETRIES; attempt++) {
        uint32_t cmd_id = next_cmd_id++;
        uint8_t pkt[16];
        build_cmd(pkt, opcode, 0, 0, 0, cmd_id);
        send_to_fpga(pkt, 16);

        if (wait_for_cmd_ack(cmd_id, CMD_TIMEOUT_MS)) {
            printf("[OK] %s command acknowledged\n", name);
            return 1;
        }
    }
    printf("[TIMEOUT] %s command no ACK after %d retries\n", name, CMD_RETRIES);
    return 0;
}

static void set_nonblocking(int fd) {
#ifdef _WIN32
    u_long mode = 1;
    ioctlsocket(fd, FIONBIO, &mode);
#else
    int flags = fcntl(fd, F_GETFL, 0);
    fcntl(fd, F_SETFL, flags | O_NONBLOCK);
#endif
}

static void process_data_packet(const uint8_t *data, int len, FILE *out_fp) {
    if (len < LUDP_HDR_LEN) return;

    uint16_t magic = data[0] | (data[1] << 8);
    if (magic != LUDP_MAGIC) return;

    uint8_t pkt_type = data[2];
    if (pkt_type != PKT_DATA) return;

    uint32_t seq = data[4] | (data[5] << 8) | (data[6] << 16) | (data[7] << 24);
    uint16_t payload_len = data[8] | (data[9] << 8);

    stats.packets_received++;
    stats.bytes_received += len;
    stats.last_seq = seq;

    if (seq > highest_seq) highest_seq = seq;

    if (seq == expected_seq) {
        stats.packets_processed++;
        if (out_fp && payload_len > 0) {
            fwrite(data + LUDP_HDR_LEN, 1, payload_len, out_fp);
        }
        expected_seq++;

        if (expected_seq % CREDIT_INTERVAL == 0) {
            uint32_t new_credit = expected_seq + window_size;
            if (new_credit > abs_credit) send_credit(new_credit);
        }
    } else if (seq > expected_seq) {
        stats.packets_out_of_order++;
        stats.gap_count += seq - expected_seq;
        expected_seq = seq + 1;
        stats.packets_processed++;
        if (out_fp && payload_len > 0) {
            fwrite(data + LUDP_HDR_LEN, 1, payload_len, out_fp);
        }
        uint32_t new_credit = expected_seq + window_size;
        if (new_credit > abs_credit) send_credit(new_credit);
    }
}

int main(int argc, char *argv[]) {
    char *fpga_ip = "192.168.1.128";
    int port = DEFAULT_PORT;
    int duration = DEFAULT_DURATION;
    char *output_file = NULL;
    int debug = 0;
    int no_write = 0;

    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--fpga-ip") == 0 && i + 1 < argc) fpga_ip = argv[++i];
        else if (strcmp(argv[i], "--port") == 0 && i + 1 < argc) port = atoi(argv[++i]);
        else if (strcmp(argv[i], "-o") == 0 && i + 1 < argc) output_file = argv[++i];
        else if (strcmp(argv[i], "--timeout") == 0 && i + 1 < argc) duration = atoi(argv[++i]);
        else if (strcmp(argv[i], "--debug") == 0) debug = 1;
        else if (strcmp(argv[i], "--no-write") == 0) no_write = 1;
        else if (strcmp(argv[i], "--window") == 0 && i + 1 < argc) window_size = atoi(argv[++i]);
        else { printf("Unknown option: %s\n", argv[i]); return 1; }
    }

#ifdef _WIN32
    WSADATA wsa;
    WSAStartup(MAKEWORD(2, 2), &wsa);
#endif

    sock_fd = socket(AF_INET, SOCK_DGRAM, 0);
    if (sock_fd < 0) { perror("socket"); return 1; }

    int rcvbuf = 64 * 1024 * 1024;
    setsockopt(sock_fd, SOL_SOCKET, SO_RCVBUF, (const char *)&rcvbuf, sizeof(rcvbuf));
    int sndbuf = 16 * 1024 * 1024;
    setsockopt(sock_fd, SOL_SOCKET, SO_SNDBUF, (const char *)&sndbuf, sizeof(sndbuf));

    struct sockaddr_in local_addr;
    memset(&local_addr, 0, sizeof(local_addr));
    local_addr.sin_family = AF_INET;
    local_addr.sin_addr.s_addr = INADDR_ANY;
    local_addr.sin_port = htons(port);
    if (bind(sock_fd, (struct sockaddr *)&local_addr, sizeof(local_addr)) < 0) {
        perror("bind"); return 1;
    }

    memset(&fpga_addr, 0, sizeof(fpga_addr));
    fpga_addr.sin_family = AF_INET;
    fpga_addr.sin_port = htons(DEFAULT_PORT);
#ifdef _WIN32
    fpga_addr.sin_addr.s_addr = inet_addr(fpga_ip);
#else
    inet_pton(AF_INET, fpga_ip, &fpga_addr.sin_addr);
#endif

    set_nonblocking(sock_fd);

    printf("[APP] %s\n", no_write ? "Receive-only mode (no file output)" :
           (output_file ? "Writing raw payload data" : "Receive-only mode (use -o to save)"));
    printf("[LUDP] Host started. FPGA=%s:%d\n", fpga_ip, DEFAULT_PORT);

    FILE *out_fp = NULL;
    if (!no_write && output_file) {
        out_fp = fopen(output_file, "wb");
        if (!out_fp) { perror("fopen"); return 1; }
    }

    if (!send_cmd_wait_ack(CMD_START, "START")) {
        printf("[APP] Failed to start acquisition. Exiting.\n");
        fclose(out_fp);
        return 1;
    }

    abs_credit = window_size;
    send_credit(abs_credit);

    uint64_t start_time = get_time_ms();
    uint64_t last_stats_time = start_time;
    uint64_t last_credit_time = start_time;
    int idle_count = 0;

    while (running) {
        uint64_t now = get_time_ms();
        if (now - start_time >= (uint64_t)duration * 1000) break;

        int got_data = 0;
        for (int b = 0; b < 256; b++) {
            uint8_t buf[MAX_PKT_SIZE];
            struct sockaddr_in from_addr;
            socklen_t from_len = sizeof(from_addr);
            int n = recvfrom(sock_fd, (char *)buf, MAX_PKT_SIZE, 0,
                             (struct sockaddr *)&from_addr, &from_len);
            if (n < 0) {
#ifdef _WIN32
                int err = WSAGetLastError();
                if (err == WSAEWOULDBLOCK) break;
#else
                if (errno == EAGAIN || errno == EWOULDBLOCK) break;
#endif
                break;
            }
            if (n < LUDP_HDR_LEN) continue;

            uint16_t magic = buf[0] | (buf[1] << 8);
            if (magic != LUDP_MAGIC) continue;

            uint8_t pkt_type = buf[2];
            if (pkt_type == PKT_DATA) {
                process_data_packet(buf, n, out_fp);
                got_data = 1;
            } else if (pkt_type == PKT_CMD_ACK || pkt_type == PKT_CMD_CPL) {
                if (debug) {
                    uint32_t rx_cmd_id = buf[4] | (buf[5] << 8) | (buf[6] << 16) | (buf[7] << 24);
                    printf("[DEBUG RX] CMD_ACK/CPL cmd_id=%u\n", rx_cmd_id);
                }
            }
        }

        now = get_time_ms();

        if (now - last_credit_time >= 1) {
            uint32_t new_credit = expected_seq + window_size;
            if (new_credit > abs_credit) send_credit(new_credit);
            last_credit_time = now;
        }

        if (!got_data) {
            idle_count++;
            if (idle_count > 100) {
#ifdef _WIN32
                Sleep(1);
#else
                usleep(1000);
#endif
                idle_count = 0;
            }
        } else {
            idle_count = 0;
        }

        if (now - last_stats_time >= 1000) {
            double elapsed = (now - start_time) / 1000.0;
            double mbps = stats.bytes_received * 8.0 / (elapsed * 1e6);
            double kpps = stats.packets_received / (elapsed * 1000.0);
            printf("[STATS] rx=" PRIu64_FMT " proc=" PRIu64_FMT " ooo=" PRIu64_FMT " gaps=" PRIu64_FMT " %.1f Mbps %.1f kpps\n",
                   (unsigned long long)stats.packets_received,
                   (unsigned long long)stats.packets_processed,
                   (unsigned long long)stats.packets_out_of_order,
                   (unsigned long long)stats.gap_count,
                   mbps, kpps);
            last_stats_time = now;
        }
    }

    send_cmd_wait_ack(CMD_STOP, "STOP");

    double elapsed = (get_time_ms() - start_time) / 1000.0;
    double mbps = stats.bytes_received * 8.0 / (elapsed * 1e6);
    double kpps = stats.packets_received / (elapsed * 1000.0);
    double ooo_pct = stats.packets_received > 0 ?
        100.0 * stats.packets_out_of_order / stats.packets_received : 0;
    printf("[APP] Stats: " PRIu64_FMT " processed, " PRIu64_FMT " OOO (%.1f%%), " PRIu64_FMT " gaps, %.1f Mbps, %.1f kpps, elapsed=%.1fs\n",
           (unsigned long long)stats.packets_processed,
           (unsigned long long)stats.packets_out_of_order,
           ooo_pct,
           (unsigned long long)stats.gap_count,
           mbps, kpps, elapsed);

    fflush(out_fp);
    if (out_fp) fclose(out_fp);

#ifdef _WIN32
    closesocket(sock_fd);
    WSACleanup();
#else
    close(sock_fd);
#endif

    printf("[LUDP] Host stopped.\n");
    printf("[APP] Data saved to %s\n", output_file ? output_file : "N/A");
    return 0;
}
