# Copyright Till Straumann, 2023. Licensed under the EUPL-1.2 or later.
# You may obtain a copy of the license at
#   https://joinup.ec.europa.eu/collection/eupl/eupl-text-eupl-12
# This notice must not be removed.

# Set the SCOPE_TO_REF property of the XDC file to
#   'Usb2CCSync'
# (module name) in Vivado. (Also restrict its use to
# 'implementation' in order to reduce warnings.)
#
# In case some synchronizers are optimized away; we could use '-quiet'
# to avoid critical warnings.
# Note that this is dangerous since any mistake might go unnoticed.
# After any change to this file or the HDL code it is recommended
# to take -quiet out and inspect the logs before putting it back in.

set_false_path -to [get_pins -of_objects [get_cells {*ccSync_reg[0]} -filter ASYNC_REG] -filter {REF_PIN_NAME==D}]

