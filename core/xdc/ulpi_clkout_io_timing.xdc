# Copyright Till Straumann, 2023. Licensed under the EUPL-1.2 or later.
# You may obtain a copy of the license at
#   https://joinup.ec.europa.eu/collection/eupl/eupl-text-eupl-12
# This notice must not be removed.

# IO timing constraints (Xilinx-Vivado) when the ULPI clock is driven by the PHY, i.e. ULPI OUTPUT clock mode
#
# NOTE:
#  - values in this file reflect ULPI std; it is likely that modern transceivers have
#    relaxed values; check the data sheet.
#  - board trace delays are assumed to be ~0.7ns (max)/0.25 ns(min) in these examples
#    and completely balanced (not 100% realistic).
#
#  - ulpiClk must be defined by user (clock at output pin that drives the ulpi clock)

# set the min. input delay to
# min(data_trace_delay - clock_trace_delay) + min. delay when data source is valid after active clock (ULPI: 0ns)

set_input_delay -add_delay -clock ulpiClk -min 0.500 [all_fanin -flat -startpoints_only [get_pins -hier -regex {.*/din_r_reg[[]0[]]/D}]]
set_input_delay -add_delay -clock ulpiClk -min 0.500 [all_fanin -flat -startpoints_only [get_pins -hier -regex {.*/din_r_reg[[]1[]]/D}]]
set_input_delay -add_delay -clock ulpiClk -min 0.500 [all_fanin -flat -startpoints_only [get_pins -hier -regex {.*/din_r_reg[[]2[]]/D}]]
set_input_delay -add_delay -clock ulpiClk -min 0.500 [all_fanin -flat -startpoints_only [get_pins -hier -regex {.*/din_r_reg[[]3[]]/D}]]
set_input_delay -add_delay -clock ulpiClk -min 0.500 [all_fanin -flat -startpoints_only [get_pins -hier -regex {.*/din_r_reg[[]4[]]/D}]]
set_input_delay -add_delay -clock ulpiClk -min 0.500 [all_fanin -flat -startpoints_only [get_pins -hier -regex {.*/din_r_reg[[]5[]]/D}]]
set_input_delay -add_delay -clock ulpiClk -min 0.500 [all_fanin -flat -startpoints_only [get_pins -hier -regex {.*/din_r_reg[[]6[]]/D}]]
set_input_delay -add_delay -clock ulpiClk -min 0.500 [all_fanin -flat -startpoints_only [get_pins -hier -regex {.*/din_r_reg[[]7[]]/D}]]
set_input_delay -add_delay -clock ulpiClk -min 0.500 [all_fanin -flat -startpoints_only [get_pins -hier -regex .*/nxt_r_reg/D]]
set_input_delay -add_delay -clock ulpiClk -min 0.500 [all_fanin -flat -startpoints_only [get_pins -hier -regex .*/dir_r_reg/D]]
# use -quiet for stp_i since this signal is only used when MARK_DEBUG is enabled
set_input_delay -quiet -add_delay -clock ulpiClk -min 0.500 [all_fanin -quiet -flat -startpoints_only [get_pins -quiet -hier -regex .*/stp_i_reg/D]]

# set the max. input delay to
# max(data_trace_delay - clock_trace_delay) + max. delay when data source is valid after active clock (ULPI: 9ns)

set_input_delay -add_delay -clock ulpiClk -max 9.500 [all_fanin -flat -startpoints_only [get_pins -hier -regex {.*/din_r_reg[[]0[]]/D}]]
set_input_delay -add_delay -clock ulpiClk -max 9.500 [all_fanin -flat -startpoints_only [get_pins -hier -regex {.*/din_r_reg[[]1[]]/D}]]
set_input_delay -add_delay -clock ulpiClk -max 9.500 [all_fanin -flat -startpoints_only [get_pins -hier -regex {.*/din_r_reg[[]2[]]/D}]]
set_input_delay -add_delay -clock ulpiClk -max 9.500 [all_fanin -flat -startpoints_only [get_pins -hier -regex {.*/din_r_reg[[]3[]]/D}]]
set_input_delay -add_delay -clock ulpiClk -max 9.500 [all_fanin -flat -startpoints_only [get_pins -hier -regex {.*/din_r_reg[[]4[]]/D}]]
set_input_delay -add_delay -clock ulpiClk -max 9.500 [all_fanin -flat -startpoints_only [get_pins -hier -regex {.*/din_r_reg[[]5[]]/D}]]
set_input_delay -add_delay -clock ulpiClk -max 9.500 [all_fanin -flat -startpoints_only [get_pins -hier -regex {.*/din_r_reg[[]6[]]/D}]]
set_input_delay -add_delay -clock ulpiClk -max 9.500 [all_fanin -flat -startpoints_only [get_pins -hier -regex {.*/din_r_reg[[]7[]]/D}]]
set_input_delay -add_delay -clock ulpiClk -max 9.500 [all_fanin -flat -startpoints_only [get_pins -hier -regex .*/nxt_r_reg/D]]
set_input_delay -add_delay -clock ulpiClk -max 9.500 [all_fanin -flat -startpoints_only [get_pins -hier -regex .*/dir_r_reg/D]]
# use -quiet for stp_i since this signal is only used when MARK_DEBUG is enabled
set_input_delay -quiet -add_delay -clock ulpiClk -max 9.500 [all_fanin -quiet -flat -startpoints_only [get_pins -quiet -hier -regex .*/stp_i_reg/D]]

# set the max. output delay to
#  max(data_trace_delay + clock_trace_delay) + ULPI_setup_time (ULPI: 6ns)

# set the min. output delay to
#  min(data_trace_delay + clock_trace_delay) - ULPI_hold_time (ULPI: 0ns)

set_output_delay -add_delay -clock ulpiClk -min 1.00  [all_fanout -flat -endpoints_only [get_pins -hier -regex {.*/dou_r_reg[[]0[]]/Q}]]
set_output_delay -add_delay -clock ulpiClk -min 1.00  [all_fanout -flat -endpoints_only [get_pins -hier -regex {.*/dou_r_reg[[]1[]]/Q}]]
set_output_delay -add_delay -clock ulpiClk -min 1.00  [all_fanout -flat -endpoints_only [get_pins -hier -regex {.*/dou_r_reg[[]2[]]/Q}]]
set_output_delay -add_delay -clock ulpiClk -min 1.00  [all_fanout -flat -endpoints_only [get_pins -hier -regex {.*/dou_r_reg[[]3[]]/Q}]]
set_output_delay -add_delay -clock ulpiClk -min 1.00  [all_fanout -flat -endpoints_only [get_pins -hier -regex {.*/dou_r_reg[[]4[]]/Q}]]
set_output_delay -add_delay -clock ulpiClk -min 1.00  [all_fanout -flat -endpoints_only [get_pins -hier -regex {.*/dou_r_reg[[]5[]]/Q}]]
set_output_delay -add_delay -clock ulpiClk -min 1.00  [all_fanout -flat -endpoints_only [get_pins -hier -regex {.*/dou_r_reg[[]6[]]/Q}]]
set_output_delay -add_delay -clock ulpiClk -min 1.00  [all_fanout -flat -endpoints_only [get_pins -hier -regex {.*/dou_r_reg[[]7[]]/Q}]]
set_output_delay -add_delay -clock ulpiClk -max 7.000 [all_fanout -flat -endpoints_only [get_pins -hier -regex {.*/dou_r_reg[[]0[]]/Q}]]
set_output_delay -add_delay -clock ulpiClk -max 7.000 [all_fanout -flat -endpoints_only [get_pins -hier -regex {.*/dou_r_reg[[]1[]]/Q}]]
set_output_delay -add_delay -clock ulpiClk -max 7.000 [all_fanout -flat -endpoints_only [get_pins -hier -regex {.*/dou_r_reg[[]2[]]/Q}]]
set_output_delay -add_delay -clock ulpiClk -max 7.000 [all_fanout -flat -endpoints_only [get_pins -hier -regex {.*/dou_r_reg[[]3[]]/Q}]]
set_output_delay -add_delay -clock ulpiClk -max 7.000 [all_fanout -flat -endpoints_only [get_pins -hier -regex {.*/dou_r_reg[[]4[]]/Q}]]
set_output_delay -add_delay -clock ulpiClk -max 7.000 [all_fanout -flat -endpoints_only [get_pins -hier -regex {.*/dou_r_reg[[]5[]]/Q}]]
set_output_delay -add_delay -clock ulpiClk -max 7.000 [all_fanout -flat -endpoints_only [get_pins -hier -regex {.*/dou_r_reg[[]6[]]/Q}]]
set_output_delay -add_delay -clock ulpiClk -max 7.000 [all_fanout -flat -endpoints_only [get_pins -hier -regex {.*/dou_r_reg[[]7[]]/Q}]]

set_output_delay -add_delay -clock ulpiClk -min 1.00  [all_fanout -flat -endpoints_only [get_pins -hier -regex .*/stp_r_reg/Q]]
set_output_delay -add_delay -clock ulpiClk -max 7.000 [all_fanout -flat -endpoints_only [get_pins -hier -regex .*/stp_r_reg/Q]]

#delay from DIR until outputs are high-z (or back on)
#note that the input delay into DIR and output delay out of the data outputs is 'included' in the max_delay
#if we're paranoid we'd set this to 1 clock cycle to avoid possible
#metastability when the turn-around cycle is latched. However, at least on slower
#devices this does not seem possible. 2-cycles is a must!
set_max_delay -from [all_fanin -flat -startpoints_only [get_pins -hier -regex .*/dir_r_reg/D]] -to [all_fanout -flat -endpoints_only [get_pins -hier -regex {.*/dou_r_reg[[]0[]]/Q}]] 33.333
set_max_delay -from [all_fanin -flat -startpoints_only [get_pins -hier -regex .*/dir_r_reg/D]] -to [all_fanout -flat -endpoints_only [get_pins -hier -regex {.*/dou_r_reg[[]1[]]/Q}]] 33.333
set_max_delay -from [all_fanin -flat -startpoints_only [get_pins -hier -regex .*/dir_r_reg/D]] -to [all_fanout -flat -endpoints_only [get_pins -hier -regex {.*/dou_r_reg[[]2[]]/Q}]] 33.333
set_max_delay -from [all_fanin -flat -startpoints_only [get_pins -hier -regex .*/dir_r_reg/D]] -to [all_fanout -flat -endpoints_only [get_pins -hier -regex {.*/dou_r_reg[[]3[]]/Q}]] 33.333
set_max_delay -from [all_fanin -flat -startpoints_only [get_pins -hier -regex .*/dir_r_reg/D]] -to [all_fanout -flat -endpoints_only [get_pins -hier -regex {.*/dou_r_reg[[]4[]]/Q}]] 33.333
set_max_delay -from [all_fanin -flat -startpoints_only [get_pins -hier -regex .*/dir_r_reg/D]] -to [all_fanout -flat -endpoints_only [get_pins -hier -regex {.*/dou_r_reg[[]5[]]/Q}]] 33.333
set_max_delay -from [all_fanin -flat -startpoints_only [get_pins -hier -regex .*/dir_r_reg/D]] -to [all_fanout -flat -endpoints_only [get_pins -hier -regex {.*/dou_r_reg[[]6[]]/Q}]] 33.333
set_max_delay -from [all_fanin -flat -startpoints_only [get_pins -hier -regex .*/dir_r_reg/D]] -to [all_fanout -flat -endpoints_only [get_pins -hier -regex {.*/dou_r_reg[[]7[]]/Q}]] 33.333
