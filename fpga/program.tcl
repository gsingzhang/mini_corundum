open_hw_manager
connect_hw_server -allow_non_jtag
open_hw_target
current_hw_device [lindex [get_hw_devices] 0]
set_property PROGRAM.FILE {d:/gx/study/corundum/mini_corundum/fpga/fpga.bit} [current_hw_device]
program_hw_devices [current_hw_device]
close_hw_manager
