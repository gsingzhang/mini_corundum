// Safe DPI-C bridge - avoids array arguments that cause VCS crashes
// Uses individual byte access instead of array passing

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define MAX_PACKETS 16
#define MAX_PACKET_SIZE 9216

static unsigned char packet_data[MAX_PACKETS][MAX_PACKET_SIZE];
static int packet_lengths[MAX_PACKETS];
static int packet_count = 0;
static int current_packet = 0;
static int current_byte = 0;
static int initialized = 0;

void init_packets() {
    if (initialized) return;

    // Test ARP request packet (60 bytes)
    unsigned char arp_pkt[] = {
        0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
        0x02, 0x00, 0x00, 0x00, 0x00, 0x01,
        0x08, 0x06,
        0x00, 0x01, 0x08, 0x00, 0x06, 0x04, 0x00, 0x01,
        0x02, 0x00, 0x00, 0x00, 0x00, 0x01,
        0xc0, 0xa8, 0x01, 0xc7,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0xc0, 0xa8, 0x01, 0x80,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    };

    memcpy(packet_data[0], arp_pkt, 60);
    packet_lengths[0] = 60;
    packet_count = 1;
    initialized = 1;
}

// Safe DPI functions using scalar types only

int dpi_packet_available() {
    if (!initialized) init_packets();
    return (current_packet < packet_count) ? 1 : 0;
}

int dpi_get_length() {
    if (!initialized) init_packets();
    if (current_packet >= packet_count) return 0;
    return packet_lengths[current_packet];
}

int dpi_get_byte(int idx) {
    if (!initialized) init_packets();
    if (current_packet >= packet_count) return 0;
    if (idx < 0 || idx >= packet_lengths[current_packet]) return 0;
    return packet_data[current_packet][idx];
}

void dpi_next_packet() {
    if (!initialized) init_packets();
    current_packet++;
}

void dpi_reset_packets() {
    current_packet = 0;
}

int dpi_get_packet_idx() {
    return current_packet;
}

int dpi_get_total_packets() {
    if (!initialized) init_packets();
    return packet_count;
}
