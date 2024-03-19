module pads(
	   input wire 	interface_clk,
		input wire  core_clk,
	   input wire 	reset,
		input wire	cs_n,
		input wire  sdi,
		output wire sdo,
	   output wire	valid,
		output wire auth_fail,
		output wire trigger,

	   output wire die_interface_clk,
	   output wire die_core_clk,
	   output wire die_reset,
	   output wire die_cs_n,
	   output wire die_sdi,
	   input wire die_valid,
	   input wire die_sdo,
	   input wire die_auth_fail,
	   input wire die_trig
      );

   PADI clkipad(.PAD(interface_clk), .OUT(die_interface_clk));
   PADI clkcpad(.PAD(core_clk), .OUT(die_core_clk));
   PADI resetpad(.PAD(reset), .OUT(die_reset));

   PADI cspad(.PAD(cs_n), .OUT(die_cs_n));
   PADI sdipad(.PAD(sdi), .OUT(die_sdi));

   PADO sdopad(.IN(die_sdo), .PAD(sdo));
   PADO validpad(.IN(die_valid), .PAD(valid));
   PADO authpad(.IN(die_auth_fail), .PAD(auth_fail));
   PADO trigpad(.IN(die_trig), .PAD(trigger));

   PADCORNER ul();
   PADCORNER ur();
   PADCORNER ll();
   PADCORNER lr();

   PADVDD1 vdd1();
   PADVDD1 vdd2();
   PADVDD1 vdd3();
   PADVDD1 vdd4();

   PADVSS1 vss1();
   PADVSS1 vss2();
   PADVSS1 vss3();
   PADVSS1 vss4();
   
endmodule

module PADI(input wire PAD, output wire OUT);
   assign OUT = PAD;
endmodule 

module PADO(output wire PAD, input wire IN);
   assign PAD = IN;
endmodule 

module PADVSS1();
endmodule 

module PADVDD1();
endmodule 

module PADCORNER();
endmodule
