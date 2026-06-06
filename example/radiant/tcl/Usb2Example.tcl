
set origin_dir [file normalize [file dir [info script]]]

set proj_name Usb2Example

set proj_dir "${origin_dir}/../${proj_name}"

prj_create -name "${proj_name}" -dir "${proj_dir}" -impl "impl_1" -dev LIFCL-40-9BG400C -performance "9_High-Performance_1.0V" -synthesis "synplify"

# Disable PAR DRC to enable routing non-clock pin
prj_set_strategy_value -strategy Strategy1 {par_cmdline_args=-exp WARNING_ON_PCLKPLC1=1}
prj_set_strategy_value -strategy Strategy1 {syn_vhdl2008=True}

source "${origin_dir}/../../tcl/srcs_common.tcl"

foreach fil ${example_common_src_files} {
  prj_add_source "${fil}"
}

prj_add_source "${origin_dir}/../hdl/Usb2Example.vhd"
prj_add_source "${origin_dir}/../hdl/Usb2AppCfgPkgBody.vhd"

prj_add_source "${origin_dir}/../pdc/clock.sdc"
prj_enable_source "${origin_dir}/../pdc/clock.sdc"

prj_add_source "${origin_dir}/../pdc/Usb2Example.pdc"
prj_enable_source "${origin_dir}/../pdc/Usb2Example.pdc"

prj_add_source "${origin_dir}/../ip/UlpiPLL/UlpiPLL.ipx"

prj_save
