with open("tb/tb_mini_corundum_top.v", "r") as f:
    lines = f.readlines()

new_lines = []
for line in lines:
    if "tb_probe" in line or "module tb_probe" in line:
        break
    new_lines.append(line)

with open("tb/tb_mini_corundum_top.v", "w") as f:
    f.writelines(new_lines)
