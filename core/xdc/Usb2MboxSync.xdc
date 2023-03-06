# Copyright Till Straumann, 2023. Licensed under the EUPL-1.2 or later.
# You may obtain a copy of the license at
#   https://joinup.ec.europa.eu/collection/eupl/eupl-text-eupl-12
# This notice must not be removed.

# Set the SCOPE_TO_REF property of the XDC file to
#   'Usb2MboxSync'
# (module name) in Vivado. (Also restrict its use to
# 'implementation' in order to reduce warnings.)
#
set_max_delay -datapath_only -from [get_clocks -of_objects [get_ports clkB ]]  -through [get_pins -of_objects [get_cells B_Usb2MboxSync.b2aData_reg*] -filter {REF_PIN_NAME==Q}] [get_property PERIOD [get_clocks -of_objects [get_ports clkA]]]
#set_max_delay -datapath_only -from [get_clocks -of_objects [get_ports clkB ]] -to [get_clocks -of_objects [get_ports clkA]] -through [get_pins -of_objects [get_cells B_Usb2MboxSync.b2aData_reg*] -filter {REF_PIN_NAME==Q}] [get_property PERIOD [get_clocks -of_objects [get_ports clkA]]]

set_max_delay -datapath_only -from [get_clocks -of_objects [get_ports clkA]]  -through [get_pins -of_objects [get_cells B_Usb2MboxSync.a2bData_reg*] -filter {REF_PIN_NAME==Q}] [get_property PERIOD [get_clocks -of_objects [get_ports clkB]]]
#set_max_delay -datapath_only -from [get_clocks -of_objects [get_ports clkA]] -to [get_clocks -of_objects [get_ports clkB]] -through [get_pins -of_objects [get_cells B_Usb2MboxSync.a2bData_reg*] -filter {REF_PIN_NAME==Q}] [get_property PERIOD [get_clocks -of_objects [get_ports clkB]]]

