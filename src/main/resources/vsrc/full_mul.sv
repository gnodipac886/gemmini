module PE_BLACKBOX #(
	parameter INPUT_W 	= 8,
	parameter OUTPUT_W 	= 20,
	parameter C_W 		= 32,
	parameter SEXT_W 	= C_W - OUTPUT_W
) (
	input 	logic							clock,
	input 	logic	[INPUT_W  - 1	:0]  	in_a,
	input 	logic	[OUTPUT_W - 1	:0] 	in_b,
	input 	logic	[OUTPUT_W - 1	:0] 	in_d,
	output 	logic	[INPUT_W  - 1	:0]  	out_a,
	output 	logic	[OUTPUT_W - 1	:0] 	out_b,
	output 	logic	[OUTPUT_W - 1	:0] 	out_c,
	input 	logic							in_control_dataflow,
	input 	logic							in_control_propagate,
	input 	logic	[4:0]  					in_control_shift,
	output 	logic							out_control_dataflow,
	output 	logic							out_control_propagate,
	output 	logic	[4:0]  					out_control_shift,
	input 	logic	[2:0]  					in_id,
	output 	logic	[2:0]  					out_id,
	input 	logic							in_last,
	output 	logic							out_last,
	input 	logic							in_valid,
	output 	logic							out_valid,
	output 	logic							bad_dataflow
);

	logic [C_W-1:0] 		c1, c2, c1_shifted, c2_shifted;
	logic 					last_s;
	logic 					flip;
	logic [4:0] 			shift_offset;

	logic [INPUT_W-1:0] 	mac_m1;
	logic [INPUT_W-1:0] 	mac_m2;
	logic [C_W-1:0]			mac_self;
	logic [C_W-1:0] 		mac_acc;

	assign c1_shifted				= c1 >> shift_offset;
	assign c2_shifted				= c2 >> shift_offset;

	assign out_a 					= in_a;
	assign out_control_dataflow 	= in_control_dataflow;
	assign out_control_propagate 	= in_control_propagate;
	assign out_control_shift 		= in_control_shift;
	assign out_id 					= in_id;
	assign out_last 				= in_last;
	assign out_valid 				= in_valid;

	assign flip 					= last_s != in_control_propagate;
	assign shift_offset 			= flip ? in_control_shift : 5'h0;

	// assign bad_dataflow 			= ~in_control_dataflow ? 1'h0 : (in_control_dataflow ? 1'h0 : 1'h1);

	two_mac #(
		.INPUT_W(INPUT_W),
		.OUTPUT_W(OUTPUT_W),
		.C_W(C_W)
	) mac_unit (
		.m1(mac_m1),
		.m2(mac_m2),
		.self(mac_self),
		.acc(mac_acc)
	);

	typedef enum logic[1:0] {
		OS_P 	= 2'b01,
		OS_NP	= 2'b00,
		WS_P	= 2'b11,
		WS_NP	= 2'b10
	} DF_t;

	function set_defaults();
		bad_dataflow		= 1'b0;
		out_c				= '0;
		out_b				= '0;

		mac_m1				= in_a;
		mac_m2				= '0;
		mac_self			= '0;
	endfunction

	always_comb begin
		set_defaults();
		
		unique case ({in_control_dataflow, in_control_propagate})
			OS_P	: begin 
				out_c 		= c1_shifted[OUTPUT_W-1:0];
				out_b 		= in_b;
				
				mac_m2		= in_b[INPUT_W-1:0];
				mac_self 	= c2;
			end 

			OS_NP	: begin 
				out_c 		= c2_shifted[OUTPUT_W-1:0];
				out_b 		= in_b;

				mac_m2		= in_b[INPUT_W-1:0];
				mac_self 	= c1;
			end 

			WS_P	: begin 
				out_c 		= c1;
				out_b 		= mac_acc;

				mac_m2		= c2[INPUT_W-1:0];
				mac_self 	= in_b;
			end 

			WS_NP	: begin 
				out_c 		= c2;
				out_b 		= mac_acc;

				mac_m2		= c1[INPUT_W-1:0];
				mac_self 	= in_b;
			end 

			default: begin 
				bad_dataflow = 1'b1;
			end 
		endcase
	end

	always_ff @(posedge clock ) begin
		if (in_valid) begin 
			last_s <= in_control_propagate;
		
			unique case ({in_control_dataflow, in_control_propagate})
				OS_P	: begin 
					c2	<= mac_acc;
					c1	<= {{SEXT_W{in_d[OUTPUT_W-1]}}, in_d};
				end 

				OS_NP	: begin 
					c1	<= mac_acc;
					c2	<= {{SEXT_W{in_d[OUTPUT_W-1]}}, in_d};
				end 

				WS_P	: begin 
					c1	<= {{SEXT_W{in_d[OUTPUT_W-1]}}, in_d};
				end 

				WS_NP	: begin 
					c2	<= {{SEXT_W{in_d[OUTPUT_W-1]}}, in_d};
				end 

				default:;
			endcase
		end 
	end

endmodule

module two_mac #(
	parameter INPUT_W 	= 8,
	parameter OUTPUT_W 	= 20,
	parameter C_W 		= 32
) (
	input 	logic [INPUT_W-1:0] 	m1,
	input 	logic [INPUT_W-1:0] 	m2,
	input 	logic [C_W-1:0]			self,
	output 	logic [C_W-1:0] 		acc
);

	assign acc = m1 * m2 + self;
	// assign acc = (m1 << m2[0]) + (m1 << (m2[1] << m2 & 4'b0010)) + (m1 << (m2[2] << m2 & 4'b0100)) + (m1 << (m2[3] << m2 & 4'b1000)) + (self)
	// logic [2:0] first_term, second_term;
	// logic is_one_term;
	// logic sign;
	// logic [C_W - 1:0] m1_shifted_first, m1_shifted_second;

	// assign first_term 			= m2[5:3];
	// assign second_term 			= m2[2:0];
	// assign is_one_term			= m2[6];
	// assign sign 				= m2[7];

	// assign m1_shifted_first 	= m1 << first_term;
	// assign m1_shifted_second 	= m1 << second_term;

	// function three_input_add(logic [C_W - 1:0] a, logic [C_W - 1:0] b, logic [C_W - 1:0] c);
	// 	return a + b + c;
	// endfunction

	// always_comb begin
	// 	acc 			= '0;

	// 	if (is_one_term) begin 
	// 		// acc			= m1_shifted_first + self;
	// 		acc			= three_input_add(m1_shifted_first, self, 0);
	// 	end else begin 
	// 		unique case(sign)
	// 			1'b1: begin 
	// 				// acc = (m1_shifted_first) - (m1_shifted_second) + self;
	// 				acc = three_input_add(m1_shifted_first, self, -m1_shifted_second);
	// 			end 

	// 			1'b0: begin 
	// 				// acc = (m1_shifted_first) + (m1_shifted_second) + self;
	// 				acc = three_input_add(m1_shifted_first, self, m1_shifted_second);
	// 			end 

	// 			default:;
	// 		endcase
	// 	end 
	// end

endmodule