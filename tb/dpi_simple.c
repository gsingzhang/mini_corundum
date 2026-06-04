// Simple DPI-C bridge using pre-loaded packet data
// This avoids file I/O operations that cause VCS crashes

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define MAX_PACKETS 16
#define MAX_PACKET_SIZE 9216

// Pre-allocated packet storage
static unsigned char packet_data[MAX_PACKETS][MAX_PACKET_SIZE];
static int packet_lengths[MAX_PACKETS];
static int packet_count = 0;
static int current_packet = 0;
static int initialized = 0;

// Initialize with a test ARP packet
void init_test_packets() {
    if (initialized) return;

    // Test ARP request packet (60 bytes)
    unsigned char arp_pkt[] = {
        // Ethernet header
        0xff, 0xff, 0xff, 0xff, 0xff, 0xff,  // dst MAC (broadcast)
        0x02, 0x00, 0x00, 0x00, 0x00, 0x01,  // src MAC
        0x08, 0x06,                           // type = ARP
        // ARP packet
        0x00, 0x01,                           // hw type = Ethernet
        0x08, 0x00,                           // proto type = IPv4
        0x06,                                 // hw len
        0x04,                                 // proto len
        0x00, 0x01,                           // opcode = request
        0x02, 0x00, 0x00, 0x00, 0x00, 0x01,  // sender MAC
        0xc0, 0xa8, 0x01, 0xc7,              // sender IP = 192.168.1.199
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00,  // target MAC
        0xc0, 0xa8, 0x01, 0x80,              // target IP = 192.168.1.128
        // Padding
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    };

    memcpy(packet_data[0], arp_pkt, sizeof(arp_pkt));
    packet_lengths[0] = sizeof(arp_pkt);
    packet_count = 1;
    initialized = 1;

    printf("[DPI] Initialized with %d test packets\n", packet_count);
    fflush(stdout);
}

// DPI-C function: Initialize
void dpi_simple_init() {
    init_test_packets();
}

// DPI-C function: Check if packets are available
int dpi_has_packet() {
    if (!initialized) init_test_packets();
    return (current_packet < packet_count) ? 1 : 0;
}

// DPI-C function: Get next packet length
int dpi_get_packet_length() {
    if (!initialized) init_test_packets();
    if (current_packet >= packet_count) return 0;
    return packet_lengths[current_packet];
}

// DPI-C function: Read packet data into Verilog array
void dpi_read_packet(unsigned char *data, int max_len) {
    if (!initialized) init_test_packets();
    if (current_packet >= packet_count) return;

    int len = packet_lengths[current_packet];
    if (len > max_len) len = max_len;

    memcpy(data, packet_data[current_packet], len);
    current_packet++;
}

// DPI-C function: Get packet count
int dpi_get_packet_count() {
    if (!initialized) init_test_packets();
    return packet_count - current_packet;
}

// DPI-C function: Cleanup
void dpi_simple_cleanup() {
    initialized = 0;
    packet_count = 0;
    current_packet = 0;
    printf("[DPI] Cleanup done\n");
    fflush(stdout);
}
