module dfan_top (
    input wire clk,
    input wire rst_n,
    input wire [3:0] demand_N3,
    input wire [3:0] demand_N2,
    input wire [3:0] demand_N1,
    input wire [3:0] demand_N0,
    input wire [3:0] por_N,
    input wire sync_px,

    output wire [1:0] state_N0,
    output wire [1:0] state_N1,
    output wire [1:0] state_N2,
    output wire [1:0] state_N3,
    output wire px_grant,
    output wire fault_flag
);

    wire [15:0] flat_demand = {demand_N3, demand_N2, demand_N1, demand_N0};
    wire [3:0]  current_active_mask;
    wire        entering_active;
    wire [3:0]  next_candidate_mask;
    wire signed [7:0] s0, s1, s2, s3;
    
    wire [1:0] pre_state_N0, pre_state_N1, pre_state_N2, pre_state_N3;
    wire pre_px_grant;
    wire multi_por_fault;

    wire [1:0] fsm_global_state;
    wire [3:0] w0, w1, w2, w3;
    wire [3:0] l0, l1, l2, l3;
    wire [3:0] h0, h1, h2, h3;

    // --- MASTER FAIL-SAFE MUX ---
    assign state_N0 = fault_flag ? 2'b00 : pre_state_N0;
    assign state_N1 = fault_flag ? 2'b00 : pre_state_N1;
    assign state_N2 = fault_flag ? 2'b00 : pre_state_N2;
    assign state_N3 = fault_flag ? 2'b00 : pre_state_N3;
    assign px_grant = fault_flag ? 1'b0  : pre_px_grant;

    dfan_datapath u_datapath (
        .clk(clk), .rst_n(rst_n), .demand_N_flat(flat_demand),
        .entering_active(entering_active),
        .current_active_mask(current_active_mask),
        .score_0(s0), .score_1(s1), .score_2(s2), .score_3(s3),
        .W0_out(w0), .W1_out(w1), .W2_out(w2), .W3_out(w3),
        .L0_out(l0), .L1_out(l1), .L2_out(l2), .L3_out(l3),
        .H0_out(h0), .H1_out(h1), .H2_out(h2), .H3_out(h3)
    );

    dfan_arbitration u_arbitration (
        .clk(clk), .rst_n(rst_n),
        .demand_N_flat(flat_demand), .por_N(por_N),
        .score_0(s0), .score_1(s1), .score_2(s2), .score_3(s3),
        .current_active_mask(current_active_mask),
        .next_candidate_mask(next_candidate_mask),
        .multi_por_fault(multi_por_fault)
    );

    dfan_fsm #( .TRANS_DELAY_VAL(4'd2) ) u_fsm (
        .clk(clk), .rst_n(rst_n), .sync_px(sync_px),
        .next_candidate_mask(next_candidate_mask),
        .current_active_mask(current_active_mask), 
        .entering_active(entering_active),
        .fsm_state_N0(pre_state_N0), .fsm_state_N1(pre_state_N1),
        .fsm_state_N2(pre_state_N2), .fsm_state_N3(pre_state_N3),
        .fsm_px_grant(pre_px_grant),
        .global_state_out(fsm_global_state)
    );

    dfan_fault_interlock u_fault (
        .clk(clk), .rst_n(rst_n),
        .state_N0(pre_state_N0), .state_N1(pre_state_N1),
        .state_N2(pre_state_N2), .state_N3(pre_state_N3),
        .multi_por_fault(multi_por_fault),
        .sync_px(sync_px),
        .global_fsm_state(fsm_global_state),
        .W0(w0), .W1(w1), .W2(w2), .W3(w3),
        .L0(l0), .L1(l1), .L2(l2), .L3(l3),
        .H0(h0), .H1(h1), .H2(h2), .H3(h3),
        .demand_N0(demand_N0), .demand_N1(demand_N1),
        .demand_N2(demand_N2), .demand_N3(demand_N3),
        .por_N(por_N),
        .fault_flag(fault_flag)
    );

endmodule
