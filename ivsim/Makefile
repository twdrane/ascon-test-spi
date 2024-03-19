all: iv

iv:
	iverilog -g2012 -o interface_test ../rtl/config_core.sv ../sim/sipo.sv interface_test.sv ../rtl/ascon_core.sv ../rtl/asconp.sv ../rtl/ascon_spi.sv
	vvp interface_test

wave: iv
	gtkwave tb.vcd config.gtkw --rcvar 'fontname_signals Source Code Pro 10' --rcvar 'fontname_waves Source Code Pro 10'
 
clean:
	rm -f interface_test tb.vcd