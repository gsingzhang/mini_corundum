// DPI-C import declarations for FIFO-based packet bridge
import "DPI-C" function int dpi_fifo_init();
import "DPI-C" function int dpi_has_packet();
import "DPI-C" function int dpi_get_packet_length();
import "DPI-C" function void dpi_read_packet(input byte data [], input int max_len);
import "DPI-C" function int dpi_get_packet_count();
import "DPI-C" function void dpi_fifo_cleanup();
