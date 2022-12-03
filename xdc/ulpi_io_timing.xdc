# ulpiClk must be defined by user (clock at input/output pin that receives/drives the ulpi clock

set_input_delay -clock ulpiClk -min 0.500 [all_fanin -flat -startpoints_only [get_pins -hier -regex {.*/din_r_reg[[][0-7][]]/D}]]
set_input_delay -clock ulpiClk -min 0.500 [all_fanin -flat -startpoints_only [get_pins -hier -regex .*/nxt_r_reg/D]]
set_input_delay -clock ulpiClk -min 0.500 [all_fanin -flat -startpoints_only [get_pins -hier -regex .*/dir_r_reg/D]]

set_input_delay -clock ulpiClk -max 7.500 [all_fanin -flat -startpoints_only [get_pins -hier -regex {.*/din_r_reg[[][0-7][]]/D}]]
set_input_delay -clock ulpiClk -max 7.500 [all_fanin -flat -startpoints_only [get_pins -hier -regex .*/nxt_r_reg/D]]
set_input_delay -clock ulpiClk -max 7.500 [all_fanin -flat -startpoints_only [get_pins -hier -regex .*/dir_r_reg/D]]

set_output_delay -clock ulpiClk -min 0.500 [all_fanout -flat -endpoints_only [get_pins -hier -regex {.*/dou_r_reg[[][0-7][]]/Q}]]
set_output_delay -clock ulpiClk -max 4.000 [all_fanout -flat -endpoints_only [get_pins -hier -regex {.*/dou_r_reg[[][0-7][]]/Q}]]

set_output_delay -clock ulpiClk -min 0.500 [all_fanout -flat -endpoints_only [get_pins -hier -regex .*/stp_r_reg/Q]]
set_output_delay -clock ulpiClk -max 4.000 [all_fanout -flat -endpoints_only [get_pins -hier -regex .*/stp_r_reg/Q]]

#delay from DIR until outputs are high-z (or back on)
#note that the input delay into DIR and output delay out of the data outputs is 'included' in the max_delay - however, there is no
#    'setup' requirement for data going hi-z; when switching back on we have an extra turn-around cycle.
#Thus, we define the max delay = period + max output delay (this removes the internal output delay)
#     = 16.667 + 4.0 = 20.667
set_max_delay -datapath_only -from [all_fanin -flat -startpoints_only [get_pins -hier -regex .*/dir_r_reg/D]] -to [all_fanout -flat -endpoints_only [get_pins -hier -regex {.*/dou_r_reg[[][0-7][]]/Q}]] 20.667
#set_min_delay  0.0 -datapath_only -from [all_fanin -flat -startpoints_only [get_pins -hier -regex {.*/dir_r_reg/D}]] -to [all_fanout -flat -endpoints_only [get_pins -hier -regex {.*/dou_r_reg[[][0-7][]]/Q}]]



