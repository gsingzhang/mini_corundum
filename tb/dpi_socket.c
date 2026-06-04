// DPI-C socket bridge for Python co-simulation
// This file provides DPI-C functions for SystemVerilog to receive packets
// from Python via Unix domain sockets

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <errno.h>
#include <fcntl.h>

#define SOCKET_PATH "/tmp/ludp_dpi_socket"
#define MAX_PACKET_SIZE 9216
#define MAX_PACKETS 256

static int server_fd = -1;
static int client_fd = -1;
static int initialized = 0;

// Packet buffer
static unsigned char packet_buffer[MAX_PACKETS][MAX_PACKET_SIZE];
static int packet_lengths[MAX_PACKETS];
static int packet_count = 0;
static int packet_read_idx = 0;

// Initialize socket server
int dpi_socket_init() {
    struct sockaddr_un addr;
    int flags;

    if (initialized) return 0;

    // Remove old socket file
    unlink(SOCKET_PATH);

    // Create Unix domain socket
    server_fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (server_fd < 0) {
        perror("socket");
        return -1;
    }

    // Set non-blocking mode
    flags = fcntl(server_fd, F_GETFL, 0);
    fcntl(server_fd, F_SETFL, flags | O_NONBLOCK);

    memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;
    strncpy(addr.sun_path, SOCKET_PATH, sizeof(addr.sun_path) - 1);

    if (bind(server_fd, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
        perror("bind");
        close(server_fd);
        return -1;
    }

    if (listen(server_fd, 1) < 0) {
        perror("listen");
        close(server_fd);
        return -1;
    }

    printf("[DPI] Socket server listening on %s\n", SOCKET_PATH);
    fflush(stdout);

    initialized = 1;
    return 0;
}

// Accept connection from Python client
int dpi_socket_accept() {
    struct sockaddr_un addr;
    socklen_t len = sizeof(addr);
    int flags;

    if (client_fd >= 0) return 0;  // Already connected

    client_fd = accept(server_fd, (struct sockaddr *)&addr, &len);
    if (client_fd < 0) {
        if (errno == EAGAIN || errno == EWOULDBLOCK) {
            return -1;  // No connection yet
        }
        perror("accept");
        return -1;
    }

    // Set non-blocking mode for client
    flags = fcntl(client_fd, F_GETFL, 0);
    fcntl(client_fd, F_SETFL, flags | O_NONBLOCK);

    printf("[DPI] Python client connected\n");
    fflush(stdout);
    return 0;
}

// Receive packets from Python (non-blocking)
int dpi_socket_receive() {
    int result;
    unsigned char header[4];

    if (!initialized) return 0;
    if (client_fd < 0) {
        dpi_socket_accept();
        return 0;
    }

    // Try to read packet header (4 bytes: length as uint32)
    result = recv(client_fd, header, 4, MSG_DONTWAIT | MSG_PEEK);
    if (result < 0) {
        if (errno == EAGAIN || errno == EWOULDBLOCK) {
            return 0;  // No data available
        }
        if (errno == ECONNRESET || errno == EPIPE) {
            printf("[DPI] Client disconnected\n");
            close(client_fd);
            client_fd = -1;
            return 0;
        }
        perror("recv peek");
        return 0;
    }
    if (result < 4) return 0;  // Not enough data for header

    int length = header[0] | (header[1] << 8) | (header[2] << 16) | (header[3] << 24);
    if (length <= 0 || length > MAX_PACKET_SIZE) {
        printf("[DPI] Invalid packet length: %d\n", length);
        // Consume the bad header
        recv(client_fd, header, 4, MSG_DONTWAIT);
        return 0;
    }

    if (packet_count >= MAX_PACKETS) {
        printf("[DPI] Packet buffer full\n");
        return 0;
    }

    // Read header + packet data
    unsigned char *buf = malloc(4 + length);
    result = recv(client_fd, buf, 4 + length, MSG_DONTWAIT);
    if (result < 4 + length) {
        free(buf);
        return 0;  // Not enough data yet
    }

    // Copy packet data to buffer
    memcpy(packet_buffer[packet_count], buf + 4, length);
    packet_lengths[packet_count] = length;
    packet_count++;

    free(buf);
    return 1;
}

// DPI-C function: Check if packets are available
int dpi_has_packet() {
    dpi_socket_receive();
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
void dpi_socket_cleanup() {
    if (client_fd >= 0) {
        close(client_fd);
        client_fd = -1;
    }
    if (server_fd >= 0) {
        close(server_fd);
        server_fd = -1;
    }
    unlink(SOCKET_PATH);
    initialized = 0;
    packet_count = 0;
    packet_read_idx = 0;
    printf("[DPI] Socket cleanup done\n");
    fflush(stdout);
}
