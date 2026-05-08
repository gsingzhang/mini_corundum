import sys
with open("tb/tb_mini_corundum_top.v", "r") as f:
    lines = f.readlines()

new_lines = []
for line in lines:
    if "dut.udp_inst" in line and "display" in line:
        continue
    if "dut_xgmii_txc" in line and "display" in line:
        continue
    new_lines.append(line)

with open("tb/tb_mini_corundum_top.v", "w") as f:
    f.writelines(new_lines)
