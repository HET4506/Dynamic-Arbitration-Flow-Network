module dfan_datapath(
    input wire clk,
    input wire rst_n,
    input wire [15:0] demand_N_flat,
    input wire entering_active,
    input wire [3:0] current_active_mask,
    
    output wire signed [7:0] score_0,
    output wire signed [7:0] score_1,
    output wire signed [7:0] score_2,
    output wire signed [7:0] score_3,
    
    output wire [3:0] W0_out, W1_out, W2_out, W3_out,
    output wire [3:0] L0_out, L1_out, L2_out, L3_out,
    output wire [3:0] H0_out, H1_out, H2_out, H3_out
);

    wire [3:0] demand_0 = demand_N_flat[3:0];
    wire [3:0] demand_1 = demand_N_flat[7:4];
    wire [3:0] demand_2 = demand_N_flat[11:8];
    wire [3:0] demand_3 = demand_N_flat[15:12];

    reg [3:0] W [0:3]; 
    reg [3:0] L [0:3]; 
    reg [3:0] H [0:3]; 

    integer i;

    // The Power-Efficient Formula: (D + W) - (L + H)
    assign score_0 = ({4'b0, demand_0} + W[0]) - (L[0] + H[0]);
    assign score_1 = ({4'b0, demand_1} + W[1]) - (L[1] + H[1]);
    assign score_2 = ({4'b0, demand_2} + W[2]) - (L[2] + H[2]);
    assign score_3 = ({4'b0, demand_3} + W[3]) - (L[3] + H[3]);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i=0; i<4; i=i+1) begin
                W[i] <= 4'd0;
                L[i] <= 4'd0;
                H[i] <= 4'd0;
            end
        end else begin
            for (i=0; i<4; i=i+1) begin
                // Wait Counter Logic
                if (current_active_mask[i] == 0 && (i==0?demand_0 : i==1?demand_1 : i==2?demand_2 : demand_3) > 0) begin
                    if (W[i] < 4'd15) W[i] <= W[i] + 1'b1;
                end else begin
                    W[i] <= 4'd0;
                end

                // Duration Counter Logic
                if (current_active_mask[i]) begin
                    if (L[i] < 4'd15) L[i] <= L[i] + 1'b1;
                end else begin
                    L[i] <= 4'd0;
                end

                // History Penalty Logic
                if (entering_active && current_active_mask[i]) begin
                    if (H[i] < 4'd7) H[i] <= H[i] + 1'b1;
                end else if (H[i] > 0 && current_active_mask[i] == 0) begin
                    H[i] <= H[i] - 1'b1;
                end
            end
        end
    end

    // Export Arrays for the Watchdog
    assign W0_out = W[0]; assign W1_out = W[1]; assign W2_out = W[2]; assign W3_out = W[3];
    assign L0_out = L[0]; assign L1_out = L[1]; assign L2_out = L[2]; assign L3_out = L[3];
    assign H0_out = H[0]; assign H1_out = H[1]; assign H2_out = H[2]; assign H3_out = H[3];

endmodule
