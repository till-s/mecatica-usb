# Copyright Till Straumann, 2023. Licensed under the EUPL-1.2 or later.
# You may obtain a copy of the license at
#   https://joinup.ec.europa.eu/collection/eupl/eupl-text-eupl-12
# This notice must not be removed.

# Define ULPI clock for ULPI CLOCK INPUT mode

create_generated_clock -name ulpiClk -source [get_pins -hier *G_CLKDDR.U_DDR/Q] -multiply_by 1 [all_fanout -flat -endpoints_only [get_pins -hier *G_CLKDDR.U_DDR/Q]]

# we use the MMCM to create a negative phase shift to compensate
# for the routing delay from the non-CCIO pin. This works fine
# for input paths but in the opposite direction the worst
# case found by the timer is (a bit less than) 1 cycle off.
# Remedy with a multicycle path

set_multicycle_path -from [get_clocks ulpiClk] 2

# The ulpiDir -> ulpiDat[x] combinatorial path (which switches the output drivers
# off) does not use the delayed clock; must relax the hold timing.
# It would be desirable to not use a multicycle path at all for this combinatorial
# path but on the low-end device we must allow 2 cycles for turn-around which
# is in-principle OK but may result in a bit of driver fighting.
set_multicycle_path -hold -from [get_clocks ulpiClk] -to [get_clocks ulpiClk] 1
