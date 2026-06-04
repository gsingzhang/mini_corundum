// DPI-C import declarations for socket bridge
// This file provides SystemVerilog interface to the C socket bridge

import "DPI-C" function int dpi_socket_init();
import "DPI-C" function int dpi_has_packet();
import "DPI-C" function int dpi_get_packet_length();
import "DPI-C" function void dpi_read_packet(input byte data [], input int max_len);
import "DPI-C" function int dpi_get_packet_count();
import "DPI-C" function void dpi_socket_cleanup();
