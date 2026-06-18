create_ip -name axi_clock_converter -vendor xilinx.com -library ip -module_name axi_clock_converter_0

set_property -dict [list \
    CONFIG.PROTOCOL {AXI4} \
    CONFIG.ADDR_WIDTH {32} \
    CONFIG.DATA_WIDTH {512} \
    CONFIG.ID_WIDTH {4} \
    CONFIG.AWUSER_WIDTH {0} \
    CONFIG.ARUSER_WIDTH {0} \
    CONFIG.WUSER_WIDTH {0} \
    CONFIG.RUSER_WIDTH {0} \
    CONFIG.BUSER_WIDTH {0} \
    CONFIG.SYNCHRONOUS_CLKS {false} \
] [get_ips axi_clock_converter_0]
