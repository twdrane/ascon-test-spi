module chip(
	    input wire 	interface_clk,
		input wire  core_clk,
	    input wire 	reset,
		input wire	cs_n,
		input wire  sdi,
		output wire sdo,
	    output wire	valid,
		output wire auth_fail,
		output wire trigger);
   
    wire 	die_interface_clk;
	wire	die_core_clk;
    wire 	die_reset;
    wire	die_cs_n;
	wire	die_sdi;
    wire	die_valid;
    wire	die_sdo;
    wire 	die_auth_fail;
    wire	die_trig;

   pads thepads(.interface_clk(interface_clk),
		.core_clk(core_clk),
		.reset(reset),
		.cs_n(cs_n),
		.sdi(sdi),
		.sdo(sdo),
		.valid(valid),
		.auth_fail(auth_fail),
		.trigger(trigger),

		// die connections
		.die_interface_clk(die_interface_clk),
		.die_core_clk(die_core_clk),
		.die_reset(die_reset),
		.die_cs_n(die_cs_n),
		.die_sdi(die_sdi),
		.die_valid(die_valid),
		.die_sdo(die_sdo),
		.die_auth_fail(die_auth_fail),
		.die_trig(die_trig)
		);

   ascon_spi thecore (
        .interface_clk(die_interface_clk),
        .core_clk(die_core_clk),
        .rst(die_reset),
        .cs_n(die_cs_n),
        .sdi(die_sdi),
        .valid(die_valid),
        .sdo(die_sdo),
        .auth_fail(die_auth_fail),
        .trig(die_trig)
	);
   
endmodule
   
