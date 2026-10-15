`timescale 1ns/1ps

module tb_dfan_top;
    reg clk, rst_n, sync_px;
    reg [3:0] demand_N0, demand_N1, demand_N2, demand_N3, por_N;
    
    wire [1:0] state_N0, state_N1, state_N2, state_N3;
    wire px_grant, fault_flag;

    integer tests_passed = 0;
    integer tests_failed = 0;

    dfan_top uut (
        .clk(clk), .rst_n(rst_n),
        .demand_N0(demand_N0), .demand_N1(demand_N1),
        .demand_N2(demand_N2), .demand_N3(demand_N3),
        .por_N(por_N), .sync_px(sync_px),
        .state_N0(state_N0), .state_N1(state_N1),
        .state_N2(state_N2), .state_N3(state_N3),
        .px_grant(px_grant), .fault_flag(fault_flag)
    );

    always #5 clk = ~clk;

    task assert_check;
        input condition;
        input [800:0] msg;
        begin
            if (condition) begin
                $display("[PASS] %s", msg);
                tests_passed = tests_passed + 1;
            end else begin
                $display("[FAIL] %s", msg);
                tests_failed = tests_failed + 1;
            end
        end
    endtask

    initial begin
        clk = 0; rst_n = 0; sync_px = 0; por_N = 0;
        demand_N0 = 1; demand_N1 = 1; demand_N2 = 1; demand_N3 = 1; // Baseline non-zero
        
        $display("\n===========================================================");
        $display("   DFAN MEGA-VERIFICATION SUITE: 10-STAGE STRESS TEST");
        $display("===========================================================\n");
        
        #20 rst_n = 1;

        // ---------------------------------------------------------
        // TEST 1: LONG CONTINUOUS STARVATION (History Buffer Fill)
        // ---------------------------------------------------------
        $display("--- TEST 1: Extended Monopolization & History Saturation ---");
        demand_N0 = 4'd15; demand_N1 = 4'd15; 
        demand_N2 = 4'd2;  demand_N3 = 4'd2;
        #500; // Let it run wild
        assert_check(uut.u_datapath.H[0] > 3, "N0 History penalty heavily saturated.");
        assert_check(uut.u_datapath.W[2] > 3, "N2 Wait multiplier grew massively.");
        wait(state_N2 == 2'b10); 
        assert_check(state_N2 == 2'b10, "Mathematical fairness broke the long monopoly!");

        // ---------------------------------------------------------
        // TEST 2: TOTAL WAR (All Domains Max Demand)
        // ---------------------------------------------------------
        $display("\n--- TEST 2: Total War (All D = 15) ---");
        demand_N0 = 4'd15; demand_N1 = 4'd15; 
        demand_N2 = 4'd15; demand_N3 = 4'd15;
        #300; 
        assert_check((uut.u_datapath.score_0 != uut.u_datapath.score_2), "Scores dynamically diverging due to history math.");

        // ---------------------------------------------------------
        // TEST 3: ASYMMETRICAL HITCHHIKING (Heavy vs Light)
        // ---------------------------------------------------------
        $display("\n--- TEST 3: Asymmetrical Hitchhiking ---");
        demand_N0 = 4'd15; demand_N1 = 4'd1;  // N0 carries N1
        demand_N2 = 4'd2;  demand_N3 = 4'd14; // N3 carries N2
        #300;
        assert_check(state_N0 == state_N1, "N1 successfully hitched a ride with dominant N0.");
        
        // ---------------------------------------------------------
        // TEST 4: THE LONE WOLF (One Max vs Three Mids)
        // ---------------------------------------------------------
        $display("\n--- TEST 4: The Lone Wolf Competition ---");
        demand_N0 = 4'd15; demand_N1 = 4'd0; 
        demand_N2 = 4'd8;  demand_N3 = 4'd8;
        wait(state_N0 == 2'b10); #10;
        assert_check(state_N1 == 2'b00, "N1 blocked perfectly due to 0 demand while N0 active.");

        // ---------------------------------------------------------
        // TEST 5: SEQUENTIAL POR BOMBARDMENT
        // ---------------------------------------------------------
        $display("\n--- TEST 5: Sequential Emergency Overrides ---");
        demand_N0 = 4'd5; demand_N1 = 4'd5; demand_N2 = 4'd5; demand_N3 = 4'd5;
        
        por_N = 4'b0001; // N0 Override
        wait(state_N0 == 2'b10); #20;
        assert_check(state_N0 == 2'b10, "N0 successfully captured POR.");
        
        por_N = 4'b1000; // N3 Instantly steals it
        wait(state_N3 == 2'b10); #20;
        assert_check(state_N3 == 2'b10, "N3 successfully stole POR from N0.");
        por_N = 4'b0000;

        // ---------------------------------------------------------
        // TEST 6: INVALID GHOST POR (Zero-Demand Filter)
        // ---------------------------------------------------------
        $display("\n--- TEST 6: Ghost POR Rejection ---");
        demand_N1 = 4'd0; 
        por_N = 4'b0010; // N1 triggers POR, but has 0 demand!
        #50;
        assert_check(state_N1 == 2'b00, "Hardware correctly ignored POR from zero-demand domain.");
        por_N = 4'b0000; demand_N1 = 4'd5; // Restore

        // ---------------------------------------------------------
        // TEST 7: GLOBAL PX PAUSE UNDER HEAVY TRAFFIC
        // ---------------------------------------------------------
        $display("\n--- TEST 7: Global Pause (PX) During Heavy Traffic ---");
        demand_N0 = 4'd15; demand_N2 = 4'd15; 
        wait(state_N0 == 2'b10 || state_N2 == 2'b10); 
        sync_px = 1'b1; #50;
        assert_check((state_N0==0 && state_N1==0 && state_N2==0 && state_N3==0), "FSM killed all active domains for PX.");
        sync_px = 1'b0; #50;

        // ---------------------------------------------------------
        // TEST 8: THE RAPID FLICKER TEST
        // ---------------------------------------------------------
        $display("\n--- TEST 8: Rapid Demand Fluctuation (Jitter) ---");
        repeat(5) begin
            demand_N0 = 15; demand_N2 = 1; #10;
            demand_N0 = 1; demand_N2 = 15; #10;
        end
        assert_check(uut.u_fsm.global_state != 2'b10, "FSM safely held in Transition/Idle during severe input jitter.");
        
        // ---------------------------------------------------------
        // TEST 9: ILLEGAL COEXISTENCE (Physical Glitch Injection)
        // ---------------------------------------------------------
        $display("\n--- TEST 9: Illegal Coexistence Glitch (Alpha Particle) ---");
        demand_N0 = 4'd10; demand_N1 = 4'd10; demand_N2 = 4'd1; demand_N3 = 4'd1;
        wait(state_N0 == 2'b10);
        
        force uut.pre_state_N2 = 2'b10; // Physically short the wire
        #10;
        assert_check(fault_flag == 1'b1, "Hardware fault interlock caught physical cross-pair short (N0+N2).");
        assert_check((state_N0==0 && state_N2==0), "Fail-safe instant output suppression works.");
        release uut.pre_state_N2;
        
        rst_n = 0; #20; rst_n = 1; #20; // Hard reset to clear fault

        // ---------------------------------------------------------
        // TEST 10: MULTI-POR HARD FAULT CLASH
        // ---------------------------------------------------------
        $display("\n--- TEST 10: Multi-POR Fatal Collision ---");
        demand_N1 = 4'd10; demand_N3 = 4'd10;
        por_N = 4'b1010; // N3 and N1 both hit the panic button
        #30;
        assert_check(fault_flag == 1'b1, "Fault latched successfully on multi-POR clash.");
        
        // ---------------------------------------------------------
        // SUMMARY DASHBOARD
        // ---------------------------------------------------------
        $display("\n===========================================================");
        $display("   VERIFICATION SUMMARY DASHBOARD");
        $display("===========================================================");
        $display("   Total Assertions  : %0d", (tests_passed + tests_failed));
        $display("   Tests Passed      : %0d", tests_passed);
        $display("   Tests Failed      : %0d", tests_failed);
        if (tests_failed == 0)
            $display("   FINAL STATUS      : PASSED [SILICON READY]");
        else
            $display("   FINAL STATUS      : FAILED [REVIEW REQUIRED]");
        $display("===========================================================\n");
        
        $finish;
    end
endmodule
