# XDC constraints for the Xilinx ZCU106 board
# part: xczu7ev-ffvc1156-2-e

# General configuration
set_property BITSTREAM.GENERAL.COMPRESS true           [current_design]

# System clocks
# 125 MHz
set_property -dict {LOC H9  IOSTANDARD LVDS} [get_ports clk_125mhz_p]
set_property -dict {LOC G9  IOSTANDARD LVDS} [get_ports clk_125mhz_n]
create_clock -period 8.000 -name clk_125mhz [get_ports clk_125mhz_p]

# LEDs
set_property -dict {LOC AL11 IOSTANDARD LVCMOS12 SLEW SLOW DRIVE 8} [get_ports {led[0]}]
set_property -dict {LOC AL13 IOSTANDARD LVCMOS12 SLEW SLOW DRIVE 8} [get_ports {led[1]}]
set_property -dict {LOC AK13 IOSTANDARD LVCMOS12 SLEW SLOW DRIVE 8} [get_ports {led[2]}]
set_property -dict {LOC AE15 IOSTANDARD LVCMOS12 SLEW SLOW DRIVE 8} [get_ports {led[3]}]
set_property -dict {LOC AM8  IOSTANDARD LVCMOS12 SLEW SLOW DRIVE 8} [get_ports {led[4]}]
set_property -dict {LOC AM9  IOSTANDARD LVCMOS12 SLEW SLOW DRIVE 8} [get_ports {led[5]}]
set_property -dict {LOC AM10 IOSTANDARD LVCMOS12 SLEW SLOW DRIVE 8} [get_ports {led[6]}]
set_property -dict {LOC AM11 IOSTANDARD LVCMOS12 SLEW SLOW DRIVE 8} [get_ports {led[7]}]

set_false_path -to [get_ports {led[*]}]
set_output_delay 0 [get_ports {led[*]}]

# Reset button
set_property -dict {LOC G13  IOSTANDARD LVCMOS12} [get_ports reset]

set_false_path -from [get_ports {reset}]
set_input_delay 0 [get_ports {reset}]

# Push buttons
set_property -dict {LOC AG13 IOSTANDARD LVCMOS12} [get_ports btnu]
set_property -dict {LOC AK12 IOSTANDARD LVCMOS12} [get_ports btnl]
set_property -dict {LOC AP20 IOSTANDARD LVCMOS12} [get_ports btnd]
set_property -dict {LOC AC14 IOSTANDARD LVCMOS12} [get_ports btnr]
set_property -dict {LOC AL10 IOSTANDARD LVCMOS12} [get_ports btnc]

set_false_path -from [get_ports {btnu btnl btnd btnr btnc}]
set_input_delay 0 [get_ports {btnu btnl btnd btnr btnc}]

# DIP switches
set_property -dict {LOC A17  IOSTANDARD LVCMOS18} [get_ports {sw[0]}]
set_property -dict {LOC A16  IOSTANDARD LVCMOS18} [get_ports {sw[1]}]
set_property -dict {LOC B16  IOSTANDARD LVCMOS18} [get_ports {sw[2]}]
set_property -dict {LOC B15  IOSTANDARD LVCMOS18} [get_ports {sw[3]}]
set_property -dict {LOC A15  IOSTANDARD LVCMOS18} [get_ports {sw[4]}]
set_property -dict {LOC A14  IOSTANDARD LVCMOS18} [get_ports {sw[5]}]
set_property -dict {LOC B14  IOSTANDARD LVCMOS18} [get_ports {sw[6]}]
set_property -dict {LOC B13  IOSTANDARD LVCMOS18} [get_ports {sw[7]}]

set_false_path -from [get_ports {sw[*]}]
set_input_delay 0 [get_ports {sw[*]}]

# UART
set_property -dict {LOC AL17 IOSTANDARD LVCMOS12 SLEW SLOW DRIVE 8} [get_ports uart_txd]
set_property -dict {LOC AH17 IOSTANDARD LVCMOS12} [get_ports uart_rxd]
set_property -dict {LOC AM15 IOSTANDARD LVCMOS12} [get_ports uart_rts]
set_property -dict {LOC AP17 IOSTANDARD LVCMOS12 SLEW SLOW DRIVE 8} [get_ports uart_cts]

set_false_path -to [get_ports {uart_txd uart_cts}]
set_output_delay 0 [get_ports {uart_txd uart_cts}]
set_false_path -from [get_ports {uart_rxd uart_rts}]
set_input_delay 0 [get_ports {uart_rxd uart_rts}]

# I2C interfaces
#set_property -dict {LOC AE19 IOSTANDARD LVCMOS12 SLEW SLOW DRIVE 8} [get_ports i2c0_scl]
#set_property -dict {LOC AH23 IOSTANDARD LVCMOS12 SLEW SLOW DRIVE 8} [get_ports i2c0_sda]
#set_property -dict {LOC AH19 IOSTANDARD LVCMOS12 SLEW SLOW DRIVE 8} [get_ports i2c1_scl]
#set_property -dict {LOC AL21 IOSTANDARD LVCMOS12 SLEW SLOW DRIVE 8} [get_ports i2c1_sda]

#set_false_path -to [get_ports {i2c1_sda i2c1_scl}]
#set_output_delay 0 [get_ports {i2c1_sda i2c1_scl}]
#set_false_path -from [get_ports {i2c1_sda i2c1_scl}]
#set_input_delay 0 [get_ports {i2c1_sda i2c1_scl}]

# SFP+ Interface
set_property -dict {LOC AA2 } [get_ports sfp0_rx_p] ;# MGTHRXP2_225 GTHE4_CHANNEL_X0Y10 / GTHE4_COMMON_X0Y2
set_property -dict {LOC AA1 } [get_ports sfp0_rx_n] ;# MGTHRXN2_225 GTHE4_CHANNEL_X0Y10 / GTHE4_COMMON_X0Y2
set_property -dict {LOC Y4  } [get_ports sfp0_tx_p] ;# MGTHTXP2_225 GTHE4_CHANNEL_X0Y10 / GTHE4_COMMON_X0Y2
set_property -dict {LOC Y3  } [get_ports sfp0_tx_n] ;# MGTHTXN2_225 GTHE4_CHANNEL_X0Y10 / GTHE4_COMMON_X0Y2
set_property -dict {LOC W2  } [get_ports sfp1_rx_p] ;# MGTHRXP3_225 GTHE4_CHANNEL_X0Y11 / GTHE4_COMMON_X0Y2
set_property -dict {LOC W1  } [get_ports sfp1_rx_n] ;# MGTHRXN3_225 GTHE4_CHANNEL_X0Y11 / GTHE4_COMMON_X0Y2
set_property -dict {LOC W6  } [get_ports sfp1_tx_p] ;# MGTHTXP3_225 GTHE4_CHANNEL_X0Y11 / GTHE4_COMMON_X0Y2
set_property -dict {LOC W5  } [get_ports sfp1_tx_n] ;# MGTHTXN3_225 GTHE4_CHANNEL_X0Y11 / GTHE4_COMMON_X0Y2
set_property -dict {LOC U10 } [get_ports sfp_mgt_refclk_0_p] ;# MGTREFCLK1P_226 from U56 SI570 via U51 SI53340
set_property -dict {LOC U9  } [get_ports sfp_mgt_refclk_0_n] ;# MGTREFCLK1N_226 from U56 SI570 via U51 SI53340
#set_property -dict {LOC W10 } [get_ports sfp_mgt_refclk_1_p] ;# MGTREFCLK1P_225 from U20 CKOUT2 SI5328
#set_property -dict {LOC W9  } [get_ports sfp_mgt_refclk_1_n] ;# MGTREFCLK1N_225 from U20 CKOUT2 SI5328
#set_property -dict {LOC H11 IOSTANDARD LVDS} [get_ports sfp_recclk_p] ;# to U20 CKIN1 SI5328
#set_property -dict {LOC G11 IOSTANDARD LVDS} [get_ports sfp_recclk_n] ;# to U20 CKIN1 SI5328
set_property -dict {LOC AE22 IOSTANDARD LVCMOS12 SLEW SLOW DRIVE 8} [get_ports sfp0_tx_disable_b]
set_property -dict {LOC AF20 IOSTANDARD LVCMOS12 SLEW SLOW DRIVE 8} [get_ports sfp1_tx_disable_b]

# 156.25 MHz MGT reference clock
create_clock -period 6.400 -name sfp_mgt_refclk_0 [get_ports sfp_mgt_refclk_0_p]

set_false_path -to [get_ports {sfp0_tx_disable_b sfp1_tx_disable_b}]
set_output_delay 0 [get_ports {sfp0_tx_disable_b sfp1_tx_disable_b}]

# DDR4 SDRAM (ZCU106 PL-side)
# 4x MT40A256M16GE-075E, 64-bit, 2 ranks
# System clock: 300 MHz Si570
set_property -dict {LOC AH12 IOSTANDARD DIFF_SSTL12} [get_ports ddr4_sys_clk_p]
set_property -dict {LOC AJ12 IOSTANDARD DIFF_SSTL12} [get_ports ddr4_sys_clk_n]

set_property -dict {LOC AK9  IOSTANDARD SSTL12_DCI     } [get_ports {ddr4_adr[0]}]
set_property -dict {LOC AG11 IOSTANDARD SSTL12_DCI     } [get_ports {ddr4_adr[1]}]
set_property -dict {LOC AJ10 IOSTANDARD SSTL12_DCI     } [get_ports {ddr4_adr[2]}]
set_property -dict {LOC AL8  IOSTANDARD SSTL12_DCI     } [get_ports {ddr4_adr[3]}]
set_property -dict {LOC AK10 IOSTANDARD SSTL12_DCI     } [get_ports {ddr4_adr[4]}]
set_property -dict {LOC AH8  IOSTANDARD SSTL12_DCI     } [get_ports {ddr4_adr[5]}]
set_property -dict {LOC AJ9  IOSTANDARD SSTL12_DCI     } [get_ports {ddr4_adr[6]}]
set_property -dict {LOC AG8  IOSTANDARD SSTL12_DCI     } [get_ports {ddr4_adr[7]}]
set_property -dict {LOC AH9  IOSTANDARD SSTL12_DCI     } [get_ports {ddr4_adr[8]}]
set_property -dict {LOC AG10 IOSTANDARD SSTL12_DCI     } [get_ports {ddr4_adr[9]}]
set_property -dict {LOC AH13 IOSTANDARD SSTL12_DCI     } [get_ports {ddr4_adr[10]}]
set_property -dict {LOC AG9  IOSTANDARD SSTL12_DCI     } [get_ports {ddr4_adr[11]}]
set_property -dict {LOC AM13 IOSTANDARD SSTL12_DCI     } [get_ports {ddr4_adr[12]}]
set_property -dict {LOC AF8  IOSTANDARD SSTL12_DCI     } [get_ports {ddr4_adr[13]}]
set_property -dict {LOC AC12 IOSTANDARD SSTL12_DCI     } [get_ports {ddr4_adr[14]}]
set_property -dict {LOC AE12 IOSTANDARD SSTL12_DCI     } [get_ports {ddr4_adr[15]}]
set_property -dict {LOC AF11 IOSTANDARD SSTL12_DCI     } [get_ports {ddr4_adr[16]}]
set_property -dict {LOC AK8  IOSTANDARD SSTL12_DCI     } [get_ports {ddr4_ba[0]}]
set_property -dict {LOC AL12 IOSTANDARD SSTL12_DCI     } [get_ports {ddr4_ba[1]}]
set_property -dict {LOC AE14 IOSTANDARD SSTL12_DCI     } [get_ports {ddr4_bg}]
set_property -dict {LOC AH11 IOSTANDARD DIFF_SSTL12_DCI} [get_ports {ddr4_ck_t}]
set_property -dict {LOC AJ11 IOSTANDARD DIFF_SSTL12_DCI} [get_ports {ddr4_ck_c}]
set_property -dict {LOC AB13 IOSTANDARD SSTL12_DCI     } [get_ports ddr4_cke]
set_property -dict {LOC AD12 IOSTANDARD SSTL12_DCI     } [get_ports ddr4_cs_n]
set_property -dict {LOC AD14 IOSTANDARD SSTL12_DCI     } [get_ports ddr4_act_n]
set_property -dict {LOC AF10 IOSTANDARD SSTL12_DCI     } [get_ports ddr4_odt]
set_property -dict {LOC AF12 IOSTANDARD LVCMOS12       } [get_ports ddr4_reset_n]

set_property -dict {LOC AF16 IOSTANDARD POD12_DCI      } [get_ports {ddr4_dq[0]}]
set_property -dict {LOC AF18 IOSTANDARD POD12_DCI      } [get_ports {ddr4_dq[1]}]
set_property -dict {LOC AG15 IOSTANDARD POD12_DCI      } [get_ports {ddr4_dq[2]}]
set_property -dict {LOC AF17 IOSTANDARD POD12_DCI      } [get_ports {ddr4_dq[3]}]
set_property -dict {LOC AF15 IOSTANDARD POD12_DCI      } [get_ports {ddr4_dq[4]}]
set_property -dict {LOC AG18 IOSTANDARD POD12_DCI      } [get_ports {ddr4_dq[5]}]
set_property -dict {LOC AG14 IOSTANDARD POD12_DCI      } [get_ports {ddr4_dq[6]}]
set_property -dict {LOC AE17 IOSTANDARD POD12_DCI      } [get_ports {ddr4_dq[7]}]
set_property -dict {LOC AA14 IOSTANDARD POD12_DCI      } [get_ports {ddr4_dq[8]}]
set_property -dict {LOC AC16 IOSTANDARD POD12_DCI      } [get_ports {ddr4_dq[9]}]
set_property -dict {LOC AB15 IOSTANDARD POD12_DCI      } [get_ports {ddr4_dq[10]}]
set_property -dict {LOC AD16 IOSTANDARD POD12_DCI      } [get_ports {ddr4_dq[11]}]
set_property -dict {LOC AB16 IOSTANDARD POD12_DCI      } [get_ports {ddr4_dq[12]}]
set_property -dict {LOC AC17 IOSTANDARD POD12_DCI      } [get_ports {ddr4_dq[13]}]
set_property -dict {LOC AB14 IOSTANDARD POD12_DCI      } [get_ports {ddr4_dq[14]}]
set_property -dict {LOC AD17 IOSTANDARD POD12_DCI      } [get_ports {ddr4_dq[15]}]
set_property -dict {LOC AH14 IOSTANDARD DIFF_POD12_DCI } [get_ports {ddr4_dqs_t[0]}]
set_property -dict {LOC AJ14 IOSTANDARD DIFF_POD12_DCI } [get_ports {ddr4_dqs_c[0]}]
set_property -dict {LOC AA16 IOSTANDARD DIFF_POD12_DCI } [get_ports {ddr4_dqs_t[1]}]
set_property -dict {LOC AA15 IOSTANDARD DIFF_POD12_DCI } [get_ports {ddr4_dqs_c[1]}]
set_property -dict {LOC AH18 IOSTANDARD POD12_DCI      } [get_ports {ddr4_dm_dbi_n[0]}]
set_property -dict {LOC AD15 IOSTANDARD POD12_DCI      } [get_ports {ddr4_dm_dbi_n[1]}]

set_property -dict {LOC AJ16 IOSTANDARD POD12_DCI      } [get_ports {ddr4_dq[16]}]
set_property -dict {LOC AJ17 IOSTANDARD POD12_DCI      } [get_ports {ddr4_dq[17]}]
set_property -dict {LOC AL15 IOSTANDARD POD12_DCI      } [get_ports {ddr4_dq[18]}]
set_property -dict {LOC AK17 IOSTANDARD POD12_DCI      } [get_ports {ddr4_dq[19]}]
set_property -dict {LOC AJ15 IOSTANDARD POD12_DCI      } [get_ports {ddr4_dq[20]}]
set_property -dict {LOC AK18 IOSTANDARD POD12_DCI      } [get_ports {ddr4_dq[21]}]
set_property -dict {LOC AL16 IOSTANDARD POD12_DCI      } [get_ports {ddr4_dq[22]}]
set_property -dict {LOC AL18 IOSTANDARD POD12_DCI      } [get_ports {ddr4_dq[23]}]
set_property -dict {LOC AP13 IOSTANDARD POD12_DCI      } [get_ports {ddr4_dq[24]}]
set_property -dict {LOC AP16 IOSTANDARD POD12_DCI      } [get_ports {ddr4_dq[25]}]
set_property -dict {LOC AP15 IOSTANDARD POD12_DCI      } [get_ports {ddr4_dq[26]}]
set_property -dict {LOC AN16 IOSTANDARD POD12_DCI      } [get_ports {ddr4_dq[27]}]
set_property -dict {LOC AN13 IOSTANDARD POD12_DCI      } [get_ports {ddr4_dq[28]}]
set_property -dict {LOC AM18 IOSTANDARD POD12_DCI      } [get_ports {ddr4_dq[29]}]
set_property -dict {LOC AN17 IOSTANDARD POD12_DCI      } [get_ports {ddr4_dq[30]}]
set_property -dict {LOC AN18 IOSTANDARD POD12_DCI      } [get_ports {ddr4_dq[31]}]
set_property -dict {LOC AK15 IOSTANDARD DIFF_POD12_DCI } [get_ports {ddr4_dqs_t[2]}]
set_property -dict {LOC AK14 IOSTANDARD DIFF_POD12_DCI } [get_ports {ddr4_dqs_c[2]}]
set_property -dict {LOC AM14 IOSTANDARD DIFF_POD12_DCI } [get_ports {ddr4_dqs_t[3]}]
set_property -dict {LOC AN14 IOSTANDARD DIFF_POD12_DCI } [get_ports {ddr4_dqs_c[3]}]
set_property -dict {LOC AM16 IOSTANDARD POD12_DCI      } [get_ports {ddr4_dm_dbi_n[2]}]
set_property -dict {LOC AP18 IOSTANDARD POD12_DCI      } [get_ports {ddr4_dm_dbi_n[3]}]

set_property -dict {LOC AB19 IOSTANDARD POD12_DCI      } [get_ports {ddr4_dq[32]}]
set_property -dict {LOC AD19 IOSTANDARD POD12_DCI      } [get_ports {ddr4_dq[33]}]
set_property -dict {LOC AC18 IOSTANDARD POD12_DCI      } [get_ports {ddr4_dq[34]}]
set_property -dict {LOC AC19 IOSTANDARD POD12_DCI      } [get_ports {ddr4_dq[35]}]
set_property -dict {LOC AA20 IOSTANDARD POD12_DCI      } [get_ports {ddr4_dq[36]}]
set_property -dict {LOC AE20 IOSTANDARD POD12_DCI      } [get_ports {ddr4_dq[37]}]
set_property -dict {LOC AA19 IOSTANDARD POD12_DCI      } [get_ports {ddr4_dq[38]}]
set_property -dict {LOC AD20 IOSTANDARD POD12_DCI      } [get_ports {ddr4_dq[39]}]
set_property -dict {LOC AF22 IOSTANDARD POD12_DCI      } [get_ports {ddr4_dq[40]}]
set_property -dict {LOC AH21 IOSTANDARD POD12_DCI      } [get_ports {ddr4_dq[41]}]
set_property -dict {LOC AG19 IOSTANDARD POD12_DCI      } [get_ports {ddr4_dq[42]}]
set_property -dict {LOC AG21 IOSTANDARD POD12_DCI      } [get_ports {ddr4_dq[43]}]
set_property -dict {LOC AE24 IOSTANDARD POD12_DCI      } [get_ports {ddr4_dq[44]}]
set_property -dict {LOC AG20 IOSTANDARD POD12_DCI      } [get_ports {ddr4_dq[45]}]
set_property -dict {LOC AE23 IOSTANDARD POD12_DCI      } [get_ports {ddr4_dq[46]}]
set_property -dict {LOC AF21 IOSTANDARD POD12_DCI      } [get_ports {ddr4_dq[47]}]
set_property -dict {LOC AA18 IOSTANDARD DIFF_POD12_DCI } [get_ports {ddr4_dqs_t[4]}]
set_property -dict {LOC AB18 IOSTANDARD DIFF_POD12_DCI } [get_ports {ddr4_dqs_c[4]}]
set_property -dict {LOC AF23 IOSTANDARD DIFF_POD12_DCI } [get_ports {ddr4_dqs_t[5]}]
set_property -dict {LOC AG23 IOSTANDARD DIFF_POD12_DCI } [get_ports {ddr4_dqs_c[5]}]
set_property -dict {LOC AE18 IOSTANDARD POD12_DCI      } [get_ports {ddr4_dm_dbi_n[4]}]
set_property -dict {LOC AH22 IOSTANDARD POD12_DCI      } [get_ports {ddr4_dm_dbi_n[5]}]

set_property -dict {LOC AL22 IOSTANDARD POD12_DCI      } [get_ports {ddr4_dq[48]}]
set_property -dict {LOC AJ22 IOSTANDARD POD12_DCI      } [get_ports {ddr4_dq[49]}]
set_property -dict {LOC AL23 IOSTANDARD POD12_DCI      } [get_ports {ddr4_dq[50]}]
set_property -dict {LOC AJ21 IOSTANDARD POD12_DCI      } [get_ports {ddr4_dq[51]}]
set_property -dict {LOC AK20 IOSTANDARD POD12_DCI      } [get_ports {ddr4_dq[52]}]
set_property -dict {LOC AJ19 IOSTANDARD POD12_DCI      } [get_ports {ddr4_dq[53]}]
set_property -dict {LOC AK19 IOSTANDARD POD12_DCI      } [get_ports {ddr4_dq[54]}]
set_property -dict {LOC AJ20 IOSTANDARD POD12_DCI      } [get_ports {ddr4_dq[55]}]
set_property -dict {LOC AP22 IOSTANDARD POD12_DCI      } [get_ports {ddr4_dq[56]}]
set_property -dict {LOC AN22 IOSTANDARD POD12_DCI      } [get_ports {ddr4_dq[57]}]
set_property -dict {LOC AP21 IOSTANDARD POD12_DCI      } [get_ports {ddr4_dq[58]}]
set_property -dict {LOC AP23 IOSTANDARD POD12_DCI      } [get_ports {ddr4_dq[59]}]
set_property -dict {LOC AM19 IOSTANDARD POD12_DCI      } [get_ports {ddr4_dq[60]}]
set_property -dict {LOC AM23 IOSTANDARD POD12_DCI      } [get_ports {ddr4_dq[61]}]
set_property -dict {LOC AN19 IOSTANDARD POD12_DCI      } [get_ports {ddr4_dq[62]}]
set_property -dict {LOC AN23 IOSTANDARD POD12_DCI      } [get_ports {ddr4_dq[63]}]
set_property -dict {LOC AK22 IOSTANDARD DIFF_POD12_DCI } [get_ports {ddr4_dqs_t[6]}]
set_property -dict {LOC AK23 IOSTANDARD DIFF_POD12_DCI } [get_ports {ddr4_dqs_c[6]}]
set_property -dict {LOC AM21 IOSTANDARD DIFF_POD12_DCI } [get_ports {ddr4_dqs_t[7]}]
set_property -dict {LOC AN21 IOSTANDARD DIFF_POD12_DCI } [get_ports {ddr4_dqs_c[7]}]
set_property -dict {LOC AL21 IOSTANDARD POD12_DCI      } [get_ports {ddr4_dm_dbi_n[6]}]
set_property -dict {LOC AM22 IOSTANDARD POD12_DCI      } [get_ports {ddr4_dm_dbi_n[7]}]
