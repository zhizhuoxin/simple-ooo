`include "OOO_v1/param.v"


module memd(
  input clk,
  input rst,

  input  [`MEMD_SIZE-1:0] in_addr,
  input in_valid,
 
  output [`REG_LEN-1:0] out_data,
  output out_valid,

  output ready,
);

  reg [`REG_LEN-1:0] memd [`MEMD_SIZE-1:0];

  reg [`REG_LEN-1:0] out_data_buf;

  // State of memd that determines the latency
  // > 1 -> not ready, no output, -1
  // = 1 -> ready, output, -1
  // = 0 -> ready, no output, not changed
  reg [`MEMD_SIZE-1:0] counter;

  assign ready = (counter == 0) || (counter == 1);
  assign out_valid = counter == 1;
  assign out_data = out_valid ? out_data_buf : 0;

  always @(posedge clk) begin
    if (rst) begin
`ifdef INIT_MEMD_CUSTOMIZED
        memd[0] <= 2;
        memd[1] <= 1;
        memd[2] <= 0;
        memd[3] <= 0;
`else
      for (i=0; i<`MEMD_SIZE; i=i+1)
        memd[i] <= 0;
`endif
      counter <= 0;
    end else begin
      if (ready && in_valid) begin
        out_data_buf <= memd[in_addr];
        counter <= in_addr + 1;
      end else if (in_addr > 0) begin
        counter <= counter - 1;
      end
    end
  end


endmodule
