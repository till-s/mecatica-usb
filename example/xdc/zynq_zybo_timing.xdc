# Copyright Till Straumann, 2023. Licensed under the EUPL-1.2 or later.
# You may obtain a copy of the license at
#   https://joinup.ec.europa.eu/collection/eupl/eupl-text-eupl-12
# This notice must not be removed.

# the i2s clock is not routed to a clock input; we get relentless
# warnings but running such a slow clock through the fabric should
# not be a problem for timing...

set_property CLOCK_DEDICATED_ROUTE FALSE [get_nets i2sBCLK_IBUF]

