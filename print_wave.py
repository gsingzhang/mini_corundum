import sys
with open("tb/tb_mini_corundum_top.v", "r") as f:
    lines = f.readlines()

new_lines = []
for line in lines:
    new_lines.append(line)
    if "if (dut.eth_tx_hdr_valid && dut.eth_tx_hdr_ready) begin" in line:
        pass
    if "always @(posedge clk) begin" in line:
        new_lines.append("""
        if (host_xgmii_txc != 8'hff) begin
            $display("[%0t] host_xgmii_txd: %x, txc: %x", $time, host_xgmii_txd, host_xgmii_txc);
        end
        """)
        new_lines.append("""
        if (dut_xgmii_txc != 8'hff) begin
            $display("[%0t] dut_xgmii_txd: %x, txc: %x", $time, dut_xgmii_txd, dut_xgmii_txc);
        end
        """)

with open("tb/tb_mini_corundum_top.v", "w") as f:
    f.writelines(new_lines)
