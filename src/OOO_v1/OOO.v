
`include "OOO_v1/param.v"

`include "OOO_v1/decode.v"
`include "OOO_v1/execute.v"

`include "OOO_v1/rf.v"
`include "OOO_v1/memi.v"


module OOO(
  input clk,
  input rst
);
  integer i, j;
  genvar p;

  // STEP: PC
  reg  [`MEMI_SIZE_LOG-1:0] F_pc;

  // Fetch PC is_public
  reg  F_pc_is_public;

  always @(posedge clk) begin
    if (rst) F_pc <= 0;
    else     F_pc <= F_next_pc;
  end

  // Fetch PC is_public cond
  always @(posedge clk) begin
    F_pc_is_public <= // F_next_pc_is_public
      ROB_head_is_public && ROB_tail_is_public &&
      ROB_state_is_public[ROB_head] && // C_valid_is_public
      ROB_is_br_is_public[ROB_head] && ROB_predicted_taken_is_public[ROB_head] && ROB_taken[ROB_head] && // C_squash_is_public
      ((C_valid && C_squash) ? 
          ROB_next_pc_is_public[ROB_head] : // C_next_pc_is_public // TODO
          ROB_state_is_public[ROB_tail] && // ROB_full_is_public
            F_pc_is_public)
      // => F_inst_is_public (according to imem)
      // => F_is_br_is_public && F_rs1_br_offset_is_public (according to decode_instance)
      // F_predicted_taken_is_public since F_predicted_taken = 0

    // F_next_pc =
    // (C_valid && C_squash)?           C_next_pc :
    // ROB_full?                        F_pc :
    // (F_is_br && F_predicted_taken)?  F_pc+F_rs1_br_offset :
    //                                  F_pc+1;
  end



  // STEP: Fetch
  wire [`INST_LEN-1:0] F_inst;
  memi memi_instance(
    .clk(clk), .rst(rst),
    .req_addr(F_pc), .resp_data(F_inst)
  );




  // STEP: Decode
  wire [`INST_SIZE_LOG-1:0] F_opcode;

  wire                      F_rs1_used;
  wire [`REG_LEN-1      :0] F_rs1_imm;
  wire [`MEMI_SIZE_LOG-1:0] F_rs1_br_offset;
  wire [`RF_SIZE_LOG-1  :0] F_rs1;

  wire                      F_rs2_used;
  wire [`RF_SIZE_LOG-1  :0] F_rs2;

  wire                    F_wen;
  wire [`RF_SIZE_LOG-1:0] F_rd;
  wire                    F_rd_data_use_alu;

  wire F_mem_valid;

  wire F_is_br;

  decode decode_instance(
    .inst(F_inst), // input
    .opcode(F_opcode),
    .rs1_used(F_rs1_used), .rs1_imm(F_rs1_imm), .rs1_br_offset(F_rs1_br_offset), .rs1(F_rs1),
    .rs2_used(F_rs2_used), .rs2(F_rs2),
    .wen(F_wen), .rd(F_rd), .rd_data_use_alu(F_rd_data_use_alu),
    .mem_valid(F_mem_valid),
    .is_br(F_is_br)
  );




  // STEP: rf Read Write
  wire [`REG_LEN-1:0] F_rs1_data_rf;
  wire [`REG_LEN-1:0] F_rs2_data_rf;
  rf rf_instance(
    .clk(clk), .rst(rst),
    .rs1(F_rs1), .rs1_data(F_rs1_data_rf),
    .rs2(F_rs2), .rs2_data(F_rs2_data_rf),
    .wen(C_valid && C_wen), .rd(C_rd), .rd_data(C_rd_data)
  );




  // STEP: PC Prediction
  wire                      F_predicted_taken;
  wire [`MEMI_SIZE_LOG-1:0] F_next_pc;

  assign F_predicted_taken = 1'b0;
  assign F_next_pc = (C_valid && C_squash)?           C_next_pc :
                     ROB_full?                        F_pc :
                     (F_is_br && F_predicted_taken)?  F_pc+F_rs1_br_offset :
                                                      F_pc+1;




  // STEP: Rename Table
  reg  [`RF_SIZE-1     :0] renameTB_valid;
  reg  [`ROB_SIZE_LOG-1:0] renameTB_ROBlink [`RF_SIZE-1:0];

  // Rename Table is_public
  reg  [`RF_SIZE-1:0] renameTB_valid_is_public;
  reg  [`RF_SIZE-1:0] renameTB_ROBlink_is_public;

  wire                F_rs1_stall;
  wire [`REG_LEN-1:0] F_rs1_data;
  wire                F_rs2_stall;
  wire [`REG_LEN-1:0] F_rs2_data;

  // STEP.: update rename table entries
  wire renameTB_clearEntry, renameTB_addEntry, renameTB_clearAddConflict;
  assign renameTB_clearEntry = C_valid && C_wen && (renameTB_ROBlink[C_rd]==ROB_head);
  assign renameTB_addEntry   = !ROB_full && F_wen;
  assign renameTB_clearAddConflict = renameTB_addEntry && renameTB_clearEntry && F_rd==C_rd;
  always @(posedge clk) begin
    if (rst)        begin 
      for (i=0; i<`RF_SIZE; i=i+1) begin
        renameTB_valid[i]         <= 1'b0;
      end
    end

    else if (C_squash && C_valid)
      for (i=0; i<`RF_SIZE; i=i+1) begin
        renameTB_valid[i]         <= 1'b0;
      end

    else begin
      if (renameTB_clearEntry && !renameTB_clearAddConflict) begin
        renameTB_valid        [C_rd] <= 1'b0;
      end

      if (renameTB_addEntry) begin
        renameTB_valid[F_rd]         <= 1'b1;
      end
    end
  end

  always @(posedge clk) begin
    if (!ROB_full && F_wen) renameTB_ROBlink[F_rd] <= ROB_tail;
  end

  // Rename Table is_public cond
  always @(posedge clk) begin
    for (i = 0; i < `RF_SIZE; i=i+1) begin
      // Don't forget if conditions and array indicies!!!
      // Don't forget self (for entries that are not updated in one cycle)
      renameTB_valid_is_public[i] <= 
        renameTB_valid_is_public &&
        ROB_head_is_public && 
        ROB_is_br_is_public[ROB_head] && ROB_predicted_taken_is_public[ROB_head] && ROB_taken[ROB_head] && // C_squash_is_public
        ROB_state_is_public[ROB_head] && // C_valid_is_public
        ROB_wen_is_public[ROB_head] && ROB_rd[ROB_head] && renameTB_ROBlink[i] // renameTB_clearEntry_is_public = C_valid_is_public && C_wen_is_public && C_rd_is_public && renameTB_ROBlink_is_public && ROB_head_is_public 
        ROB_state_is_public[ROB_tail] && F_pc_is_public &&  // renameTB_clearAddConflict_is_public = renameTB_addEntry_is_public && renameTB_clearEntry_is_public && F_rd_is_public && C_rd_is_public
        // C_rd_is_public (sat)
        // renameTB_addEntry_is_public = ROB_full_is_public && F_wen_is_public (sat)
        // F_rd_is_public (sat)
    end

    for (i = 0; i < `RF_SIZE; i=i+1) begin
      renameTB_ROBlink_is_public[i] <=
        renameTB_ROBlink_is_public[i] &&
        ROB_tail_is_public && ROB_state_is_public[ROB_tail] && // ROB_full_is_public
        F_pc_is_public && // F_wen_is_public && F_rd_is_public
        // ROB_tail_is_public
    end
  end


  // STEP.: use renameTB to read data from either reg or ROB or stall
  assign F_rs1_stall =
    F_rs1_used && renameTB_valid[F_rs1] &&
    !(ROB_state[renameTB_ROBlink[F_rs1]]==`FINISHED);
  assign F_rs2_stall =
    F_rs2_used && renameTB_valid[F_rs2] &&
    !(ROB_state[renameTB_ROBlink[F_rs2]]==`FINISHED);

  assign F_rs1_data = renameTB_valid[F_rs1]?
                      ROB_rd_data[renameTB_ROBlink[F_rs1]]:
                      F_rs1_data_rf;
  assign F_rs2_data = renameTB_valid[F_rs2]?
                      ROB_rd_data[renameTB_ROBlink[F_rs2]]:
                      F_rs2_data_rf;




  // STEP: ROB
  reg  [`ROB_STATE_LEN-1:0] ROB_state [`ROB_SIZE-1:0];

  reg  [`MEMI_SIZE_LOG-1:0] ROB_pc [`ROB_SIZE-1:0];
  reg  [`INST_SIZE_LOG-1:0] ROB_op [`ROB_SIZE-1:0];

  reg  [`ROB_SIZE-1     :0] ROB_rs1_stall;
  reg  [`REG_LEN-1      :0] ROB_rs1_imm       [`ROB_SIZE-1:0];
  reg  [`MEMI_SIZE_LOG-1:0] ROB_rs1_br_offset [`ROB_SIZE-1:0];
  reg  [`REG_LEN-1      :0] ROB_rs1_data      [`ROB_SIZE-1:0];
  reg  [`ROB_SIZE_LOG-1 :0] ROB_rs1_ROBlink   [`ROB_SIZE-1:0];

  reg  [`ROB_SIZE-1     :0] ROB_rs2_stall;
  reg  [`REG_LEN-1      :0] ROB_rs2_data      [`ROB_SIZE-1:0];
  reg  [`ROB_SIZE_LOG-1 :0] ROB_rs2_ROBlink   [`ROB_SIZE-1:0];

  reg  [`ROB_SIZE-1     :0] ROB_mem_valid;

  reg  [`ROB_SIZE-1     :0] ROB_wen;
  reg  [`RF_SIZE_LOG-1  :0] ROB_rd      [`ROB_SIZE-1:0];
  reg  [`ROB_SIZE-1     :0] ROB_rd_data_use_alu;
  reg  [`REG_LEN-1      :0] ROB_rd_data [`ROB_SIZE-1:0];

  reg  [`ROB_SIZE-1     :0] ROB_is_br;
  reg  [`ROB_SIZE-1     :0] ROB_predicted_taken;
  reg  [`ROB_SIZE-1     :0] ROB_taken;
  reg  [`MEMI_SIZE_LOG-1:0] ROB_next_pc [`ROB_SIZE-1:0];

  reg  [`ROB_SIZE_LOG-1:0] ROB_head;
  reg  [`ROB_SIZE_LOG-1:0] ROB_tail;

  // ROB is_public
  reg  [`ROB_SIZE-1:0] ROB_state_is_public;

  reg  [`ROB_SIZE-1:0] ROB_pc_is_public;
  reg  [`ROB_SIZE-1:0] ROB_op_is_public;

  reg  [`ROB_SIZE-1:0] ROB_rs1_stall_is_public;
  reg  [`ROB_SIZE-1:0] ROB_rs1_imm_is_public;
  reg  [`ROB_SIZE-1:0] ROB_rs1_br_offset_is_public;
  reg  [`ROB_SIZE-1:0] ROB_rs1_data_is_public;
  reg  [`ROB_SIZE-1:0] ROB_rs1_ROBlink_is_public;

  reg  [`ROB_SIZE-1:0] ROB_rs2_stall_is_public;
  reg  [`ROB_SIZE-1:0] ROB_rs2_data_is_public;
  reg  [`ROB_SIZE-1:0] ROB_rs2_ROBlink_is_public;

  reg  [`ROB_SIZE-1:0] ROB_mem_valid_is_public;

  reg  [`ROB_SIZE-1:0] ROB_wen_is_public;
  reg  [`ROB_SIZE-1:0] ROB_rd_is_public;
  reg  [`ROB_SIZE-1:0] ROB_rd_data_use_alu_is_public;
  reg  [`ROB_SIZE-1:0] ROB_rd_data_is_public;

  reg  [`ROB_SIZE-1:0] ROB_is_br_is_public;
  reg  [`ROB_SIZE-1:0] ROB_predicted_taken_is_public;
  reg  [`ROB_SIZE-1:0] ROB_taken_is_public;
  reg  [`ROB_SIZE-1:0] ROB_next_pc_is_public;

  reg  ROB_head_is_public;
  reg  ROB_tail_is_public;

  wire ROB_full;
  wire ROB_empty;

  always @(posedge clk) begin
    if (rst) begin
      for (i=0; i<`ROB_SIZE; i=i+1) begin
        ROB_state[i] <= `IDLE;
      end
      ROB_head <= 0;
      ROB_tail <= 0;
    end

    // STEP.1: squash
    else if (C_valid && C_squash) begin
      for (i=0; i<`ROB_SIZE; i=i+1) begin
        ROB_state[i] <= `IDLE;
      end
      ROB_head <= 0;
      ROB_tail <= 0;
    end

    else begin
      // STEP.2: push
      if (!ROB_full) begin
        ROB_state[ROB_tail] <= `STALLED;

        ROB_pc[ROB_tail] <= F_pc;
        ROB_op[ROB_tail] <= F_opcode;

        ROB_rs1_stall      [ROB_tail] <= F_rs1_stall;
        ROB_rs1_imm        [ROB_tail] <= F_rs1_imm;
        ROB_rs1_br_offset  [ROB_tail] <= F_rs1_br_offset;
        ROB_rs1_data       [ROB_tail] <= F_rs1_data;
        ROB_rs1_ROBlink    [ROB_tail] <= renameTB_ROBlink[F_rs1];

        ROB_rs2_stall      [ROB_tail] <= F_rs2_stall;
        ROB_rs2_data       [ROB_tail] <= F_rs2_data;
        ROB_rs2_ROBlink    [ROB_tail] <= renameTB_ROBlink[F_rs2];

        ROB_wen            [ROB_tail] <= F_wen;
        ROB_rd             [ROB_tail] <= F_rd;
        ROB_rd_data_use_alu[ROB_tail] <= F_rd_data_use_alu;

        ROB_mem_valid      [ROB_tail] <= F_mem_valid;

        ROB_is_br          [ROB_tail] <= F_is_br;
        ROB_predicted_taken[ROB_tail] <= F_predicted_taken;

        ROB_tail <= ROB_tail + 1;
      end


      // STEP.3: wakeup
      for (i=0; i<`ROB_SIZE; i=i+1) begin
        if (ROB_state[i]==`STALLED &&
            !ROB_rs1_stall[i] && !ROB_rs2_stall[i]) begin
`ifdef DELAY_LOAD_COMMIT
          if (ROB_op[i] != `INST_OP_LD || i == ROB_head)
            ROB_state[i] <= `READY;
`else
          ROB_state [i] <= `READY;
`endif
        end
      end


      // STEP.4: execute
      for (i=0; i<`ROB_SIZE; i=i+1) begin
        if (ROB_state[i]==`READY) begin
          ROB_rd_data[i] <= ROB_rd_data_wire[i];
          ROB_taken  [i] <= ROB_taken_wire[i];
          ROB_next_pc[i] <= ROB_next_pc_wire[i];

          ROB_state[i] <= `FINISHED;
        end
      end


      // STEP.5: forward
      for (i=0; i<`ROB_SIZE; i=i+1) begin
        if (ROB_state[i]==`FINISHED) begin
          for (j=0; j<`ROB_SIZE; j=j+1) begin
            if (ROB_state[j]==`STALLED && ROB_rs1_stall[j] &&
                ROB_rs1_ROBlink[j]==i[`ROB_SIZE_LOG-1:0]) begin
              ROB_rs1_stall[j] <= 1'b0;
              ROB_rs1_data[j] <= ROB_rd_data[i];
            end

            if (ROB_state[j]==`STALLED && ROB_rs2_stall[j] &&
                ROB_rs2_ROBlink[j]==i[`ROB_SIZE_LOG-1:0]) begin
              ROB_rs2_stall[j] <= 1'b0;
              ROB_rs2_data[j] <= ROB_rd_data[i];
            end
          end
        end
      end


      // STEP.6: pop
      if (C_valid) begin
        ROB_state[ROB_head] <= `IDLE;
        ROB_head <= ROB_head + 1;
      end
    end
  end

  always @(posedge clk) begin
    for (i=0; i<`ROB_SIZE; i=i+1) begin
      // Note that ROB entries can affect each other!!! so only use ROB[i] may not be enough!!!
      // else if should consider all prior conditions!
      ROB_state_is_public[i] <=
        ROB_state_is_public[i] &&
        ROB_head_is_public && ROB_tail_is_public && // ROB_head ROB_tail
        ROB_state_is_public[ROB_head] && // C_valid
        ROB_is_br_is_public[ROB_head] && ROB_predicted_taken_is_public[ROB_head] && ROB_taken[ROB_head] && // C_squash
        ROB_state_is_public[ROB_tail] // ROB_full
        ROB_rs1_stall_is_public[i] && ROB_rs2_stall_is_public[i] // ROB_rs1_stall ROB_rs2_stall ROB_op

      ROB_pc_is_public[i] <= // push
        ROB_pc_is_public[i] &&
        ROB_head_is_public && ROB_tail_is_public && // ROB_head ROB_tail
        ROB_state_is_public[ROB_head] && // C_valid
        ROB_is_br_is_public[ROB_head] && ROB_predicted_taken_is_public[ROB_head] && ROB_taken[ROB_head] && // C_squash
        ROB_tail_is_public && ROB_state_is_public[ROB_tail] // ROB_full ROB_tail
        F_pc_is_public // F_pc_is_public

      ROB_op_is_public[i] <= // push
        ROB_op_is_public[i] &&
        ROB_head_is_public && ROB_tail_is_public && // ROB_head ROB_tail
        ROB_state_is_public[ROB_head] && // C_valid
        ROB_is_br_is_public[ROB_head] && ROB_predicted_taken_is_public[ROB_head] && ROB_taken[ROB_head] && // C_squash
        ROB_tail_is_public && ROB_state_is_public[ROB_tail] // ROB_full ROB_tail
        F_pc_is_public // F_pc_is_public

      ROB_rs1_stall_is_public[i] <= // push, forward
        ROB_rs1_stall_is_public[i] &&
        ROB_head_is_public && ROB_tail_is_public && // ROB_head ROB_tail
        ROB_state_is_public[ROB_head] && // C_valid
        ROB_is_br_is_public[ROB_head] && ROB_predicted_taken_is_public[ROB_head] && ROB_taken[ROB_head] && // C_squash
        ROB_tail_is_public && ROB_state_is_public[ROB_tail] // ROB_full ROB_tail
        F_pc_is_public && (&renameTB_valid_is_public) && (&ROB_state_is_public) && (&renameTB_ROBlink_is_public)
        // F_rs1_stall_is_public = F_rs1_used_is_public && F_rs1_is_public && renameTB_valid_is_public[:] && ROB_state_is_public[:] && renameTB_ROBlink_is_public[:]

      ROB_rs1_imm_is_public[i] <= // push
        ROB_rs1_imm_is_public[i] &&
        ROB_head_is_public && ROB_tail_is_public && // ROB_head ROB_tail
        ROB_state_is_public[ROB_head] && // C_valid
        ROB_is_br_is_public[ROB_head] && ROB_predicted_taken_is_public[ROB_head] && ROB_taken[ROB_head] && // C_squash
        ROB_tail_is_public && ROB_state_is_public[ROB_tail] // ROB_full ROB_tail
        F_pc_is_public // F_pc_is_public

      ROB_rs1_br_offset_is_public[i] <= // push
        ROB_rs1_imm_is_public[i] &&
        ROB_head_is_public && ROB_tail_is_public && // ROB_head ROB_tail
        ROB_state_is_public[ROB_head] && // C_valid
        ROB_is_br_is_public[ROB_head] && ROB_predicted_taken_is_public[ROB_head] && ROB_taken[ROB_head] && // C_squash
        ROB_tail_is_public && ROB_state_is_public[ROB_tail] // ROB_full ROB_tail
        F_pc_is_public // F_pc_is_public

      ROB_rs1_data_is_public <= 0 // TODO

      ROB_rs1_ROBlink_is_public[i] <= // push
        ROB_rs1_ROBlink_is_public[i] &&
        ROB_head_is_public && ROB_tail_is_public && // ROB_head ROB_tail
        ROB_state_is_public[ROB_head] && // C_valid
        ROB_is_br_is_public[ROB_head] && ROB_predicted_taken_is_public[ROB_head] && ROB_taken[ROB_head] && // C_squash
        ROB_tail_is_public && ROB_state_is_public[ROB_tail] // ROB_full ROB_tail
        F_pc_is_public // F_pc_is_public
        renameTB_ROBlink

      ROB_rs2_stall_is_public[i] <= // push, forward
        ROB_rs2_stall_is_public[i] &&
        ROB_head_is_public && ROB_tail_is_public && // ROB_head ROB_tail
        ROB_state_is_public[ROB_head] && // C_valid
        ROB_is_br_is_public[ROB_head] && ROB_predicted_taken_is_public[ROB_head] && ROB_taken[ROB_head] && // C_squash
        ROB_tail_is_public && ROB_state_is_public[ROB_tail] // ROB_full ROB_tail
        F_pc_is_public && (&renameTB_valid_is_public) && (&ROB_state_is_public) && (&renameTB_ROBlink_is_public)
        // F_rs2_stall_is_public = F_rs2_used_is_public && F_rs2_is_public && renameTB_valid_is_public[:] && ROB_state_is_public[:] && renameTB_ROBlink_is_public[:]

      ROB_rs2_data_is_public <= 0 // TODO

      ROB_rs2_ROBlink_is_public[i] <= // push
        ROB_rs2_ROBlink_is_public[i] &&
        ROB_head_is_public && ROB_tail_is_public && // ROB_head ROB_tail
        ROB_state_is_public[ROB_head] && // C_valid
        ROB_is_br_is_public[ROB_head] && ROB_predicted_taken_is_public[ROB_head] && ROB_taken[ROB_head] && // C_squash
        ROB_tail_is_public && ROB_state_is_public[ROB_tail] // ROB_full ROB_tail
        F_pc_is_public // F_pc_is_public
        renameTB_ROBlink

      ROB_mem_valid_is_public[i] <= // push
        ROB_mem_valid_is_public[i] &&
        ROB_head_is_public && ROB_tail_is_public && // ROB_head ROB_tail
        ROB_state_is_public[ROB_head] && // C_valid
        ROB_is_br_is_public[ROB_head] && ROB_predicted_taken_is_public[ROB_head] && ROB_taken[ROB_head] && // C_squash
        ROB_tail_is_public && ROB_state_is_public[ROB_tail] // ROB_full ROB_tail
        F_pc_is_public // F_pc_is_public

      ROB_wen_is_public[i] <= // push
        ROB_wen_is_public[i] &&
        ROB_head_is_public && ROB_tail_is_public && // ROB_head ROB_tail
        ROB_state_is_public[ROB_head] && // C_valid
        ROB_is_br_is_public[ROB_head] && ROB_predicted_taken_is_public[ROB_head] && ROB_taken[ROB_head] && // C_squash
        ROB_tail_is_public && ROB_state_is_public[ROB_tail] // ROB_full ROB_tail
        F_pc_is_public // F_pc_is_public

      ROB_rd_is_public[i] <= // push
        ROB_rd_is_public[i] &&
        ROB_head_is_public && ROB_tail_is_public && // ROB_head ROB_tail
        ROB_state_is_public[ROB_head] && // C_valid
        ROB_is_br_is_public[ROB_head] && ROB_predicted_taken_is_public[ROB_head] && ROB_taken[ROB_head] && // C_squash
        ROB_tail_is_public && ROB_state_is_public[ROB_tail] // ROB_full ROB_tail
        F_pc_is_public // F_pc_is_public

      ROB_rd_data_use_alu_is_public[i] <= // push
        ROB_rd_data_use_alu_is_public[i] &&
        ROB_head_is_public && ROB_tail_is_public && // ROB_head ROB_tail
        ROB_state_is_public[ROB_head] && // C_valid
        ROB_is_br_is_public[ROB_head] && ROB_predicted_taken_is_public[ROB_head] && ROB_taken[ROB_head] && // C_squash
        ROB_tail_is_public && ROB_state_is_public[ROB_tail] // ROB_full ROB_tail
        F_pc_is_public // F_pc_is_public

      ROB_rd_data_is_public <= 0 // TODO

      ROB_is_br_is_public[i] <= // push
        ROB_is_br_is_public[i] &&
        ROB_head_is_public && ROB_tail_is_public && // ROB_head ROB_tail
        ROB_state_is_public[ROB_head] && // C_valid
        ROB_is_br_is_public[ROB_head] && ROB_predicted_taken_is_public[ROB_head] && ROB_taken[ROB_head] && // C_squash
        ROB_tail_is_public && ROB_state_is_public[ROB_tail] // ROB_full ROB_tail
        F_pc_is_public // F_pc_is_public

      ROB_predicted_taken_is_public[i] <= // push
        ROB_predicted_taken_is_public[i] &&
        ROB_head_is_public && ROB_tail_is_public && // ROB_head ROB_tail
        ROB_state_is_public[ROB_head] && // C_valid
        ROB_is_br_is_public[ROB_head] && ROB_predicted_taken_is_public[ROB_head] && ROB_taken[ROB_head] && // C_squash
        ROB_tail_is_public && ROB_state_is_public[ROB_tail] // ROB_full ROB_tail

      ROB_taken_is_public[i] <= 0 // TODO !!! it might not be public!!!
        // ROB_taken_is_public[i] &&
        // ROB_head_is_public && ROB_tail_is_public && // ROB_head ROB_tail
        // ROB_state_is_public[ROB_head] && // C_valid
        // ROB_is_br_is_public[ROB_head] && ROB_predicted_taken_is_public[ROB_head] && ROB_taken[ROB_head] && // C_squash
        // ROB_taken_wire

      ROB_next_pc_is_public[i] <= // TODO !!! it might not be public!!!
        ROB_next_pc_is_public[i] &&
        ROB_head_is_public && ROB_tail_is_public && // ROB_head ROB_tail
        ROB_state_is_public[ROB_head] && // C_valid
        ROB_is_br_is_public[ROB_head] && ROB_predicted_taken_is_public[ROB_head] && ROB_taken[ROB_head] && // C_squash
        ROB_rs2_data[i] && // TODO!!!
        ROB_is_br_is_public[i] && ROB_pc_is_public[i] && ROB_rs1_br_offset_is_public[i]

      ROB_head_is_public <= // squash, pop
        ROB_head_is_public && ROB_tail_is_public &&
        ROB_state_is_public[ROB_head] && // C_valid
        ROB_is_br_is_public[ROB_head] && ROB_predicted_taken_is_public[ROB_head] && ROB_taken[ROB_head] && // C_squash

      ROB_tail_is_public <= // squash, push
        ROB_head_is_public & ROB_tail_is_public &&
        ROB_state_is_public[ROB_head] && // C_valid
        ROB_is_br_is_public[ROB_head] && ROB_predicted_taken_is_public[ROB_head] && ROB_taken[ROB_head] && // C_squash
        ROB_state[ROB_tail]

    end
  end

  assign ROB_full  = ROB_state[ROB_tail] != `IDLE;
  assign ROB_empty = ROB_state[ROB_head] == `IDLE;

  wire [`MEMD_SIZE_LOG-1:0] ROB_mem_addr[`ROB_SIZE-1:0];
  wire [`ROB_SIZE-1:0]      ROB_mem_addr_is_public;
  generate for(p=0; p<`ROB_SIZE; p=p+1) begin
    assign ROB_mem_addr[p] = (ROB_state[p]==`READY && ROB_mem_valid[p]) ? mem_addr[p] : 0;
    // assign ROB_mem_addr[p] = (ROB_state[p]==`READY && ROB_mem_valid[p]) ? mem_addr[p] : 1;

    assign ROB_mem_addr_is_public[p] =
      ROB_state_is_public[p] && ROB_mem_valid_is_public[p] &&
      ((ROB_state[p]==`READY && ROB_mem_valid[p]) ? mem_addr_is_public[p] : 1);
    // TODO!!!
    // Lemma: (ROB_state[p]==`READY && ROB_mem_valid[p]) <=> p = ROB_head

    assign mem_addr_is_public[p] = ROB_rs1_data_is_public[p];

  end endgenerate


  // STEP: Execute + Memory Read
  // STEP.X: Memory Read
  reg [`REG_LEN-1:0] memd [`MEMD_SIZE-1:0];
  
  reg memd_is_public; // always true

  always @(posedge clk) begin
    if (rst) begin
`ifdef INIT_MEMD_CUSTOMIZED
        memd[0] <= 2;
        memd[1] <= 3;
        memd[2] <= 3;
        memd[3] <= 3;
`else
      for (i=0; i<`MEMD_SIZE; i=i+1)
        memd[i] <= 0;
`endif
    end

    memd_is_public <= 1
  end


  // STEP.X: output from alu
  wire [`MEMD_SIZE_LOG-1:0] mem_addr        [`ROB_SIZE-1:0];
  wire [`REG_LEN-1      :0] ROB_rd_data_wire[`ROB_SIZE-1:0];
  wire [`ROB_SIZE-1     :0] ROB_taken_wire;
  wire [`MEMI_SIZE_LOG-1:0] ROB_next_pc_wire[`ROB_SIZE-1:0];
  generate for (p=0; p <`ROB_SIZE; p=p+1) begin
  execute execute_instance(
    .pc(ROB_pc[p]),
    .op(ROB_op[p]),

    .rs1_imm(ROB_rs1_imm[p]),
    .rs1_br_offset(ROB_rs1_br_offset[p]),
    .rs1_data(ROB_rs1_data[p]),

    .rs2_data(ROB_rs2_data[p]),

    .mem_addr(mem_addr[p]), // output
    .mem_data(memd[mem_addr[p]]),

    .rd_data_use_alu(ROB_rd_data_use_alu[p]),
    .rd_data(ROB_rd_data_wire[p]), // output

    .is_br(ROB_is_br[p]),
    .taken(ROB_taken_wire[p]), // output
    .next_pc(ROB_next_pc_wire[p]) // output
  );
  end endgenerate




  // STEP: Commit
  wire                      C_valid;

  wire                      C_wen;
  wire [`RF_SIZE_LOG-1  :0] C_rd;
  wire [`REG_LEN-1      :0] C_rd_data;

  wire                      C_is_br;
  wire                      C_taken;
  wire                      C_squash;
  wire [`MEMI_SIZE_LOG-1:0] C_next_pc;

  wire [`MEMI_SIZE_LOG-1:0] C_pc;
  wire [`INST_SIZE_LOG-1:0] C_op;
  wire [`MEMD_SIZE_LOG-1:0] C_addr;

  assign C_valid = ROB_state[ROB_head]==`FINISHED;

  assign C_wen     = ROB_wen    [ROB_head];
  assign C_rd      = ROB_rd     [ROB_head];
  assign C_rd_data = ROB_rd_data[ROB_head];

  assign C_is_br   = ROB_is_br  [ROB_head];
  assign C_taken   = ROB_taken  [ROB_head];
  assign C_squash  = C_is_br && (ROB_predicted_taken[ROB_head] != ROB_taken[ROB_head]);
  assign C_next_pc = ROB_next_pc[ROB_head];
  assign C_pc      = C_valid ? ROB_pc[ROB_head] : 0;
  assign C_op      = C_valid ? ROB_op[ROB_head] : 0;
  assign C_addr    = C_valid && ROB_mem_valid[ROB_head] ? mem_addr[ROB_head] : 0;


  always @(posedge clk) begin
    $display(
      "Commit %x%x%x %x, ROB LD %x%x%x%x %x%x%x%x", 
      C_valid, C_pc, C_op, C_addr,
      ROB_mem_addr[0], ROB_mem_addr[1],
      ROB_mem_addr[2], ROB_mem_addr[3],
      ROB_mem_addr[4], ROB_mem_addr[5],
      ROB_mem_addr[6], ROB_mem_addr[7],
    );
  end




  // STEP: for verification
  wire                      veri_commit;
  reg  [`MEMI_SIZE_LOG-1:0] veri_pc_last;
  wire [`REG_LEN-1      :0] veri_rf   [`RF_SIZE-1  :0];
  wire [`INST_LEN-1     :0] veri_memi [`MEMI_SIZE-1:0];
  wire [`REG_LEN-1      :0] veri_memd [`MEMD_SIZE-1:0];

  assign veri_commit = C_valid;
  always @(posedge clk)
    if (veri_commit)
      veri_pc_last <= ROB_pc[ROB_head];
  generate for(p=0; p<`RF_SIZE; p=p+1) begin
    assign veri_rf[p] = rf_instance.array[p];
  end endgenerate
  generate for(p=0; p<`MEMI_SIZE; p=p+1) begin
    assign veri_memi[p] = memi_instance.array[p];
  end endgenerate
  generate for(p=0; p<`MEMD_SIZE; p=p+1) begin
    assign veri_memd[p] = memd[p];
  end endgenerate

endmodule

