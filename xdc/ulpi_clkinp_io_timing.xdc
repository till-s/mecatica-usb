# Copyright Till Straumann, 2023. Licensed under the EUPL-1.2 or later.
# You may obtain a copy of the license at
#   https://joinup.ec.europa.eu/collection/eupl/eupl-text-eupl-12
# This notice must not be removed.

# IO timing constraints (Xilinx-Vivado) when the ULPI clock is driven by the FPGA, i.e. ULPI INPUT clock mode
#
# NOTE:
#  - values in this file reflect ULPI std; it is likely that modern transceivers have
#    relaxed values; check the data sheet.
#  - board trace delays are assumed to be 0.7ns (max)/0.25 ns(min) in these examples
#    and completely balanced (not 100% realistic).
#
#  - ulpiClk must be defined by user (clock at output pin that drives the ulpi clock)

# set the min. input delay to
# min(data_trace_delay + clock_trace_delay) + min. delay when data source is valid after active clock (ULPI: 0ns)

set_input_delay -add_delay -clock ulpiClk -min 0.500 [all_fanin -flat -startpoints_only [get_pins -hier -regex {.*/din_r_reg[[][0-7][]]/D}]]
set_input_delay -add_delay -clock ulpiClk -min 0.500 [all_fanin -flat -startpoints_only [get_pins -hier -regex .*/nxt_r_reg/D]]
set_input_delay -add_delay -clock ulpiClk -min 0.500 [all_fanin -flat -startpoints_only [get_pins -hier -regex .*/dir_r_reg/D]]
set_input_delay -add_delay -clock ulpiClk -min 0.500 [all_fanin -flat -startpoints_only [get_pins -hier -regex .*/stp_i_reg/D]]

# set the max. input delay to
# max(data_trace_delay + clock_trace_delay) + max. delay when data source is valid after active clock (ULPI: 6ns)

set_input_delay -add_delay -clock ulpiClk -max 7.500 [all_fanin -flat -startpoints_only [get_pins -hier -regex {.*/din_r_reg[[][0-7][]]/D}]]
set_input_delay -add_delay -clock ulpiClk -max 7.500 [all_fanin -flat -startpoints_only [get_pins -hier -regex .*/nxt_r_reg/D]]
set_input_delay -add_delay -clock ulpiClk -max 7.500 [all_fanin -flat -startpoints_only [get_pins -hier -regex .*/dir_r_reg/D]]
set_input_delay -add_delay -clock ulpiClk -max 7.500 [all_fanin -flat -startpoints_only [get_pins -hier -regex .*/stp_i_reg/D]]

# set the max. output delay to
#  max(data_trace_delay - clock_trace_delay) + ULPI_setup_time (ULPI: 3ns)

# set the min. output delay to
#  min(data_trace_delay - clock_trace_delay) - ULPI_hold_time (ULPI: 1.5ns)

set_output_delay -add_delay -clock ulpiClk -min -1.00 [all_fanout -flat -endpoints_only [get_pins -hier -regex {.*/dou_r_reg[[][0-7][]]/Q}]]
set_output_delay -add_delay -clock ulpiClk -max 4.000 [all_fanout -flat -endpoints_only [get_pins -hier -regex {.*/dou_r_reg[[][0-7][]]/Q}]]

set_output_delay -add_delay -clock ulpiClk -min -1.00 [all_fanout -flat -endpoints_only [get_pins -hier -regex .*/stp_r_reg/Q]]
set_output_delay -add_delay -clock ulpiClk -max 4.000 [all_fanout -flat -endpoints_only [get_pins -hier -regex .*/stp_r_reg/Q]]

#delay from DIR until outputs are high-z (or back on)
#note that the input delay into DIR and output delay out of the data outputs is 'included' in the max_delay
#if we're paranoid we'd set this to 1 clock cycle to avoid possible
#metastability when the turn-around cycle is latched. However, at least on slower
#devices this does not seem possible. 2-cycles is a must!
set_max_delay -datapath_only -from [all_fanin -flat -startpoints_only [get_pins -hier -regex .*/dir_r_reg/D]] -to [all_fanout -flat -endpoints_only [get_pins -hier -regex {.*/dou_r_reg[[][0-7][]]/Q}]] 33.333
# set_min_delay does not accept -datapath_only; furthermore set_max_delay -datapath_only marks
# a false-path for hold check (c.f. set_max_delay -help)
#set_min_delay  0.0 -datapath_only -from [all_fanin -flat -startpoints_only [get_pins -hier -regex {.*/dir_r_reg/D}]] -to [all_fanout -flat -endpoints_only [get_pins -hier -regex {.*/dou_r_reg[[][0-7][]]/Q}]]
