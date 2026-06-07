# Copyright Till Straumann, 2026. Licensed under the EUPL-1.2 or later.
# You may obtain a copy of the license at
#   https://joinup.ec.europa.eu/collection/eupl/eupl-text-eupl-12
# This notice must not be removed.

#DISABLED# create_clock -name {CLK_U1} -period 83.3333333333333 [get_ports clk]
create_clock -name {ulpiClk} -period 16.6666666666666 [get_ports ulpiClk]
