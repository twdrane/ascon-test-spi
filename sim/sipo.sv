`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: WPI
// Engineer: Trevor Drane
// 
// Create Date: 11/28/2023 02:43:11 PM
// Design Name: Ascon SPI
// Module Name: sipo
// Project Name: 
// Target Devices: Basys 3
// Tool Versions: 
// Description: simple 32 bit sipo conversion
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module sipo(
    input logic clk,
    input logic sdi,
    input logic cs,
    output logic [31:0] pdo
    );

    logic [31:0] shift,hold;
    integer count;

    initial begin
        count = 1;
        pdo = 32'b0;
    end

    assign shift = (cs == 1'b1) ? {hold[30:0],sdi} : hold;
    
    always @(posedge clk) begin
        if (cs == 1'b1) begin
            hold <= shift;
            if (count == 32) begin
                count <= 1;
            end
            else begin
                count <= count+1;
            end
        end
        if (count == 32) begin
            pdo <= shift;
            hold <= shift;
        end
    end

    
endmodule
