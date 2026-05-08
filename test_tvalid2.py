import sys
with open("tb/tb_mini_corundum_top.v", "r") as f:
    lines = f.readlines()

new_lines = []
for line in lines:
    if "tb_probe" in line:
        continue
    new_lines.append(line)

with open("tb/tb_mini_corundum_top.v", "w") as f:
    f.writelines(new_lines)

with open("tb/tb_mini_corundum_top.v", "a") as f:
    f.write("""
module tb_probe7;
    initial begin
        forever @(posedge tb_mini_corundum_top.clk) begin
            if (tb_mini_corundum_top.dut.eth_rx_payload_axis_tvalid) begin
                $display("[%0t] DUT payload valid! tready=%b, tlast=%b, tuser=%b, tdata=%x", $time, tb_mini_corundum_top.dut.eth_rx_payload_axis_tready, tb_mini_corundum_top.dut.eth_rx_payload_axis_tlast, tb_mini_corundum_top.dut.eth_rx_payload_axis_tuser, tb_mini_corundum_top.dut.eth_rx_payload_axis_tdata);
            end
        end
    end
endmodule
""")
