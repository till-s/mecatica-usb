# Zybo PMOD JB1_P
set_property PACKAGE_PIN T20 [get_ports ulpiStp]
# Zybo PMOD JB1_N
set_property PACKAGE_PIN U20 [get_ports ulpiRstb]
# Zybo PMOD JB2_P
set_property PACKAGE_PIN V20 [get_ports ulpiDir]
# Zybo PMOD JB2_N
#set_property PACKAGE_PIN W20 [get_ports {JB2_N}]
# Zybo PMOD JB3_P
set_property PACKAGE_PIN Y18 [get_ports ulpiClk]
# Zybo PMOD JB3_N
#set_property PACKAGE_PIN Y19 [get_ports {JB3_N}]
# Zybo PMOD JB4_P
set_property PACKAGE_PIN W18 [get_ports ulpiNxt]
# Zybo PMOD JB4_N
#set_property PACKAGE_PIN W19 [get_ports {JB4_N}]

# Zybo PMOD JC1_P
set_property PACKAGE_PIN V15 [get_ports {ulpiDat[0]}]
# Zybo PMOD JC1_N
#set_property PACKAGE_PIN W15 [get_ports {JC1_N}]
# Zybo PMOD JC2_P
set_property PACKAGE_PIN T11 [get_ports {ulpiDat[2]}]
# Zybo PMOD JC2_N
#set_property PACKAGE_PIN T10 [get_ports {JC2_N}]
# Zybo PMOD JC3_P
set_property PACKAGE_PIN W14 [get_ports {ulpiDat[1]}]
# Zybo PMOD JC3_N
#set_property PACKAGE_PIN Y14 [get_ports {JC3_N}]
# Zybo PMOD JC4_P
set_property PACKAGE_PIN T12 [get_ports {ulpiDat[3]}]
# Zybo PMOD JC4_N
#set_property PACKAGE_PIN U12 [get_ports {JC4_N}]

# Zybo PMOD JD1_P
set_property PACKAGE_PIN T14 [get_ports {ulpiDat[5]}]
# Zybo PMOD JD1_N
#set_property PACKAGE_PIN T15 [get_ports {JD1_N}]
# Zybo PMOD JD2_P
set_property PACKAGE_PIN P14 [get_ports {ulpiDat[7]}]
# Zybo PMOD JD2_N
#set_property PACKAGE_PIN R14 [get_ports {JD2_N}]
# Zybo PMOD JD3_P
set_property PACKAGE_PIN U14 [get_ports {ulpiDat[4]}]
# Zybo PMOD JD3_N
#set_property PACKAGE_PIN U15 [get_ports {JD3_N}]
# Zybo PMOD JD4_P
set_property PACKAGE_PIN V17 [get_ports {ulpiDat[6]}]
# Zybo PMOD JD4_N
#set_property PACKAGE_PIN V18 [get_ports {JD4_N}]

set_property IOSTANDARD LVCMOS33 [get_ports -regex ulpi.*]

#set_property PACKAGE_PIN H16 [get_ports {HDMI_CLK_P}]
#set_property IOSTANDARD LVCMOS33 [get_ports {HDMI_CLK_P}]

set_property PACKAGE_PIN M14 [get_ports {LED[0]}]
set_property PACKAGE_PIN M15 [get_ports {LED[1]}]
set_property PACKAGE_PIN G14 [get_ports {LED[2]}]
set_property PACKAGE_PIN D18 [get_ports {LED[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports -regex {LED[[][0-9][]]}]

set_property PACKAGE_PIN T16 [get_ports {SW[3]}]
set_property PACKAGE_PIN W13 [get_ports {SW[2]}]
set_property PACKAGE_PIN P15 [get_ports {SW[1]}]
set_property PACKAGE_PIN G15 [get_ports {SW[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports -regex {SW[[][0-9][]]}]


set_property PACKAGE_PIN L16 [get_ports ethClk]
set_property IOSTANDARD LVCMOS33 [get_ports ethClk]
create_clock -period 8.000 -name ethClk [get_ports ethClk]






