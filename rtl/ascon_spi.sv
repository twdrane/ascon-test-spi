// Top spi control and testing interface for 32 bit ascon core intended 
// for use with the ascon hardware design by Robert Primas
// available at https://github.com/rprimas/ascon-verilog 
//
// Author: Trevor Drane
// Design Repository: https://github.com/twdrane/Open-Source-ASCON-ASIC
// Designed as part of a WPI Major Qualifying Project

`timescale 1ns / 1ps

module ascon_spi (
	input logic interface_clk,
	input logic core_clk,
	input logic rst,
	input logic cs_n,
	input logic sdi,
	
	output logic valid,
	output logic sdo,
	output logic auth_fail,
	output logic trig
	);

	//parameters
	parameter logic TRUE = 1'b1;
	parameter logic FALSE = 1'b0;

	// core io
	logic [31:0] 	key_w;
	logic 			key_valid;
	logic 			key_ready;
	logic [31:0]	bdi;
	logic 			bdi_valid;
	logic 			bdi_ready;
	logic [3:0]		bdi_type;
	logic 			bdi_eot;
	logic 			bdi_eoi;
	logic 			decrypt;
	logic 			hash;
	logic [31:0]	bdo;
	logic 			bdo_valid;
	logic 			bdo_ready;
	logic [3:0]		bdo_type;
	logic 			bdo_eot;
	logic			auth;
	logic 			auth_valid;
	logic 			auth_ready;

	// core op wires
	logic 			key_valid_next;
	logic			bdi_valid_next;
	logic			bdi_eot_next;
	logic 			bdi_eoi_next;

	//////////////////
	// sipo convert //
	//////////////////

	logic [31:0] d_parallel;
	logic [31:0] shift_reg;
	logic [31:0] sipo_next;
	logic [4:0] n_shifts,shifts_next;
	logic done;
	
	always_ff @ (posedge interface_clk) begin : sipo1_seq
        if (rst) begin
            shift_reg <= 32'd0;
            n_shifts <= 5'd31;
        end
        else begin
			shift_reg <= sipo_next;
            n_shifts <= shifts_next;
        end
    end
	
	// only shift if cs_n is active
	assign sipo_next = ~cs_n ? {shift_reg[30:0],sdi} : shift_reg;
	assign shifts_next = ~cs_n ? n_shifts + 1 : n_shifts;
	assign done = ~cs_n & (n_shifts == 5'd31);
	// end sipo convert
	
	// create sipo output
	always_ff @ (posedge interface_clk) begin : sipo2_seq
		if (rst) d_parallel <= 32'b0;
		else d_parallel <= (done) ? shift_reg : d_parallel;
	end

	//////////////////////////
	// FSM enumerated types //
	//////////////////////////

	// spi encryption interface state machine 	
	typedef enum bit [4:0] {
		I_IDLE,
		I_INST,
		I_READ_INST,
		I_DATA,
		I_READ_DATA,
		I_CORE,
		I_RETURN_SYNC,
		I_RETURN_PTCT,
		I_RETURN_BREAK,
		I_RETURN_TAG,
		I_RETURN_HASH,
		I_DONE
	} spi_fsm;
	
	spi_fsm current_state;
	spi_fsm next_state;

	typedef enum bit [4:0] {
		C_IDLE,
		C_LOAD_KEY,
		C_LOAD_NONCE,
		C_LOAD_AD,
		C_LOAD_PTCT,
		C_LOAD_TAG,
		C_RUN,
		C_WAIT_OUT,
		C_DONE
	} core_fsm;

	core_fsm core_state;
	core_fsm next_core_state;
	
	logic rpt_done,vml_done;

	logic [3:0]  inst;
	logic [3:0]  next_data_type,data_type;
	logic 		 read_done;
	logic [2:0]  read_count,data_size,size_calc;

	// main data registers
	logic [31:0] interface_config; //configure interface settings and run cycles
	logic [31:0] core_config; //encrypt/decrypt/hash
	logic [2:0]  key_size;
	logic [2:0]  nonce_size;
	logic [2:0]  ad_size;
	logic [2:0]  ptct_size;
	logic [2:0]  tag_size;
	// main data registers

	// main data wires
	logic [3:0] interface_mode;
	assign interface_mode = interface_config[31:28];
	logic [3:0] core_mode;
	assign core_mode = core_config[31:28];

	// load control values
	logic [2:0]  load_count,load_count_next;
	logic 		 load_done;

	// return data control registers
	logic [3:0] reg_count;
	logic [4:0] piso_count;
	
	assign inst = d_parallel[31:28];
	assign size_calc = (d_parallel[1:0] != 2'b0) ? d_parallel[5:2] : d_parallel[5:2]-1; // calculate size with rounding up
	assign read_done = (current_state == I_READ_DATA) & (read_count == data_size); // defines finishing read and instruction count;

	logic return_done; 
	logic hash_done;

	assign return_done = ((reg_count == 4'd3 & current_state == I_RETURN_TAG) | (reg_count == ptct_size & current_state == I_RETURN_PTCT)) & (piso_count == 5'd31);
	assign hash_done = (reg_count == 4'd7) & (piso_count == 5'd31);

	logic auth_check;

	assign auth_check = auth_valid && auth;
	
	// auth fail pin
	// set auth fail flag
	always_ff @(posedge core_clk) begin : auth_fail_seq
		if (rst == TRUE) begin
			auth_fail <= FALSE;
		end
		else begin
			if (auth_ready == TRUE)
				auth_fail <= (auth_valid) ? ~auth : auth_fail;
		end
	end

	///////////////////////////////
	//    ______ _____ __  __    //
	//   |  ____/ ____|  \/  |   //
	//   | |__ | (___ | \  / |   //
	//   |  __| \___ \| |\/| |   //
	//   | |    ____) | |  | |   //
	//   |_|   |_____/|_|  |_|   //
	//                           //
	///////////////////////////////

	// clock transfer buffers
	spi_fsm ifsm_buf_1,ifsm_buf_2;
	core_fsm cfsm_buf_1,cfsm_buf_2;

	// next state logic
	always_comb begin : interface_state_comb
		case (current_state)
			I_IDLE: begin
				next_state = (cs_n === 1'b0) ? I_INST : I_IDLE;
			end
			I_INST: begin
				next_state = done === TRUE ? I_READ_INST : I_INST; 
			end
			I_READ_INST: begin
				case (inst)
					// configure core
					OP_DO_ENC,OP_DO_DEC,OP_DO_HASH: 
					begin
						next_state = I_INST;
					end
					// load data
					OP_LD_KEY,OP_LD_NONCE,OP_LD_AD,OP_LD_PT,OP_LD_CT,OP_LD_TAG: 
					begin
						next_state = I_DATA;
					end
					// configure interface
					OP_INT_SINGLE,OP_INT_RPT,OP_INT_VML:
					begin
						next_state = I_CORE;
					end
					default: next_state = I_INST;
				endcase
			end
			I_DATA: begin
				next_state = done === TRUE ? I_READ_DATA : I_DATA; 
			end
			I_READ_DATA: begin
				next_state = read_done === TRUE ? I_INST : I_DATA;
			end
			// pass control to core fsm
			I_CORE: begin
				next_state = cfsm_buf_2 == C_DONE ? I_RETURN_SYNC : I_CORE;
			end
			I_RETURN_SYNC: begin // extra clock cycle to assign sipo reg
				next_state = core_mode === OP_DO_HASH ? I_RETURN_HASH : I_RETURN_PTCT;
			end
			I_RETURN_PTCT: begin
				if (core_mode == OP_DO_ENC)
					next_state = return_done === TRUE ? I_RETURN_BREAK : I_RETURN_PTCT;
				else
					next_state = return_done === TRUE ? I_DONE : I_RETURN_PTCT;
			end
			I_RETURN_BREAK: begin
				next_state = I_RETURN_TAG;
			end
			I_RETURN_TAG: begin
				next_state = return_done === TRUE ? I_DONE : I_RETURN_TAG;
			end
			I_RETURN_HASH: begin
				next_state = hash_done === TRUE ? I_DONE : I_RETURN_HASH;
			end
			I_DONE: begin
				// resets only after cs is deasserted
				next_state = cs_n === TRUE ? I_IDLE : I_DONE;
			end
			default: next_state = I_IDLE;
		endcase
	end
	
	// assign next state and reset case
	always_ff @ (posedge interface_clk) begin : interface_state_seq
		if (rst) begin
			current_state <= I_IDLE;
			cfsm_buf_1 <= C_IDLE;
			cfsm_buf_2 <= C_IDLE;
		end
		else begin
			current_state <= next_state;
			cfsm_buf_1 <= core_state;
			cfsm_buf_2 <= cfsm_buf_1;
		end
	end
	// end SPI FSM

	// core next state logic
	always_comb begin : core_state_comb
		next_core_state = C_IDLE;
		case (core_state)
			C_IDLE: begin
				if (ifsm_buf_2 == I_CORE) begin
					// check for hashing
					next_core_state = core_mode === OP_DO_HASH ? C_LOAD_AD : C_LOAD_KEY;
				end
				else next_core_state = C_IDLE;
			end
			C_LOAD_KEY: begin
				next_core_state = load_done === TRUE ? C_LOAD_NONCE : C_LOAD_KEY;
			end
			C_LOAD_NONCE: begin
				next_core_state = load_done === TRUE ? C_LOAD_AD : C_LOAD_NONCE;
			end
			C_LOAD_AD: begin
				if (load_done) begin
					// check core operation for hashing
					if (core_mode == OP_DO_HASH) begin
						// check op for vml
						if (interface_mode == OP_INT_VML) begin
							if (vml_done) begin
								next_core_state = C_WAIT_OUT;
							end	else next_core_state = C_LOAD_AD;
						end else next_core_state = C_WAIT_OUT;
					end else next_core_state = C_LOAD_PTCT;
				end else next_core_state = C_LOAD_AD;
			end
			C_LOAD_PTCT: begin
				if (load_done) begin
					if (interface_mode == OP_INT_VML) begin
						if (vml_done) begin
							case (core_mode)
								OP_DO_ENC: next_core_state = C_WAIT_OUT;
								OP_DO_DEC: next_core_state = C_LOAD_TAG;
								default: next_core_state = C_WAIT_OUT;
							endcase
						end
					end
					else begin
						// check core operation
						case (core_mode)
							OP_DO_ENC: next_core_state = C_WAIT_OUT;
							OP_DO_DEC: next_core_state = C_LOAD_TAG;
							default: next_core_state = C_WAIT_OUT;
						endcase
					end
				end 
				else next_core_state = C_LOAD_PTCT;
			end
			C_LOAD_TAG: begin
				if (load_done) begin  
					// check interface mode
					next_core_state = C_WAIT_OUT;
				end 
				else next_core_state = C_LOAD_TAG;
			end
			C_RUN: begin
				if (interface_mode == OP_INT_RPT)begin
					if (rpt_done) begin
						next_core_state = C_DONE;
					end
					else begin
						case (core_mode) 
							OP_DO_ENC,OP_DO_DEC: next_core_state = C_LOAD_NONCE;
							OP_DO_HASH: next_core_state = C_LOAD_AD;
							default: next_core_state = C_LOAD_NONCE;
						endcase
					end
				end
				else next_core_state = C_DONE;
			end
			C_WAIT_OUT: begin // wait for the tag, auth, or hash message to be calculated
				// check interface mode
				if (core_mode == OP_DO_DEC) begin
					// check auth
					next_core_state = auth_check === TRUE ? C_RUN : C_WAIT_OUT;
				end else begin
					// hashing and enc
					// wait for end of bdo
					next_core_state = bdo_eot === TRUE ? C_RUN : C_WAIT_OUT;
				end
			end
			C_DONE: begin
				next_core_state = (ifsm_buf_2 == I_CORE) ? C_DONE : C_IDLE;
			end
			default: next_core_state = C_IDLE;
		endcase
	end
	
	// core next state
	always_ff @ (posedge core_clk) begin : core_state_seq
		if (rst) begin
			core_state <= C_IDLE;
			ifsm_buf_1 <= I_IDLE;
			ifsm_buf_2 <= I_IDLE;
		end
		else begin
			core_state <= next_core_state;
			ifsm_buf_1 <= current_state;
			ifsm_buf_2 <= ifsm_buf_1;
		end
	end
	// end core fsm

	///////////////////////////////
	// interface mode ctrl logic //
	///////////////////////////////

	logic [15:0] interface_count;
	assign interface_count = interface_config[15:0];

	// OP_INT_RPT control
	logic [31:0] rpt_counter;
	assign rpt_done = (interface_mode == OP_INT_RPT) & (rpt_counter[31:16] >= interface_count);

	always_ff @ (posedge core_clk) begin : rpt_ctl
		if (rst) begin
			rpt_counter <= 32'b0;
		end
		else begin
			if ((interface_mode == OP_INT_RPT) & (core_state == C_RUN)) begin
				rpt_counter <= rpt_counter + 1;
			end
		end
	end

	// OP_INT_VML control
	logic [31:0] vml_counter;
	assign vml_done = (interface_mode == OP_INT_VML) & (vml_counter >= interface_count);

	always_ff @ (posedge core_clk) begin : vml_ctl
		if (rst) begin
			vml_counter <= 32'b0;
		end
		else begin
			if ((interface_mode == OP_INT_VML) & ((core_state == C_LOAD_AD & core_mode == OP_DO_HASH) | (core_state == C_LOAD_PTCT)) & load_done) begin
				vml_counter <= vml_counter + 1;
			end
		end
	end
	// end interface mode ctrl logic

	/////////////////////////////
	// memory and config logic //
	/////////////////////////////

	// inputs
	// encrypt
	logic [31:0] key 		[3:0];
	logic [31:0] nonce 		[3:0];
	logic [31:0] a_data 	[3:0];
	logic [31:0] ptct 		[3:0];
	// decrypt
	logic [31:0] tag 		[3:0];
	
	// outputs
	logic [31:0] ptct_out 	[3:0];
	
	logic [31:0] tag_out 	[3:0];
	
	logic [31:0] hash_out 	[7:0];
	
	// data type logic
	always_comb begin : data_type_comb
		// determine data type from instruction
		if (current_state == I_READ_INST) begin
			case (inst)
				OP_LD_KEY: next_data_type = D_KEY;
				OP_LD_NONCE: next_data_type = D_NONCE;
				OP_LD_AD: next_data_type = D_AD;
				OP_LD_PT: next_data_type = D_PTCT;
				OP_LD_CT: next_data_type = D_PTCT;
				OP_LD_TAG: next_data_type = D_TAG;
				default: next_data_type = D_NULL;
			endcase
		end else next_data_type = data_type;
		// end read instructions
	end
	
	// syncronized assignments
	always_ff @ (posedge interface_clk) begin : memory_config
		// define resets
		if (rst) begin
			core_config <= 32'b0;
			interface_config <= 32'b0;
			data_size 	<= 3'b0;
			data_type 	<= 4'b0;
			read_count 	<= 3'b0;
			key[0] 		<= 32'b0; key[1] <= 32'b0; key[2] <= 32'b0; key[3] <= 32'b0;
			nonce[0] 	<= 32'b0; nonce[1] <= 32'b0; nonce[2] <= 32'b0; nonce[3] <= 32'b0;
			a_data[0] 	<= 32'b0; a_data[1] <= 32'b0; a_data[2] <= 32'b0; a_data[3] <= 32'b0;
			ptct[0] 	<= 32'b0; ptct[1] <= 32'b0; ptct[2] <= 32'b0; ptct[3] <= 32'b0;
			tag[0] 		<= 32'b0; tag[1] <= 32'b0; tag[2] <= 32'b0; tag[3] <= 32'b0;
			key_size 	<= 3'b0;
			nonce_size 	<= 3'b0;
			ad_size 	<= 3'b0;
			ptct_size 	<= 3'b0;
			tag_size 	<= 3'b0;
		end else begin
			// update instructions
			core_config <= ((inst == OP_DO_ENC | inst == OP_DO_DEC | inst == OP_DO_HASH) & current_state == I_READ_INST) ? d_parallel : core_config;
			interface_config <= ((inst == OP_INT_SINGLE | inst == OP_INT_RPT | inst == OP_INT_VML) & current_state == I_READ_INST) ? d_parallel : interface_config;
			data_size 	<= (current_state == I_READ_INST) ? size_calc : data_size;
			data_type 	<= next_data_type;
			// end update instructions
			// update data size
			key_size 	<= (data_type == D_KEY) 	? data_size : key_size;
			nonce_size 	<= (data_type == D_NONCE) 	? data_size : nonce_size;
			ad_size 	<= (data_type == D_AD) 		? data_size : ad_size;
			ptct_size 	<= (data_type == D_PTCT) 	? data_size : ptct_size;
			tag_size 	<= (data_type == D_TAG) 	? data_size : tag_size;
			// end update size
			// update data
			//count reads
			if (current_state == I_READ_DATA) begin
				read_count <= read_count + 1;
			end
			else if (current_state == I_DATA)
				read_count <= read_count;
			else read_count <= 3'b0;
			//save data to registers
			key[read_count] 	<= (data_type == D_KEY & current_state == I_READ_DATA) 	? d_parallel : key[read_count];
			nonce[read_count] 	<= (data_type == D_NONCE & current_state == I_READ_DATA) 	? d_parallel : nonce[read_count];
			a_data[read_count] 	<= (data_type == D_AD & current_state == I_READ_DATA) 		? d_parallel : a_data[read_count];
			ptct[read_count] 	<= (data_type == D_PTCT & current_state == I_READ_DATA) 	? d_parallel : ptct[read_count];
			tag[read_count] 	<= (data_type == D_TAG & current_state == I_READ_DATA) 	? d_parallel : tag[read_count];
			// end update data
		end
	end	
	// end memory and config

	
	/////////////////////
	// core load logic //
	/////////////////////

	// define load_done
	always_comb begin : load_done_comb
		case (core_state)
			C_LOAD_KEY: 	load_done = key_ready & (load_count == key_size);
			C_LOAD_NONCE: 	load_done = bdi_ready & (load_count == nonce_size);
			C_LOAD_AD: 		load_done = bdi_ready & (load_count == ad_size);
			C_LOAD_PTCT: 	load_done = bdi_ready & (load_count == ptct_size);
			C_LOAD_TAG: 	load_done = bdi_ready & (load_count == tag_size);
			default: load_done = FALSE;
		endcase
	end

	always_comb begin : core_load_comb
		if (load_done) load_count_next = 3'b0;
		else if ((bdi_ready & bdi_valid) | (key_ready & key_valid)) load_count_next = load_count + 1;
		else load_count_next = load_count;
		key_w = 32'b0;
		key_valid_next = FALSE;
		bdi = 32'b0;
		bdi_valid_next = FALSE;
		bdi_type = D_NULL;
		bdi_eot_next = FALSE;
		bdi_eoi_next = FALSE;
		case (core_state)
			C_LOAD_KEY: begin 
				key_w 			= key[load_count];
				key_valid_next 	= ~load_done;
			end
			C_LOAD_AD: begin 
				bdi				= a_data[load_count];
				bdi_type 		= D_AD;
				bdi_valid_next 	= ~load_done;
				bdi_eot_next 	= ((ad_size == load_count_next) & bdi_ready & ((core_mode != OP_DO_HASH) | (interface_mode != OP_INT_VML) | vml_done));
				bdi_eoi_next 	= ((ad_size == load_count_next) & bdi_ready & (core_mode == OP_DO_HASH) & ((interface_mode != OP_INT_VML) | vml_done));
			end
			C_LOAD_NONCE: begin 
				bdi		 		= nonce[load_count];
				bdi_type	 	= D_NONCE;
				bdi_valid_next 	= ~load_done;
				bdi_eot_next 	= (nonce_size == load_count_next);
			end
			C_LOAD_PTCT: begin 
				bdi		 		= ptct[load_count];
				bdi_type		= D_PTCT;
				bdi_valid_next 	= ~load_done;
				bdi_eot_next 	= ((ptct_size == load_count_next) & bdi_ready & ((interface_mode != OP_INT_VML) | vml_done));
				bdi_eoi_next 	= ((ptct_size == load_count_next) & bdi_ready & ((interface_mode != OP_INT_VML) | vml_done));
			end
			C_LOAD_TAG: begin 
				bdi				= tag[load_count];
				bdi_type	 	= D_TAG;
				bdi_valid_next 	= ~load_done;
				bdi_eot_next 	= (tag_size == load_count_next);
			end
			default: begin
				bdi				= 32'b0;
				bdi_type	 	= D_NULL;
				bdi_valid_next 	= FALSE;
			end
		endcase
	end

	// sychronous state logic
	always_ff @(posedge core_clk) begin : core_load_seq
		if (rst == TRUE) begin
			load_count 	<= 3'b0;
			key_valid	<= FALSE;
		end else begin
			load_count 	<= load_count_next;
			key_valid 	<= key_valid_next;
			bdi_valid 	<= bdi_valid_next;
			bdi_eot 	<= bdi_eot_next;
			bdi_eoi 	<= bdi_eoi_next;
		end
	end
	//end core load logic


	/////////////////////
	// core read logic //
	/////////////////////

	logic [4:0] core_out_count;

	always_ff @(posedge core_clk) begin : core_read
		if (rst) begin
			core_out_count <= 5'b0;
			ptct_out[0] <= 32'b0; ptct_out[1] <= 32'b0; ptct_out[2] <= 32'b0; ptct_out[3] <= 32'b0;
			tag_out[0] 	<= 32'b0; tag_out[1]  <= 32'b0; tag_out[2]  <= 32'b0; tag_out[3]  <= 32'b0;
			hash_out[0] <= 32'b0; hash_out[1] <= 32'b0; hash_out[2] <= 32'b0; hash_out[3] <= 32'b0; 
			hash_out[4] <= 32'b0; hash_out[5] <= 32'b0; hash_out[6] <= 32'b0; hash_out[7] <= 32'b0;
		end else begin
			if (bdo_eot)
				core_out_count <= 5'b0;
			else if (bdo_valid && bdo_ready) 
				core_out_count <= core_out_count + 1;
			else 
				core_out_count <= core_out_count;
			ptct_out[load_count] 	 <= (bdo_type == D_PTCT & bdo_valid) ? bdo : ptct_out[load_count];
			tag_out[core_out_count]  <=	(bdo_type == D_TAG & bdo_valid) ? bdo : tag_out[core_out_count];
			hash_out[core_out_count] <= (bdo_type == D_HASH & bdo_valid) ? bdo : hash_out[core_out_count];
		end

	end
	// end core read logic


	//////////////////
	// piso convert //
	//////////////////

	logic [31:0] piso,piso_next;
	logic [3:0] reg_count_next;
	logic [4:0] piso_count_next;
	
	assign sdo = valid ? piso[31] : 1'b0;
	assign valid = (current_state == I_RETURN_PTCT | current_state == I_RETURN_TAG | current_state == I_RETURN_HASH);

	always_comb begin : piso_comb
		piso_next = piso;
		reg_count_next = reg_count;
		piso_count_next = piso_count;
		if (current_state == I_RETURN_SYNC | current_state == I_RETURN_BREAK) begin
			case (next_state)
				I_RETURN_PTCT: piso_next = ptct_out[0];
				I_RETURN_TAG: piso_next = tag_out[0];
				I_RETURN_HASH: piso_next = hash_out[0];
				default: piso_next = 32'b0;
			endcase
		end
		else if (valid) begin	
			if (piso_count == 5'd31) begin
				if (current_state == I_RETURN_HASH) begin
					if (reg_count == 3'd7) begin
						reg_count_next = 4'b0;
						piso_next = hash_out[0];
					end
					else begin
						reg_count_next = reg_count + 1;
						piso_next = hash_out[reg_count+1];
					end
				end
				else begin
					if (return_done) begin
						reg_count_next = 4'b0; 
					end
					else begin
						reg_count_next = reg_count + 4'b1;
						case (next_state)
							I_RETURN_PTCT: piso_next = ptct_out[reg_count+1];
							I_RETURN_TAG: piso_next = tag_out[reg_count+1];
							default: piso_next = 32'b0;
						endcase
					end
				end
				piso_count_next = 5'b00000;
			end
			// shift
			else begin 
				piso_next = {piso[30:0],1'b0};
				piso_count_next = valid ? piso_count + 5'b1 : piso_count;
			end
		end
		else begin
			reg_count_next = 4'b0;
			piso_count_next = 5'b00000;
		end
	end

	always_ff @(posedge interface_clk) begin : piso_seq
		if (rst == TRUE) begin
			piso <= 32'b0;
			reg_count <= 4'b0;
			piso_count <= 5'b00000;
		end
		else begin
			piso <= piso_next;
			reg_count <= reg_count_next;
			piso_count <= piso_count_next;
		end
	end
	// end piso convert
	
	// define config flags
	assign hash = (core_mode == OP_DO_HASH);
	assign decrypt = (core_mode == OP_DO_DEC);

	// define read flags
	assign bdo_ready = (core_state == C_LOAD_PTCT | (core_state == C_WAIT_OUT & (core_mode == OP_DO_ENC | core_mode == OP_DO_HASH)));
	assign auth_ready = (core_state == C_WAIT_OUT) & (core_mode == OP_DO_DEC);

	// instantiate the spi interface and convert for the ascon core module
	ascon_core core(
		.clk(core_clk), 		//i
		.rst(rst), 				//i
		.key(key_w), 			//i 32
		.key_valid(key_valid), 	//i
		.key_ready(key_ready),	//o
		.bdi(bdi), 				//i 32
		.bdi_valid(bdi_valid), 	//i
		.bdi_ready(bdi_ready),	//o
		.bdi_type(bdi_type), 	//i 4
		.bdi_eot(bdi_eot), 		//i
		.bdi_eoi(bdi_eoi), 		//i
		.decrypt(decrypt), 		//i
		.hash(hash), 			//i
		.bdo(bdo), 				//o 32
		.bdo_valid(bdo_valid),	//o
		.bdo_ready(bdo_ready), 	//i
		.bdo_type(bdo_type), 	//o 4
		.bdo_eot(bdo_eot),		//o
		.auth(auth),			//o
		.auth_valid(auth_valid),//o
		.auth_ready(auth_ready),//i
		.trig(trig)				//o
	);
	
endmodule // ascon_spi