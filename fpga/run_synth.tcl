open_project /home/gxzhang/gx/prj/mini_corundum/fpga/build/fpga.xpr

set_property top fpga [current_fileset]

launch_runs synth_1 -jobs 8
wait_on_run synth_1

if {[get_property STATUS [get_runs synth_1]] != "synth_design Complete!"} {
    puts "ERROR: Synthesis failed!"
    exit 1
}

puts "Synthesis completed successfully!"

open_run synth_1

report_utilization -file /home/gxzhang/gx/prj/mini_corundum/fpga/build/utilization_synth.rpt
report_timing -file /home/gxzhang/gx/prj/mini_corundum/fpga/build/timing_synth.rpt

puts "Reports generated."

exit
