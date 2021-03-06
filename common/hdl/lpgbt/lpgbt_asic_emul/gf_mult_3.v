module gf_mult_3(op1, op2, res);

// -------------------------------------------------------------------------- //
// ------------- Triple Modular Redundancy Generator Directives ------------- //
// -------------------------------------------------------------------------- //
// tmrg do_not_touch
// -------------------------------------------------------------------------- //

	input      [2:0] op1;
	input      [2:0] op2;
	output     [2:0] res;

	assign res[0] = (op1[1] & op2[2]) ^ (op1[2] & op2[1]) ^ (op1[0] & op2[0]);
	assign res[1] = (op1[1] & op2[0]) ^ (op1[0] & op2[1]) ^ (op1[2] & op2[1]) ^ (op1[1] & op2[2]) ^ (op1[2] & op2[2]);
	assign res[2] = (op1[2] & op2[0]) ^ (op1[1] & op2[1]) ^ (op1[0] & op2[2]) ^ (op1[2] & op2[2]);

endmodule
