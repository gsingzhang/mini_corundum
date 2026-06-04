// DPI-C FIFO-based packet bridge for Python co-simulation
// Uses a shared memory-like approach via files for robust VCS co-simulation

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <errno.h>

#define FIFO_DIR "/tmp/ludp_dpi_fifo"
#define MAX_PACKET_SIZE 9216
#define MAX_PACKETS 256

static int initialized = 0;
static FILE *pkt_file = NULL;
static long file_pos = 0;

// Packet buffer
static unsigned char packet_buffer[MAX_PACKETS][MAX_PACKET_SIZE];
static int packet_lengths[MAX_PACKETS];
static int packet_count = 0;
static int packet_read_idx = 0;

// Initialize FIFO
int dpi_fifo_init() {
    if (initialized) return 0;

    // Create FIFO directory
    mkdir(FIFO_DIR, 0777);

    printf("[DPI] FIFO bridge initialized, waiting for packets in %s/packets.bin\n", FIFO_DIR);
    fflush(stdout);

    initialized = 1;
    return 0;
}

// Check for new packets from file
int dpi_fifo_poll() {
    char filename[256];
    struct stat st;
    FILE *fp;
    int count;
    int i;

    if (!initialized) return 0;

    snprintf(filename, sizeof(filename), "%s/packets.bin", FIFO_DIR);

    // Check if file exists and has new data
    if (stat(filename, &st) != 0) {
        return 0;  // File doesn't exist yet
    }

    if (st.st_size <= file_pos) {
        return 0;  // No new data
    }

    // Open and read new packets
    fp = fopen(filename, "rb");
    if (!fp) return 0;

    fseek(fp, file_pos, SEEK_SET);

    // Read packet count (4 bytes)
    if (fread(&count, sizeof(int), 1, fp) != 1) {
        fclose(fp);
        return 0;
    }

    printf("[DPI] Found %d packets in file\n", count);
    fflush(stdout);

    for (i = 0; i < count; i++) {
        int length;
        if (fread(&length, sizeof(int), 1, fp) != 1) break;
        if (length <= 0 || length > MAX_PACKET_SIZE) break;
        if (packet_count >= MAX_PACKETS) break;

        if (fread(packet_buffer[packet_count], 1, length, fp) != length) break;
        packet_lengths[packet_count] = length;
        packet_count++;
    }

    file_pos = ftell(fp);
    fclose(fp);

    return count;
}

// DPI-C function: Check if packets are available
int dpi_has_packet() {
    dpi_fifo_poll();
    return (packet_read_idx < packet_count) ? 1 : 0;
}

// DPI-C function: Get next packet length
int dpi_get_packet_length() {
    if (packet_read_idx >= packet_count) return 0;
    return packet_lengths[packet_read_idx];
}

// DPI-C function: Read packet data into Verilog array
void dpi_read_packet(unsigned char *data, int max_len) {
    if (packet_read_idx >= packet_count) return;

    int len = packet_lengths[packet_read_idx];
    if (len > max_len) len = max_len;

    memcpy(data, packet_buffer[packet_read_idx], len);
    packet_read_idx++;
}

// DPI-C function: Get packet count
int dpi_get_packet_count() {
    return packet_count - packet_read_idx;
}

// DPI-C function: Cleanup
void dpi_fifo_cleanup() {
    char filename[256];
    if (pkt_file) {
        fclose(pkt_file);
        pkt_file = NULL;
    }
    snprintf(filename, sizeof(filename), "%s/packets.bin", FIFO_DIR);
    unlink(filename);
    rmdir(FIFO_DIR);
    initialized = 0;
    packet_count = 0;
    packet_read_idx = 0;
    file_pos = 0;
    printf("[DPI] FIFO cleanup done\n");
    fflush(stdout);
}
