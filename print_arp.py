import sys
with open("tb/tb_mini_corundum_top.v", "r") as f:
    lines = f.readlines()

new_lines = []
for line in lines:
    if "if (dut.udp_inst.ip_complete_64_inst.arp_inst" in line or "$display(\"[%0t] DUT ARP" in line or "dut.udp_inst.ip_complete_64_inst.arp_inst.arp_eth_" in line:
        continue
    new_lines.append(line)
    if "always @(posedge clk) begin" in line:
        new_lines.append("""
        if (dut.udp_inst.ip_complete_64_inst.arp_inst.incoming_frame_valid) begin
            $display("[%0t] DUT ARP RX frame_valid! SPA=%x, TPA=%x, OPER=%x, local_ip=%x", $time, 
                dut.udp_inst.ip_complete_64_inst.arp_inst.incoming_arp_spa, 
                dut.udp_inst.ip_complete_64_inst.arp_inst.incoming_arp_tpa,
                dut.udp_inst.ip_complete_64_inst.arp_inst.incoming_arp_oper,
                dut.udp_inst.ip_complete_64_inst.arp_inst.local_ip);
        end
        if (dut.udp_inst.ip_complete_64_inst.arp_inst.outgoing_frame_valid && dut.udp_inst.ip_complete_64_inst.arp_inst.outgoing_frame_ready) begin
            $display("[%0t] DUT ARP TX frame! SPA=%x, TPA=%x, OPER=%x", $time, 
                dut.udp_inst.ip_complete_64_inst.arp_inst.outgoing_arp_spa, 
                dut.udp_inst.ip_complete_64_inst.arp_inst.outgoing_arp_tpa,
                dut.udp_inst.ip_complete_64_inst.arp_inst.outgoing_arp_oper);
        end
        """)

with open("tb/tb_mini_corundum_top.v", "w") as f:
    f.writelines(new_lines)
