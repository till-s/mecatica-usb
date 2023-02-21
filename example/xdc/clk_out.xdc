# Copyright Till Straumann, 2023. Licensed under the EUPL-1.2 or later.
# You may obtain a copy of the license at
#   https://joinup.ec.europa.eu/collection/eupl/eupl-text-eupl-12
# This notice must not be removed.

# Define ULPI clock for ULPI OUTPUT CLOCK mode
# The pin is not a clock-capable one on the demo PMOD board; thus
# we must set CLOCK_DEDICATED_ROUTE and fiddle with MMCM phase...
create_clock -period 16.665 -name ulpiClk [get_ports ulpiClk]
set_property CLOCK_DEDICATED_ROUTE FALSE [get_nets -hier -regex .*/G_MMCM.U_ULPI_CLK_IOBUF/O]

# we use the MMCM to create a negative phase shift to compensate
# for the routing delay from the non-CCIO pin. This works fine
# for input paths but in the opposite direction the worst
# case found by the timer is (a bit less than) 1 cycle off.
# Remedy with a multicycle path

set_multicycle_path -from [get_clocks ulpiClk] 2


