import sys
with open("tb/tb_mini_corundum_top.v", "r") as f:
    lines = f.readlines()

new_lines = []
for line in lines:
    new_lines.append(line)
    if "always @(posedge clk) begin" in line:
        new_lines.append("""
        if (dut.eth_rx_payload_axis_tvalid && dut.eth_rx_payload_axis_tready && dut.eth_rx_payload_axis_tlast) begin
            $display("[%0t] DUT RX Payload TLAST! tuser=%b", $time, dut.eth_rx_payload_axis_tuser);
        end
        """)

with open("tb/tb_mini_corundum_top.v", "w") as f:
    f.writelines(new_lines)
