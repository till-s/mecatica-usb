
set origin_dir [file dir [info script]]

set proj_name Usb2Example

prj_create -name "${proj_name}" -impl "impl_1" -dev LIFCL-40-9BG400C -performance "9_High-Performance_1.0V" -synthesis "synplify"

# Disable PAR DRC to enable routing non-clock pin
prj_set_strategy_value -strategy Strategy1 {par_cmdline_args=-exp WARNING_ON_PCLKPLC1=1}
prj_set_strategy_value -strategy Strategy1 {syn_vhdl2008=True}

source "${origin_dir}/srcs.tcl"

foreach fil ${lib_vhdl_files} {
  prj_add_source "${fil}"
}

prj_add_source "${origin_dir}/../hdl/Usb2Example.vhd"
prj_add_source "${origin_dir}/../hdl/Usb2AppCfgPkgBody.vhd"

prj_add_source "${origin_dir}/../pdc/clock.sdc"
prj_enable_source "${origin_dir}/../pdc/clock.sdc"

prj_add_source "${origin_dir}/../pdc/pins.pdc"
prj_enable_source "${origin_dir}/../pdc/pins.pdc"

prj_add_source "${origin_dir}/../pdc/timing.pdc"
prj_enable_source "${origin_dir}/../pdc/timing.pdc"

prj_save
