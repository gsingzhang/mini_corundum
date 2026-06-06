#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <time.h>

#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#include <winsock2.h>
#include <ws2tcpip.h>
#include <pcap.h>
typedef int socklen_t;
#else
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <unistd.h>
#include <errno.h>
#include <pcap/pcap.h>
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
#define CMD_TIMEOUT_MS  500
#define CMD_RETRIES     5
#define CREDIT_INTERVAL 8

#define ETH_HDR_LEN     14
#define IP_HDR_LEN      20
#define UDP_HDR_LEN     8

typedef struct {
    uint64_t packets_received;
    uint64_t packets_processed;
    uint64_t packets_out_of_order;
    uint64_t bytes_received;
    uint64_t gap_count;
    uint64_t gap_events;
    uint32_t last_seq;
} stats_t;

static int ctrl_sock = -1;
static struct sockaddr_in fpga_addr;
static uint32_t expected_seq = 0;
static uint32_t abs_credit = DEFAULT_WINDOW;
static uint32_t highest_rx_seq = 0;
static uint32_t window_size = DEFAULT_WINDOW;
static stats_t stats;
static int running = 1;
static uint32_t next_cmd_id = 1;
static uint8_t credit_pkt[16];
static uint32_t credit_counter = 0;
static uint16_t target_port = DEFAULT_PORT;
static uint16_t ctrl_src_port = 0;

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
    return sendto(ctrl_sock, (const char *)pkt, len, 0,
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
    build_credit(credit_pkt, credit);
    send_to_fpga(credit_pkt, 16);
    abs_credit = credit;
}

static void update_credit(void) {
    uint32_t credit_base = highest_rx_seq > expected_seq ? highest_rx_seq : expected_seq;
    uint32_t new_credit = credit_base + window_size;
    if (new_credit > abs_credit) {
        send_credit(new_credit);
    }
}

static int wait_for_cmd_ack(uint32_t cmd_id, int timeout_ms) {
    uint8_t buf[MAX_PKT_SIZE];
    struct sockaddr_in from_addr;
    socklen_t from_len = sizeof(from_addr);
    uint64_t deadline = get_time_ms() + timeout_ms;

    while (get_time_ms() < deadline) {
        int n = recvfrom(ctrl_sock, (char *)buf, MAX_PKT_SIZE, 0,
                         (struct sockaddr *)&from_addr, &from_len);
        if (n < 0) {
#ifdef _WIN32
            int err = WSAGetLastError();
            if (err == WSAEWOULDBLOCK) {
                SwitchToThread();
                continue;
            }
#else
            if (errno == EAGAIN || errno == EWOULDBLOCK) {
                usleep(100);
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

static void pcap_handler_cb(u_char *user, const struct pcap_pkthdr *hdr,
                            const u_char *data) {
    int caplen = hdr->caplen;
    if (caplen < ETH_HDR_LEN + IP_HDR_LEN + UDP_HDR_LEN + LUDP_HDR_LEN) return;

    int ip_hdr_off = ETH_HDR_LEN;
    if ((data[ip_hdr_off] & 0xF0) != 0x40) return;

    int ip_hdr_len = (data[ip_hdr_off] & 0x0F) * 4;
    if (ip_hdr_len < IP_HDR_LEN) return;

    int udp_off = ETH_HDR_LEN + ip_hdr_len;
    if (caplen < udp_off + UDP_HDR_LEN + LUDP_HDR_LEN) return;

    uint16_t dst_port = (data[udp_off + 2] << 8) | data[udp_off + 3];
    if (dst_port != target_port && dst_port != ctrl_src_port) return;

    int ludp_off = udp_off + UDP_HDR_LEN;
    uint16_t magic = data[ludp_off] | (data[ludp_off + 1] << 8);
    if (magic != LUDP_MAGIC) return;

    uint8_t pkt_type = data[ludp_off + 2];

    if (pkt_type == PKT_DATA) {
        uint32_t seq = data[ludp_off + 4] | (data[ludp_off + 5] << 8) |
                       data[ludp_off + 6] << 16 | data[ludp_off + 7] << 24;

        stats.packets_received++;
        stats.bytes_received += caplen;
        stats.last_seq = seq;
        if (seq > highest_rx_seq) highest_rx_seq = seq;

        if (seq == expected_seq) {
            stats.packets_processed++;
            expected_seq++;
            credit_counter++;
        } else if (seq > expected_seq) {
            uint32_t gap = seq - expected_seq;
            stats.packets_out_of_order++;
            stats.gap_count += gap;
            stats.gap_events++;
            stats.packets_processed++;
            expected_seq = seq + 1;
            credit_counter++;
        }

        if (credit_counter >= CREDIT_INTERVAL) {
            update_credit();
            credit_counter = 0;
        }
    }
}

int main(int argc, char *argv[]) {
    char *fpga_ip = "192.168.1.128";
    char *local_ip = NULL;
    int port = DEFAULT_PORT;
    int duration = DEFAULT_DURATION;
    char *iface_name = NULL;

    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--fpga-ip") == 0 && i + 1 < argc) fpga_ip = argv[++i];
        else if (strcmp(argv[i], "--port") == 0 && i + 1 < argc) port = atoi(argv[++i]);
        else if (strcmp(argv[i], "--timeout") == 0 && i + 1 < argc) duration = atoi(argv[++i]);
        else if (strcmp(argv[i], "--window") == 0 && i + 1 < argc) window_size = atoi(argv[++i]);
        else if (strcmp(argv[i], "--iface") == 0 && i + 1 < argc) iface_name = argv[++i];
        else if (strcmp(argv[i], "--local-ip") == 0 && i + 1 < argc) local_ip = argv[++i];
        else { printf("Unknown option: %s\n", argv[i]); return 1; }
    }

    target_port = (uint16_t)port;

#ifdef _WIN32
    WSADATA wsa;
    WSAStartup(MAKEWORD(2, 2), &wsa);
#endif

    memset(&stats, 0, sizeof(stats));

    ctrl_sock = socket(AF_INET, SOCK_DGRAM, 0);
    if (ctrl_sock < 0) { perror("socket"); return 1; }

    int sndbuf = 16 * 1024 * 1024;
    setsockopt(ctrl_sock, SOL_SOCKET, SO_SNDBUF, (const char *)&sndbuf, sizeof(sndbuf));

    struct sockaddr_in ctrl_local;
    memset(&ctrl_local, 0, sizeof(ctrl_local));
    ctrl_local.sin_family = AF_INET;
    if (local_ip) {
        ctrl_local.sin_addr.s_addr = inet_addr(local_ip);
    } else {
        ctrl_local.sin_addr.s_addr = INADDR_ANY;
    }
    ctrl_local.sin_port = 0;
    if (bind(ctrl_sock, (struct sockaddr *)&ctrl_local, sizeof(ctrl_local)) < 0) {
        perror("bind ctrl_sock"); return 1;
    }

#ifdef _WIN32
    u_long mode = 1;
    ioctlsocket(ctrl_sock, FIONBIO, &mode);
#else
    fcntl(ctrl_sock, F_SETFL, fcntl(ctrl_sock, F_GETFL, 0) | O_NONBLOCK);
#endif

    socklen_t ctrl_local_len = sizeof(ctrl_local);
    getsockname(ctrl_sock, (struct sockaddr *)&ctrl_local, &ctrl_local_len);
    ctrl_src_port = ntohs(ctrl_local.sin_port);
    printf("[CTRL] Source port: %u\n", ctrl_src_port);

    memset(&fpga_addr, 0, sizeof(fpga_addr));
    fpga_addr.sin_family = AF_INET;
    fpga_addr.sin_port = htons(DEFAULT_PORT);
#ifdef _WIN32
    fpga_addr.sin_addr.s_addr = inet_addr(fpga_ip);
#else
    inet_pton(AF_INET, fpga_ip, &fpga_addr.sin_addr);
#endif

    char errbuf[PCAP_ERRBUF_SIZE];
    pcap_t *pcap = NULL;

    if (iface_name) {
        pcap = pcap_open_live(iface_name, 65535, 1, 1, errbuf);
    } else {
        pcap_if_t *alldevs = NULL;
        if (pcap_findalldevs(&alldevs, errbuf) == -1) {
            fprintf(stderr, "Error finding devices: %s\n", errbuf);
            return 1;
        }
        if (!alldevs) {
            fprintf(stderr, "No devices found. Install Npcap (https://npcap.com)\n");
            return 1;
        }
        printf("[PCAP] Available interfaces:\n");
        int idx = 0;
        for (pcap_if_t *d = alldevs; d; d = d->next) {
            printf("  [%d] %s%s\n", idx++, d->name,
                   d->description ? d->description : "");
        }
        pcap_if_t *selected = alldevs;
        printf("[PCAP] Using first interface: %s\n", selected->name);
        pcap = pcap_open_live(selected->name, 65535, 1, 1, errbuf);
        pcap_freealldevs(alldevs);
    }

    if (!pcap) {
        fprintf(stderr, "Failed to open pcap: %s\n", errbuf);
        fprintf(stderr, "Install Npcap from https://npcap.com\n");
        return 1;
    }

    pcap_setnonblock(pcap, 1, errbuf);

    char filter[256];
    snprintf(filter, sizeof(filter), "udp and (dst port %d or dst port %u)", port, ctrl_src_port);
    printf("[PCAP] Using filter: %s\n", filter);
    struct bpf_program fp;
    if (pcap_compile(pcap, &fp, filter, 0, 0xFFFFFF00) == -1) {
        fprintf(stderr, "Bad filter: %s\n", pcap_geterr(pcap));
        return 1;
    }
    if (pcap_setfilter(pcap, &fp) == -1) {
        fprintf(stderr, "Set filter failed: %s\n", pcap_geterr(pcap));
        return 1;
    }
    pcap_freecode(&fp);

#ifdef _WIN32
    SetThreadPriority(GetCurrentThread(), THREAD_PRIORITY_HIGHEST);
    SetProcessPriorityBoost(GetCurrentProcess(), FALSE);
#endif

    printf("[APP] Npcap kernel-bypass receiver\n");
    printf("[LUDP] Host started. FPGA=%s:%d window=%u\n", fpga_ip, DEFAULT_PORT, window_size);

    send_cmd_wait_ack(CMD_STOP, "STOP(reset)");

    expected_seq = 0;
    abs_credit = 0;
    highest_rx_seq = 0;
    credit_counter = 0;
    memset(&stats, 0, sizeof(stats));

    if (!send_cmd_wait_ack(CMD_START, "START")) {
        printf("[APP] Failed to start acquisition. Exiting.\n");
        pcap_close(pcap);
        return 1;
    }

    abs_credit = window_size;
    send_credit(abs_credit);

    uint64_t start_time = get_time_ms();
    uint64_t last_stats_time = start_time;

    while (running) {
        uint64_t now = get_time_ms();
        if (now - start_time >= (uint64_t)duration * 1000) break;

        int cnt = pcap_dispatch(pcap, 4096, pcap_handler_cb, NULL);
        if (cnt <= 0) {
            update_credit();
#ifdef _WIN32
            SwitchToThread();
#else
            sched_yield();
#endif
        }

        now = get_time_ms();
        if (now - last_stats_time >= 1000) {
            double elapsed = (now - start_time) / 1000.0;
            double mbps = stats.bytes_received * 8.0 / (elapsed * 1e6);
            double kpps = stats.packets_received / (elapsed * 1000.0);
            double ooo_pct = stats.packets_received > 0 ?
                100.0 * stats.packets_out_of_order / stats.packets_received : 0;
            printf("[STATS] rx=" PRIu64_FMT " proc=" PRIu64_FMT
                   " ooo=" PRIu64_FMT "(%.1f%%)"
                   " gaps=" PRIu64_FMT "/" PRIu64_FMT
                   " %.1f Mbps %.1f kpps\n",
                   (unsigned long long)stats.packets_received,
                   (unsigned long long)stats.packets_processed,
                   (unsigned long long)stats.packets_out_of_order, ooo_pct,
                   (unsigned long long)stats.gap_count,
                   (unsigned long long)stats.gap_events,
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
    printf("[APP] Stats: " PRIu64_FMT " processed, "
           PRIu64_FMT " OOO (%.1f%%), "
           PRIu64_FMT " gaps in " PRIu64_FMT " events, "
           "%.1f Mbps, %.1f kpps, elapsed=%.1fs\n",
           (unsigned long long)stats.packets_processed,
           (unsigned long long)stats.packets_out_of_order, ooo_pct,
           (unsigned long long)stats.gap_count,
           (unsigned long long)stats.gap_events,
           mbps, kpps, elapsed);

    pcap_close(pcap);

#ifdef _WIN32
    closesocket(ctrl_sock);
    WSACleanup();
#else
    close(ctrl_sock);
#endif

    printf("[LUDP] Host stopped.\n");
    return 0;
}

