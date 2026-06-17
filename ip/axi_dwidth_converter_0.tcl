
create_ip -name axi_dwidth_converter -vendor xilinx.com -library ip -module_name axi_dwidth_converter_0

set_property -dict [list \
    CONFIG.SI_DATA_WIDTH {64} \
    CONFIG.SI_ID_WIDTH {1} \
    CONFIG.MI_DATA_WIDTH {512} \
    CONFIG.MI_ID_WIDTH {4} \
    CONFIG.READ_WRITE_MODE {READ_WRITE} \
    CONFIG.FIFO_MODE {2} \
    CONFIG.SI_PROTOCOL {AXI4} \
    CONFIG.MI_PROTOCOL {AXI4} \
    CONFIG.SYNC_RESET {0} \
] [get_ips axi_dwidth_converter_0]
