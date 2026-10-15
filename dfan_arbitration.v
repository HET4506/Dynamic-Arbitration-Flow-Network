module dfan_arbitration(
    input wire clk,
    input wire rst_n,
    input wire [15:0] demand_N_flat, 
    input wire [3:0] por_N,
    input wire signed [7:0] score_0,
    input wire signed [7:0] score_1,
    input wire signed [7:0] score_2,
    input wire signed [7:0] score_3,
    input wire [3:0] current_active_mask,
    
    output reg [3:0] next_candidate_mask,
    output reg multi_por_fault
);

    wire [3:0] demand_0 = demand_N_flat[3:0];
    wire [3:0] demand_1 = demand_N_flat[7:4];
    wire [3:0] demand_2 = demand_N_flat[11:8];
    wire [3:0] demand_3 = demand_N_flat[15:12];

    wire valid_por_0 = por_N[0] & (demand_0 > 0);
    wire valid_por_1 = por_N[1] & (demand_1 > 0);
    wire valid_por_2 = por_N[2] & (demand_2 > 0);
    wire valid_por_3 = por_N[3] & (demand_3 > 0);

    wire [2:0] por_count = valid_por_0 + valid_por_1 + valid_por_2 + valid_por_3;

    always @(*) begin
        next_candidate_mask = 4'b0000;
        multi_por_fault = (por_count > 1); 
        
        if (!multi_por_fault) begin
            if (por_count == 1) begin
                if (valid_por_0) next_candidate_mask = 4'b0001;
                else if (valid_por_1) next_candidate_mask = 4'b0010;
                else if (valid_por_2) next_candidate_mask = 4'b0100;
                else if (valid_por_3) next_candidate_mask = 4'b1000;
            end else begin
                // Pair 0 vs Pair 1 Scoring
                reg signed [8:0] pair0_score, pair1_score;
                pair0_score = ((demand_0 > 0) ? score_0 : 0) + ((demand_1 > 0) ? score_1 : 0);
                pair1_score = ((demand_2 > 0) ? score_2 : 0) + ((demand_3 > 0) ? score_3 : 0);
                
                if (pair0_score > pair1_score) begin
                    next_candidate_mask[0] = (demand_0 > 0);
                    next_candidate_mask[1] = (demand_1 > 0);
                end else if (pair1_score > pair0_score) begin
                    next_candidate_mask[2] = (demand_2 > 0);
                    next_candidate_mask[3] = (demand_3 > 0);
                end else begin
                    next_candidate_mask = current_active_mask; 
                end
            end
        end
    end
endmodule
