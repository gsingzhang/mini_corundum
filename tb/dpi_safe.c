// Safe DPI-C bridge - avoids array arguments that cause VCS crashes
// Uses individual byte access instead of array passing
// Reads packets from file written by Python packet generator

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define MAX_PACKETS 16
#define MAX_PACKET_SIZE 9216
#define PACKET_FILE "/tmp/ludp_dpi_fifo/packets.bin"

static unsigned char packet_data[MAX_PACKETS][MAX_PACKET_SIZE];
static int packet_lengths[MAX_PACKETS];
static int packet_count = 0;
static int current_packet = 0;
static int current_byte = 0;
static int initialized = 0;

void load_packets_from_file() {
    FILE *f = fopen(PACKET_FILE, "rb");
    if (!f) {
        printf("[DPI] Warning: Could not open %s, using fallback ARP packet\n", PACKET_FILE);
        return;
    }

    unsigned int count;
    if (fread(&count, sizeof(unsigned int), 1, f) != 1) {
        printf("[DPI] Warning: Could not read packet count from %s\n", PACKET_FILE);
        fclose(f);
        return;
    }

    if (count > MAX_PACKETS) count = MAX_PACKETS;

    for (unsigned int i = 0; i < count; i++) {
        unsigned int len;
        if (fread(&len, sizeof(unsigned int), 1, f) != 1) break;
        if (len > MAX_PACKET_SIZE) len = MAX_PACKET_SIZE;
        if (fread(packet_data[i], 1, len, f) != len) break;
        packet_lengths[i] = len;
        packet_count++;
    }

    fclose(f);
    printf("[DPI] Loaded %d packets from %s\n", packet_count, PACKET_FILE);
}

void init_packets() {
    if (initialized) return;

    // Try to load from file first
    load_packets_from_file();

    // Fallback: use hardcoded ARP packet if file not available
    if (packet_count == 0) {
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
        printf("[DPI] Using fallback ARP packet\n");
    }

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
