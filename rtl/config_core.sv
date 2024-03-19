// Licensed under the Creative Commons 1.0 Universal License (CC0), see LICENSE
// for details.
//
// Author: Robert Primas (rprimas 'at' proton.me, https://rprimas.github.io)
// Minor edits for compatability and simplicity by Trevor Drane
//
// Configuration parameters for the Ascon core and test bench.

//////////////////
// Core Version //
//////////////////

// Version in permutations per clock cycle
// V1 = 1
// V2 = 2
// V3 = 3
// V4 = 6

parameter logic [2:0] UROL = 1;

///////////
// Ascon //
///////////

parameter unsigned LANES = 5;
parameter unsigned LANE_BITS = 64;
parameter unsigned KEY_BITS = 128;

///////////////
// Ascon-128 //
///////////////

parameter logic [63:0] IV_AEAD = 64'h0000000080400c06;
parameter unsigned ROUNDS_A = 12;
parameter unsigned ROUNDS_B = 6;

////////////////
// Ascon-Hash //
////////////////

parameter logic [63:0] IV_HASH = 64'h0000010000400c00;

///////////////
// Interface //
///////////////

// Bus width
parameter unsigned CCW = 32;
parameter unsigned CCSW = 32;

// Operation types
parameter logic [3:0] OP_DO_ENC = 4'h0;
parameter logic [3:0] OP_DO_DEC = 4'h1;
parameter logic [3:0] OP_DO_HASH = 4'h2;
parameter logic [3:0] OP_LD_KEY = 4'h3;
parameter logic [3:0] OP_LD_NONCE = 4'h4;
parameter logic [3:0] OP_LD_AD = 4'h5;
parameter logic [3:0] OP_LD_PT = 4'h6;
parameter logic [3:0] OP_LD_CT = 4'h7;
parameter logic [3:0] OP_LD_TAG = 4'h8;
parameter logic [3:0] OP_INT_SINGLE = 4'h9;
parameter logic [3:0] OP_INT_RPT = 4'hA;
parameter logic [3:0] OP_INT_VML = 4'hB;

// Interface data types
parameter logic [3:0] D_NULL = 4'h0;
parameter logic [3:0] D_NONCE = 4'h1;
parameter logic [3:0] D_AD = 4'h2;  // Also used for hash output
parameter logic [3:0] D_PTCT = 4'h3;  // Plaintext or ciphertext
parameter logic [3:0] D_TAG = 4'h4;
parameter logic [3:0] D_HASH = 4'h5;
parameter logic [3:0] D_KEY = 4'h6;
