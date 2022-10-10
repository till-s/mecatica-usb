# ulpiClk must be defined by user (clock at input/output pin that receives/drives the ulpi clock

set_input_delay -min 0.5 -clock ulpiClk [all_fanin -flat -startpoints_only [get_pins -hier -regex {.*/din_r_reg[[][0-7][]]/D}]]
set_input_delay -min 0.5 -clock ulpiClk [all_fanin -flat -startpoints_only [get_pins -hier -regex {.*/nxt_r_reg/D}]]
set_input_delay -min 0.5 -clock ulpiClk [all_fanin -flat -startpoints_only [get_pins -hier -regex {.*/dir_r_reg/D}]]

set_input_delay -max 7.5 -clock ulpiClk [all_fanin -flat -startpoints_only [get_pins -hier -regex {.*/din_r_reg[[][0-7][]]/D}]]
set_input_delay -max 7.5 -clock ulpiClk [all_fanin -flat -startpoints_only [get_pins -hier -regex {.*/nxt_r_reg/D}]]
set_input_delay -max 7.5 -clock ulpiClk [all_fanin -flat -startpoints_only [get_pins -hier -regex {.*/dir_r_reg/D}]]

set_output_delay -min 0.5 -clock ulpiClk [all_fanout -flat -endpoints_only [get_pins -hier -regex {.*/dou_r_reg[[][0-7][]]/Q}]]
set_output_delay -max 4.0 -clock ulpiClk [all_fanout -flat -endpoints_only [get_pins -hier -regex {.*/dou_r_reg[[][0-7][]]/Q}]]

set_output_delay -min 0.5 -clock ulpiClk [all_fanout -flat -endpoints_only [get_pins -hier -regex {.*/stp_r_reg/Q}]]
set_output_delay -max 4.0 -clock ulpiClk [all_fanout -flat -endpoints_only [get_pins -hier -regex {.*/stp_r_reg/Q}]]

#delay from DIR until outputs are high-z (or back on)
#note that the output delay of the data outputs is 'included' in the max_delay - however, there is no 'setup' requirement
#for data going hi-z; when switching back on we have an extra turn-around cycle.
set_max_delay 20.0 -from [all_fanin -flat -startpoints_only [get_pins -hier -regex {.*/dir_r_reg/D}]] -to [all_fanout -flat -endpoints_only [get_pins -hier -regex {.*/dou_r_reg[[][0-7][]]/Q}]]
set_min_delay  0.0 -from [all_fanin -flat -startpoints_only [get_pins -hier -regex {.*/dir_r_reg/D}]] -to [all_fanout -flat -endpoints_only [get_pins -hier -regex {.*/dou_r_reg[[][0-7][]]/Q}]]

