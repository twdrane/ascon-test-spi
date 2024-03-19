if {![info exists ::env(CLOCKPERIOD)] } {
  set clockPeriod 20
} else {
    set clockPeriod [getenv CLOCKPERIOD]
}

if {![info exists ::env(COREPERIOD)] } {
  set corePeriod 200
} else {
    set corePeriod [getenv COREPERIOD]
}

create_clock -name interface_clk -period $clockPeriod [get_ports "interface_clk"]

create_clock -name core_clk -period $corePeriod [get_ports "core_clk"]

set_input_delay  0 -clock interface_clk [all_inputs -no_clocks]
set_output_delay 0 -clock interface_clk [all_outputs]

set_input_delay  0 -clock core_clk [all_inputs -no_clocks]
set_output_delay 0 -clock core_clk [all_outputs]

set_dont_touch chip/thepads true
