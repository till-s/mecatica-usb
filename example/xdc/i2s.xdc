# Copyright Till Straumann, 2023. Licensed under the EUPL-1.2 or later.
# You may obtain a copy of the license at
#   https://joinup.ec.europa.eu/collection/eupl/eupl-text-eupl-12
# This notice must not be removed.

create_clock -period 434.030 -name i2sBCLK [get_ports i2sBCLK]

# min delay after clock falling edge when pblrc becomes valid: min duty cycle after rising edge
#
set_input_delay -clock i2sBCLK -min -add_delay 195.000 [get_ports i2sPBLRC]

# max delay after clock falling edge when pblrc becomes valid: max duty cycle + output delay
# 434*0.55 + 10
set_input_delay -clock i2sBCLK -max -add_delay 249.000 [get_ports i2sPBLRC]

# trace delay - external hold time
set_output_delay -clock i2sBCLK -min -add_delay -10.000 [get_ports i2sPBDAT]

# trace delay + external setup time
set_output_delay -clock i2sBCLK -max -add_delay 31.000 [get_ports i2sPBDAT]

# huge timing violations on the FIFO/RST - no surprise since there are asynchronous
# clocks. According to some forum talk this can be set as a false path because
# the FIFO internals handle it correctly (provided we reset for >=5 cycles of the
# slower clock.
set_false_path -through [get_pins -hier -regexp .*U_I2S_PLAYBACK_FIFO/RST]


