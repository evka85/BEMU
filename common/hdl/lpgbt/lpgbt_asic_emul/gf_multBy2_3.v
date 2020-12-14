module gf_multBy2_3(op, res);

// -------------------------------------------------------------------------- //
// ------------- Triple Modular Redundancy Generator Directives ------------- //
// -------------------------------------------------------------------------- //
// tmrg do_not_touch
// -------------------------------------------------------------------------- //

	input      [2:0] op;
	output reg [2:0] res;

	always @(op) begin
		res = {op[1], op[0]^op[2], op[2]};
	end

endmodule