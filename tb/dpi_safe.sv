// Safe DPI-C import declarations - scalar types only
import "DPI-C" function int dpi_packet_available();
import "DPI-C" function int dpi_get_length();
import "DPI-C" function int dpi_get_byte(input int idx);
import "DPI-C" function void dpi_next_packet();
import "DPI-C" function void dpi_reset_packets();
import "DPI-C" function int dpi_get_packet_idx();
import "DPI-C" function int dpi_get_total_packets();
