`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: WPI
// Engineer: Trevor Drane
// 
// Create Date: 10/25/2023 02:43:11 PM
// Design Name: Ascon SPI
// Module Name: interface_test
// Project Name: 
// Target Devices: Basys 3
// Tool Versions: 
// Description: Simulation source for interface testing
// 
// Dependencies: sipo.sv
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module interface_test(

    );
    logic interface_clk;
    logic core_clk;
    //logic clk;
    logic rst;
    logic cs_n;
    logic sdi;
    logic valid;
    logic sdo;
    logic auth_fail;
    logic [31:0] in;
    logic [31:0] out;
    logic trig;

    
    int tv_num;
    string tv_path;
    string TV_SET1 = "../tv/set1/tv.txt"; // long set
    string TV_SET2 = "../tv/set2/tv.txt"; // short set
    string TV_SET3 = "../tv/set3/tv.txt"; // rpt
    string TV_SET4 = "../tv/set4/tv.txt"; // vml
    string TV_SET5 = "../tv/set5/tv.txt"; //
    int arg_status = 0;
	//string CHECK_FILE = "../tv/set1/check_d.txt";
    int fvectors,fcheck;
    int SIM_T = 60000; // 60 ms for one round of hashing
    string line;
    string hdr,ignore;
    int cnt;
	
	logic [31:0] expected;
	logic verify;
    
    
    always #10 interface_clk = ~interface_clk;
    always #5 core_clk = ~core_clk;
    //always #5 clk = ~clk;
    
    initial begin
		verify = 1;
        $dumpfile("trace.vcd");
	    $dumpvars(0, interface_test);
		//fcheck = $fopen (CHECK_FILE, "r");
        arg_status = $value$plusargs("TV_SET=%d",tv_num);
        if (arg_status) begin
            case (tv_num)
                1: tv_path = TV_SET1;
                2: tv_path = TV_SET2;
                3: begin tv_path = TV_SET3;
                    SIM_T = 150_000_000; 
                end
                4: tv_path = TV_SET4;
                5: tv_path = TV_SET5;
                default: tv_path = TV_SET1;
            endcase
            fvectors = $fopen (tv_path, "r");
        end
        else fvectors = $fopen (TV_SET1, "r");
        if (fvectors == 0) begin
	       $display("Could not open test vector file");
	       $finish;
	    end
        rst = 1'b1;
        core_clk = 1'b0;
        interface_clk = 1'b0;
        cs_n = 1'b1;
        sdi = 1'b0;
        @(posedge interface_clk);
        @(negedge interface_clk) rst = 1'b0;
        @(negedge interface_clk) cs_n = 1'b0;
        while (!$feof(fvectors)) begin
            void'($fgets(line, fvectors));
            void'($sscanf(line, "%s", hdr));
            if (hdr == "WAIT") begin
                fork
                    begin
                        wait (auth_fail);
                        $display("AUTH FAIL @ %0t", $time);
                        @(negedge interface_clk) rst = 1'b1;
                        @(negedge interface_clk) rst = 1'b0;
                    end
                    begin
                        wait (valid);
                        wait (~valid);
                        @(posedge interface_clk);
                        @(posedge interface_clk);
                        wait (~valid);
                    end
                join_any
                @(negedge interface_clk) rst = 1'b1;
                @(negedge interface_clk) rst = 1'b0;
                $display("timestamp: %0t", $time);
                continue;
            end
            if (hdr == "STOP") continue;
            if (hdr == "#") void'($fgets(line, fvectors));
            void'($sscanf(line, "%s %h", hdr, in));
            //if (hdr == "STOP") $stop;
            cnt = 31;
            repeat(32) begin 
                sdi = in[cnt];
                @(negedge interface_clk);
                cnt = cnt - 1;
            end
        end
        $fclose(fvectors);
    end
    
    always #SIM_T $stop;

    sipo sipo (
        .clk(interface_clk),
        .cs(valid),
        .sdi(sdo),
        .pdo(out)
    );

    always @(out) begin
		//void'($fscanf(fcheck, "%h", expected));
		//verify = (expected==out) && verify;
        $display("%h", out);
		// if ($feof(fcheck)) begin
		// 	if (verify == 1'b1)
		// 		$display("Testbench Passed");
		// 	else
		// 		$display("Testbench Failed");
		// end
    end
    
    ascon_spi dut (
        .interface_clk(interface_clk),
        .core_clk(core_clk),
        //.clk(clk),
        .rst(rst),
        .cs_n(cs_n),
        .sdi(sdi),
        .valid(valid),
        .sdo(sdo),
        .auth_fail(auth_fail),
        .trig(trig)
	);
    
endmodule
