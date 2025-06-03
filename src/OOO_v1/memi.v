
`include "OOO_v1/param.v"


module memi(
  input clk,
  input rst,

  input  [`MEMI_SIZE_LOG-1:0] req_addr,
  output [`INST_LEN-1     :0] resp_data
);

  reg [`INST_LEN-1:0] array [`MEMI_SIZE-1:0];

  // STEP Read
  assign resp_data = array[req_addr];

  // STEP Init
  always @(posedge clk) begin
    if (rst) begin
`ifdef INIT_MEMI_CUSTOMIZED
      array[0] <= {`INST_SIZE_LOG'd`INST_OP_LD,  `REG_LEN'd0, `RF_SIZE_LOG'd0, `RF_SIZE_LOG'd1}; // R1 = Mem[R0]
      array[1] <= {`INST_SIZE_LOG'd`INST_OP_ADD, `REG_LEN'd0, `RF_SIZE_LOG'd0, `RF_SIZE_LOG'd0};
      array[2] <= {`INST_SIZE_LOG'd`INST_OP_BR,  `REG_LEN'd5, `RF_SIZE_LOG'd0, `RF_SIZE_LOG'd0}; // If (R0 == 0) PC <- PC + 5
      array[3] <= {`INST_SIZE_LOG'd`INST_OP_LD,  `REG_LEN'd1, `RF_SIZE_LOG'd0, `RF_SIZE_LOG'd3}; // R3 = Mem[R1]
      array[4] <= {`INST_SIZE_LOG'd`INST_OP_ADD, `REG_LEN'd0, `RF_SIZE_LOG'd0, `RF_SIZE_LOG'd0};
      array[5] <= {`INST_SIZE_LOG'd`INST_OP_ADD, `REG_LEN'd0, `RF_SIZE_LOG'd0, `RF_SIZE_LOG'd0};
      array[6] <= {`INST_SIZE_LOG'd`INST_OP_ADD, `REG_LEN'd0, `RF_SIZE_LOG'd0, `RF_SIZE_LOG'd0};
      array[7] <= {`INST_SIZE_LOG'd`INST_OP_MUL, `REG_LEN'd0, `RF_SIZE_LOG'd0, `RF_SIZE_LOG'd0}; // MUL
`else
      integer i;
      for (i=0; i<`MEMI_SIZE; i=i+1)
        array[i] <= 0;
`endif
    end
  end

endmodule

