# Copyright Till Straumann, 2023. Licensed under the EUPL-1.2 or later.
# You may obtain a copy of the license at
#   https://joinup.ec.europa.eu/collection/eupl/eupl-text-eupl-12
# This notice must not be removed.

# IO timing constraints (Xilinx-Vivado) when the ULPI clock is driven by the FPGA, i.e. ULPI INPUT clock mode
#
# NOTE:
#  - values in this file use Microchip USB3340 timing
#  - board trace delays are assumed to be 0.7ns (max)/0.25 ns(min) in these examples
#    and completely balanced (not 100% realistic).
#
#  - ulpiClk must be defined by user (clock at output pin that drives the ulpi clock)

# set the min. input delay to
# min(data_trace_delay + clock_trace_delay) + min. delay when data source is valid after active clock

set_input_delay -clock ulpiClk -min -add_delay 0.500 [all_fanin -flat -startpoints_only [get_pins -hier -regex {.*/din_r_reg[[][0-7][]]/D}]]
set_input_delay -clock ulpiClk -min -add_delay 0.500 [all_fanin -flat -startpoints_only [get_pins -hier -regex .*/nxt_r_reg/D]]
set_input_delay -clock ulpiClk -min -add_delay 0.500 [all_fanin -flat -startpoints_only [get_pins -hier -regex .*/dir_r_reg/D]]
set_input_delay -clock ulpiClk -min -add_delay 0.500 [all_fanin -flat -startpoints_only [get_pins -hier -regex .*/stp_i_reg/D]]

# set the max. input delay to
# max(data_trace_delay + clock_trace_delay) + max. delay when data source is valid after active clock

set_input_delay -clock ulpiClk -max -add_delay 7.20 [all_fanin -flat -startpoints_only [get_pins -hier -regex {.*/din_r_reg[[][0-7][]]/D}]]
set_input_delay -clock ulpiClk -max -add_delay 7.20 [all_fanin -flat -startpoints_only [get_pins -hier -regex .*/nxt_r_reg/D]]
set_input_delay -clock ulpiClk -max -add_delay 7.20 [all_fanin -flat -startpoints_only [get_pins -hier -regex .*/dir_r_reg/D]]
set_input_delay -clock ulpiClk -max -add_delay 7.20 [all_fanin -flat -startpoints_only [get_pins -hier -regex .*/stp_i_reg/D]]

# set the max. output delay to
#  max(data_trace_delay - clock_trace_delay) + ULPI_setup_time

# set the min. output delay to
#  min(data_trace_delay - clock_trace_delay) - ULPI_hold_time

set_output_delay -clock ulpiClk -min -add_delay -0.1500 [all_fanout -flat -endpoints_only [get_pins -hier -regex {.*/dou_r_reg[[][0-7][]]/Q}]]
set_output_delay -clock ulpiClk -max -add_delay 3.150 [all_fanout -flat -endpoints_only [get_pins -hier -regex {.*/dou_r_reg[[][0-7][]]/Q}]]

set_output_delay -clock ulpiClk -min -add_delay -0.1500 [all_fanout -flat -endpoints_only [get_pins -hier -regex .*/stp_r_reg/Q]]
set_output_delay -clock ulpiClk -max -add_delay 3.150 [all_fanout -flat -endpoints_only [get_pins -hier -regex .*/stp_r_reg/Q]]

#delay from DIR until outputs are high-z (or back on)
#note that the input delay into DIR and output delay out of the data outputs is 'included' in the max_delay
#if we're paranoid we'd set this to 1 clock cycle to avoid possible
#metastability when the turn-around cycle is latched. However, on slower
#devices at least, this does not seem possible. 2-cycles is a must!
#     = 16.667 
set_max_delay -datapath_only -from [all_fanin -flat -startpoints_only [get_pins -hier -regex .*/dir_r_reg/D]] -to [all_fanout -flat -endpoints_only [get_pins -hier -regex {.*/dou_r_reg[[][0-7][]]/Q}]] 33.333
# set_min_delay does not accept -datapath_only; furthermore set_max_delay -datapath_only marks
# a false-path for hold check (c.f. set_max_delay -help)
#set_min_delay  0.0 -datapath_only -from [all_fanin -flat -startpoints_only [get_pins -hier -regex {.*/dir_r_reg/D}]] -to [all_fanout -flat -endpoints_only [get_pins -hier -regex {.*/dou_r_reg[[][0-7][]]/Q}]]
