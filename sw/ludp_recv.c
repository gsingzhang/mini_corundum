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
#define DEFAULT_WINDOW  2048
#define DEFAULT_DURATION 10
#define STATS_INTERVAL_SEC 30
#define CREDIT_INTERVAL 64
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

#ifdef _WIN32
static BOOL WINAPI ctrl_handler(DWORD type) {
    if (type == CTRL_C_EVENT || type == CTRL_BREAK_EVENT) {
        running = 0;
        return TRUE;
    }
    return FALSE;
}
#else
static void ctrl_handler(int sig) {
    (void)sig;
    running = 0;
}
#endif

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

static void build_nack(uint8_t *buf, uint32_t seq) {
    buf[0]  = LUDP_MAGIC & 0xFF;
    buf[1]  = (LUDP_MAGIC >> 8) & 0xFF;
    buf[2]  = PKT_NACK;
    buf[3]  = 0;
    buf[4]  = seq & 0xFF;
    buf[5]  = (seq >> 8) & 0xFF;
    buf[6]  = (seq >> 16) & 0xFF;
    buf[7]  = (seq >> 24) & 0xFF;
    buf[8]  = 0; buf[9] = 0; buf[10] = 0; buf[11] = 0;
    buf[12] = 0; buf[13] = 0; buf[14] = 0; buf[15] = 0;
}

static void send_nack(uint32_t seq) {
    uint8_t pkt[16];
    build_nack(pkt, seq);
    send_to_fpga(pkt, 16);
}

static int wait_for_cmd_ack(uint32_t cmd_id, int timeout_ms) {
    uint8_t buf[MAX_PKT_SIZE];
    struct sockaddr_in from_addr;
    socklen_t from_len = sizeof(from_addr);
    uint64_t deadline = get_time_ms() + timeout_ms;

    // Temporarily set blocking with timeout for reliable ACK reception
#ifdef _WIN32
    u_long mode = 0;
    ioctlsocket(sock_fd, FIONBIO, &mode);
    DWORD tv = (DWORD)timeout_ms;
    setsockopt(sock_fd, SOL_SOCKET, SO_RCVTIMEO, (const char *)&tv, sizeof(tv));
#else
    struct timeval tv;
    tv.tv_sec = timeout_ms / 1000;
    tv.tv_usec = (timeout_ms % 1000) * 1000;
    setsockopt(sock_fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
#endif

    while (get_time_ms() < deadline) {
        int n = recvfrom(sock_fd, (char *)buf, MAX_PKT_SIZE, 0,
                         (struct sockaddr *)&from_addr, &from_len);
        if (n < 0) break;  // timeout or error

        if (n < LUDP_HDR_LEN) continue;

        uint16_t magic = buf[0] | (buf[1] << 8);
        if (magic != LUDP_MAGIC) continue;

        uint8_t pkt_type = buf[2];
        if (pkt_type == PKT_CMD_ACK || pkt_type == PKT_CMD_CPL) {
            uint32_t rx_cmd_id = buf[4] | (buf[5] << 8) | (buf[6] << 16) | (buf[7] << 24);
            if (rx_cmd_id == cmd_id) {
                // Restore non-blocking mode
#ifdef _WIN32
                mode = 1;
                ioctlsocket(sock_fd, FIONBIO, &mode);
#else
                int flags = fcntl(sock_fd, F_GETFL, 0);
                fcntl(sock_fd, F_SETFL, flags | O_NONBLOCK);
#endif
                return 1;
            }
        }
    }

    // Restore non-blocking mode
#ifdef _WIN32
    mode = 1;
    ioctlsocket(sock_fd, FIONBIO, &mode);
#else
    int flags = fcntl(sock_fd, F_GETFL, 0);
    fcntl(sock_fd, F_SETFL, flags | O_NONBLOCK);
#endif
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

static inline void process_data_packet(const uint8_t *data, int len, FILE *out_fp) {
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
    } else if (seq > expected_seq) {
        stats.packets_out_of_order++;
        stats.gap_count += seq - expected_seq;
        expected_seq = seq + 1;
        stats.packets_processed++;
        if (out_fp && payload_len > 0) {
            fwrite(data + LUDP_HDR_LEN, 1, payload_len, out_fp);
        }
    }
}

int main(int argc, char *argv[]) {
    char *fpga_ip = "192.168.1.128";
    int port = DEFAULT_PORT;
    int duration = DEFAULT_DURATION;
    char *output_file = NULL;
    int debug = 0;
    int continuous = 0;
    int stats_interval = STATS_INTERVAL_SEC;

    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--fpga-ip") == 0 && i + 1 < argc) fpga_ip = argv[++i];
        else if (strcmp(argv[i], "--port") == 0 && i + 1 < argc) port = atoi(argv[++i]);
        else if (strcmp(argv[i], "-o") == 0 && i + 1 < argc) output_file = argv[++i];
        else if (strcmp(argv[i], "--timeout") == 0 && i + 1 < argc) duration = atoi(argv[++i]);
        else if (strcmp(argv[i], "--debug") == 0) debug = 1;
        else if (strcmp(argv[i], "--window") == 0 && i + 1 < argc) window_size = atoi(argv[++i]);
        else if (strcmp(argv[i], "--continuous") == 0) continuous = 1;
        else if (strcmp(argv[i], "--stats-interval") == 0 && i + 1 < argc) stats_interval = atoi(argv[++i]);
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

#ifdef _WIN32
    SetConsoleCtrlHandler(ctrl_handler, TRUE);
#else
    signal(SIGINT, ctrl_handler);
#endif

    // Drain any stale packets from previous run
    {
        int drained = 0;
        uint8_t drain_buf[MAX_PKT_SIZE];
        struct sockaddr_in drain_addr;
        socklen_t drain_len = sizeof(drain_addr);
        for (int i = 0; i < 10000; i++) {
            int n = recvfrom(sock_fd, (char *)drain_buf, MAX_PKT_SIZE, 0,
                             (struct sockaddr *)&drain_addr, &drain_len);
            if (n < 0) break;
            drained++;
        }
        if (drained > 0) printf("[APP] Drained %d stale packets\n", drained);
    }

    // Reset state for fresh start
    send_cmd_wait_ack(CMD_STOP, "STOP(reset)");

    {
        int drained = 0;
        uint8_t drain_buf2[MAX_PKT_SIZE];
        struct sockaddr_in drain_addr2;
        socklen_t drain_len2 = sizeof(drain_addr2);
        for (int i = 0; i < 10000; i++) {
            int n = recvfrom(sock_fd, (char *)drain_buf2, MAX_PKT_SIZE, 0,
                             (struct sockaddr *)&drain_addr2, &drain_len2);
            if (n < 0) break;
            drained++;
        }
        if (drained > 0) printf("[APP] Drained %d stale packets after STOP\n", drained);
    }

    expected_seq = 0;
    abs_credit = window_size;
    highest_seq = 0;
    memset(&stats, 0, sizeof(stats));
    next_cmd_id = 1;

    printf("[APP] %s\n", output_file ? "Writing raw payload data" :
           "Receive-only mode (use -o <file> to save)");
    if (continuous) {
        printf("[APP] Continuous mode - press Ctrl+C to stop\n");
    }
    printf("[LUDP] Host started. FPGA=%s:%d window=%u stats_interval=%ds\n",
           fpga_ip, DEFAULT_PORT, window_size, stats_interval);

    FILE *out_fp = NULL;
    if (output_file) {
        out_fp = fopen(output_file, "wb");
        if (!out_fp) { perror("fopen"); return 1; }
    }

    if (!send_cmd_wait_ack(CMD_START, "START")) {
        printf("[APP] Failed to start acquisition. Exiting.\n");
        if (out_fp) fclose(out_fp);
        return 1;
    }

    abs_credit = window_size;
    send_credit(abs_credit);

    uint8_t credit_pkt[16];
    build_credit(credit_pkt, 0);

    uint64_t start_time = get_time_ms();
    uint64_t last_stats_time = start_time;
    uint64_t last_data_time = start_time;
    uint64_t last_credit_time = start_time;
    uint64_t last_warn_time = start_time;
    uint32_t last_credit_seq = 0;
    stats_t interval_stats = {0};

    while (running) {
        uint64_t now = get_time_ms();
        if (!continuous && (now - start_time >= (uint64_t)duration * 1000)) break;

        int got_data = 0;
        int rx_count = 0;
        for (int b = 0; b < 1024; b++) {
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
                uint64_t prev_rx = stats.packets_received;
                process_data_packet(buf, n, out_fp);
                if (stats.packets_received > prev_rx) {
                    interval_stats.packets_received++;
                    interval_stats.bytes_received += n;
                    interval_stats.packets_processed++;
                    if (stats.packets_out_of_order > interval_stats.packets_out_of_order) {
                        interval_stats.packets_out_of_order++;
                        interval_stats.gap_count += stats.gap_count - interval_stats.gap_count;
                    }
                    rx_count++;
                }
                got_data = 1;
            } else if (pkt_type == PKT_CMD_ACK || pkt_type == PKT_CMD_CPL) {
                if (debug) {
                    uint32_t rx_cmd_id = buf[4] | (buf[5] << 8) | (buf[6] << 16) | (buf[7] << 24);
                    printf("[DEBUG RX] CMD_ACK/CPL cmd_id=%u\n", rx_cmd_id);
                }
            }

            if (rx_count >= CREDIT_INTERVAL) {
                uint32_t new_credit = expected_seq + window_size;
                if (new_credit > abs_credit) {
                    build_credit(credit_pkt, new_credit);
                    sendto(sock_fd, (const char *)credit_pkt, 16, 0,
                           (struct sockaddr *)&fpga_addr, sizeof(fpga_addr));
                    abs_credit = new_credit;
                    last_credit_seq = expected_seq;
                    last_credit_time = get_time_ms();
                }
                rx_count = 0;
            }
        }

        if (got_data) last_data_time = get_time_ms();

        if (expected_seq != last_credit_seq) {
            uint32_t new_credit = expected_seq + window_size;
            if (new_credit > abs_credit) {
                build_credit(credit_pkt, new_credit);
                sendto(sock_fd, (const char *)credit_pkt, 16, 0,
                       (struct sockaddr *)&fpga_addr, sizeof(fpga_addr));
                abs_credit = new_credit;
                last_credit_seq = expected_seq;
                last_credit_time = get_time_ms();
            }
        }

        now = get_time_ms();
        uint64_t data_gap_ms = now - last_data_time;
        int credit_interval_ms = (data_gap_ms > 500) ? 10 : 100;
        if (now - last_credit_time >= (uint64_t)credit_interval_ms) {
            uint32_t new_credit = expected_seq + window_size;
            build_credit(credit_pkt, new_credit);
            sendto(sock_fd, (const char *)credit_pkt, 16, 0,
                   (struct sockaddr *)&fpga_addr, sizeof(fpga_addr));
            abs_credit = new_credit;
            last_credit_time = now;
        }

        if (data_gap_ms >= 200 && data_gap_ms < 5000) {
            static uint64_t last_nack_time = 0;
            if (now - last_nack_time >= 50) {
                send_nack(expected_seq);
                uint32_t new_credit = expected_seq + window_size;
                build_credit(credit_pkt, new_credit);
                sendto(sock_fd, (const char *)credit_pkt, 16, 0,
                       (struct sockaddr *)&fpga_addr, sizeof(fpga_addr));
                abs_credit = new_credit;
                last_nack_time = now;
            }
        }

        if (now - last_warn_time >= 2000 && data_gap_ms >= 2000) {
            printf("[WARN] No data for %.1fs, credit=%u expected=%u seq_highest=%u\n",
                   data_gap_ms / 1000.0, abs_credit, expected_seq, highest_seq);
            last_warn_time = now;
        }

        if (data_gap_ms >= 5000 && continuous) {
            printf("[RECOVERY] No data for 5s, attempting FPGA reset...\n");
            send_cmd_wait_ack(CMD_STOP, "STOP(recovery)");

            {
                uint8_t drain_buf[MAX_PKT_SIZE];
                struct sockaddr_in drain_addr;
                socklen_t drain_len = sizeof(drain_addr);
                for (int i = 0; i < 10000; i++) {
                    int n = recvfrom(sock_fd, (char *)drain_buf, MAX_PKT_SIZE, 0,
                                     (struct sockaddr *)&drain_addr, &drain_len);
                    if (n < 0) break;
                }
            }

            expected_seq = 0;
            abs_credit = 0;
            highest_seq = 0;
            memset(&stats, 0, sizeof(stats));
            memset(&interval_stats, 0, sizeof(interval_stats));
            last_credit_seq = 0;

            if (send_cmd_wait_ack(CMD_START, "START(recovery)")) {
                abs_credit = window_size;
                send_credit(abs_credit);
                start_time = get_time_ms();
                last_stats_time = start_time;
                last_data_time = start_time;
                last_credit_time = start_time;
                last_warn_time = start_time;
                printf("[RECOVERY] FPGA reset successful, resuming data capture\n");
            } else {
                printf("[RECOVERY] FPGA reset failed, will retry in 5s\n");
                last_data_time = now;
            }
        }

        if (!got_data) {
#ifdef _WIN32
            SwitchToThread();
#else
            sched_yield();
#endif
        }

        now = get_time_ms();
        if (now - last_stats_time >= (uint64_t)stats_interval * 1000) {
            double int_elapsed = (now - last_stats_time) / 1000.0;
            double int_mbps = interval_stats.bytes_received * 8.0 / (int_elapsed * 1e6);
            double int_kpps = interval_stats.packets_received / (int_elapsed * 1000.0);
            double int_ooo_pct = interval_stats.packets_received > 0 ?
                100.0 * interval_stats.packets_out_of_order / interval_stats.packets_received : 0;

            double total_elapsed = (now - start_time) / 1000.0;
            double total_mbps = stats.bytes_received * 8.0 / (total_elapsed * 1e6);
            double total_kpps = stats.packets_received / (total_elapsed * 1000.0);
            double total_ooo_pct = stats.packets_received > 0 ?
                100.0 * stats.packets_out_of_order / stats.packets_received : 0;

            printf("[STATS] interval: %.1f Mbps %.1f kpps ooo=%.1f%% rx=" PRIu64_FMT " | "
                   "total: %.1f Mbps %.1f kpps ooo=%.1f%% rx=" PRIu64_FMT " gaps=" PRIu64_FMT " credit=%u exp=%u\n",
                   int_mbps, int_kpps, int_ooo_pct,
                   (unsigned long long)interval_stats.packets_received,
                   total_mbps, total_kpps, total_ooo_pct,
                   (unsigned long long)stats.packets_received,
                   (unsigned long long)stats.gap_count,
                   abs_credit, expected_seq);

            interval_stats = (stats_t){0};
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

    if (out_fp) {
        fflush(out_fp);
        fclose(out_fp);
        printf("[APP] Data saved to %s\n", output_file);
    }

#ifdef _WIN32
    closesocket(sock_fd);
    WSACleanup();
#else
    close(sock_fd);
#endif

    printf("[LUDP] Host stopped.\n");
    return 0;
}
