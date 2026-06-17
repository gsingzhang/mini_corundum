open_project /home/gxzhang/gx/prj/mini_corundum/fpga/build/fpga.xpr

set_property top fpga [current_fileset]

reset_run synth_1
launch_runs synth_1 -jobs 8
wait_on_run synth_1

if {[get_property STATUS [get_runs synth_1]] != "synth_design Complete!"} {
    puts "ERROR: Synthesis failed!"
    exit 1
}

puts "Synthesis completed successfully!"

launch_runs impl_1 -jobs 8
wait_on_run impl_1

if {[get_property STATUS [get_runs impl_1]] != "route_design Complete!"} {
    puts "ERROR: Implementation failed!"
    exit 1
}

puts "Implementation completed successfully!"

open_run impl_1

report_utilization -file /home/gxzhang/gx/prj/mini_corundum/fpga/build/utilization_impl.rpt
report_timing -file /home/gxzhang/gx/prj/mini_corundum/fpga/build/timing_impl.rpt

puts "Reports generated."

exit
