module dfan_fault_interlock(
    input wire clk,
    input wire rst_n,
    input wire [1:0] state_N0, state_N1, state_N2, state_N3,
    input wire multi_por_fault,
    input wire sync_px,
    input wire [1:0] global_fsm_state, 
    input wire [3:0] W0, W1, W2, W3,
    input wire [3:0] L0, L1, L2, L3,
    input wire [3:0] H0, H1, H2, H3,
    input wire [3:0] demand_N0, demand_N1, demand_N2, demand_N3,
    input wire [3:0] por_N,

    output reg fault_flag
);

    wire act_0 = (state_N0 == 2'b10); wire act_1 = (state_N1 == 2'b10);
    wire act_2 = (state_N2 == 2'b10); wire act_3 = (state_N3 == 2'b10);
    wire illegal_coexist = (act_0 & act_2) | (act_0 & act_3) | (act_1 & act_2) | (act_1 & act_3);

    reg [1:0] prev_N0, prev_N1, prev_N2, prev_N3;
    wire illegal_trans_N0 = (prev_N0 == 2'b00 && state_N0 == 2'b10);
    wire illegal_trans_N1 = (prev_N1 == 2'b00 && state_N1 == 2'b10);
    wire illegal_trans_N2 = (prev_N2 == 2'b00 && state_N2 == 2'b10);
    wire illegal_trans_N3 = (prev_N3 == 2'b00 && state_N3 == 2'b10);
    wire illegal_trans_fault = illegal_trans_N0 | illegal_trans_N1 | illegal_trans_N2 | illegal_trans_N3;

    wire trans_abort_fault = (global_fsm_state == 2'b01) & sync_px;

    wire overflow_fault = (W0==15) | (W1==15) | (W2==15) | (W3==15) | 
                          (L0==15) | (L1==15) | (L2==15) | (L3==15);

    wire history_fault = (H0 > 7) | (H1 > 7) | (H2 > 7) | (H3 > 7);

    wire invalid_sched_N0 = act_0 & (demand_N0 == 0) & ~por_N[0];
    wire invalid_sched_N1 = act_1 & (demand_N1 == 0) & ~por_N[1];
    wire invalid_sched_N2 = act_2 & (demand_N2 == 0) & ~por_N[2];
    wire invalid_sched_N3 = act_3 & (demand_N3 == 0) & ~por_N[3];
    wire invalid_sched_fault = invalid_sched_N0 | invalid_sched_N1 | invalid_sched_N2 | invalid_sched_N3;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fault_flag <= 1'b0;
            prev_N0 <= 2'b00; prev_N1 <= 2'b00; 
            prev_N2 <= 2'b00; prev_N3 <= 2'b00;
        end else begin
            prev_N0 <= state_N0; prev_N1 <= state_N1;
            prev_N2 <= state_N2; prev_N3 <= state_N3;

            if (illegal_coexist | illegal_trans_fault | trans_abort_fault | 
                overflow_fault | history_fault | invalid_sched_fault | multi_por_fault) begin
                fault_flag <= 1'b1;
            end
        end
    end
endmodule
