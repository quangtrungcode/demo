`timescale 1ns/1ps

module tb_top;
    // Khai báo tín hiệu
    reg CLK;
    reg RST_N;
    reg VALID;
    reg [7:0] DATA_IN;
    reg [1:0] PARITY_MODE;
    wire TXD;

    // Biến đếm lỗi và vòng lặp
    integer err_count;
    integer loop_idx;

    // Khởi tạo Clock (50MHz)
    initial begin
        CLK = 0;
        forever #10 CLK = ~CLK;
    end

    // Khởi tạo DUT
    DUT u_dut (
        .CLK(CLK),
        .RST_N(RST_N),
        .VALID(VALID),
        .DATA_IN(DATA_IN),
        .PARITY_MODE(PARITY_MODE),
        .TXD(TXD)
    );

    // Reference model cho hàm tính Parity
    function reg calc_expected_parity;
        input [7:0] data;
        input [1:0] mode;
        begin
            if (mode == 2'b01) calc_expected_parity = ~(^data);      // Odd parity
            else if (mode == 2'b10) calc_expected_parity = ^data;    // Even parity
            else calc_expected_parity = 1'b0;
        end
    endfunction

    // ---------------------------------------------------------
    // [VPLAN ID 1] Task kiểm tra Reset
    // ---------------------------------------------------------
    task test_id1_reset;
        begin
            $display("[%0t] RUNNING VPLAN ID 1: Reset Test", $time);
            RST_N = 0;
            VALID = 1;
            DATA_IN = {$random} % 256;
            PARITY_MODE = {$random} % 4;
            
            repeat(5) begin
                @(posedge CLK);
                if (TXD !== 1'b0) begin
                    $display("  -> [BUG ID 1] TXD is not 0 when RST_N is active!");
                    err_count = err_count + 1;
                end
            end
        end
    endtask

    // ---------------------------------------------------------
    // [VPLAN ID 2] Task kiểm tra Valid
    // ---------------------------------------------------------
    task test_id2_valid;
        begin
            $display("[%0t] RUNNING VPLAN ID 2: Valid Test", $time);
            RST_N = 1;
            VALID = 0;
            DATA_IN = {$random} % 256;
            PARITY_MODE = {$random} % 4;
            
            repeat(5) begin
                @(posedge CLK);
                if (TXD !== 1'b0) begin
                    $display("  -> [BUG ID 2] TXD is not 0 when VALID is 0!");
                    err_count = err_count + 1;
                end
            end
        end
    endtask

    // ---------------------------------------------------------
    // [VPLAN ID 3, 4, 5] Task kiểm tra Data, Parity và mức Idle của TXD
    // ---------------------------------------------------------
    task test_id345_transfer;
        input [7:0] t_data;
        input [1:0] t_mode;
        
        // Khai báo biến cục bộ bên trong task
        reg [7:0] captured_data;
        reg expected_parity;
        reg captured_parity;
        integer k;
        
        begin
            $display("[%0t] RUNNING VPLAN ID 3,4,5: Transfer (Data: %h, Mode: %b)", $time, t_data, t_mode);
            
            @(posedge CLK);
            VALID = 1;
            DATA_IN = t_data;
            PARITY_MODE = t_mode;
            
            @(posedge CLK);
            VALID = 0; 

            // [VPLAN ID 3] Kiểm tra Data (8-bit, LSB truyền trước)
            for (k = 0; k < 8; k = k + 1) begin
                captured_data[k] = TXD;
                @(posedge CLK);
            end

            if (captured_data !== t_data) begin
                $display("  -> [BUG ID 3] Data Mismatch. Expected: %h, Captured: %h", t_data, captured_data);
                err_count = err_count + 1;
            end

            // [VPLAN ID 4] Kiểm tra Parity
            if (t_mode == 2'b01 || t_mode == 2'b10) begin
                captured_parity = TXD;
                expected_parity = calc_expected_parity(t_data, t_mode);
                
                if (captured_parity !== expected_parity) begin
                    $display("  -> [BUG ID 4] Parity Mismatch. Mode: %b, Expected: %b, Captured: %b", t_mode, expected_parity, captured_parity);
                    err_count = err_count + 1;
                end
                @(posedge CLK); 
            end

            // [VPLAN ID 5] Kiểm tra mức Idle
            repeat(3) begin
                if (TXD !== 1'b0) begin
                    $display("  -> [BUG ID 5] TXD is asserted after transfer completion!");
                    err_count = err_count + 1;
                end
                @(posedge CLK);
            end
        end
    endtask

    // ---------------------------------------------------------
    // Khối thực thi chính 
    // ---------------------------------------------------------
    initial begin
        err_count = 0;
        CLK = 0;
        RST_N = 1;
        VALID = 0;
        DATA_IN = 8'h00;
        PARITY_MODE = 2'b00;
        
        #20;

        test_id1_reset();
        test_id2_valid();

        // Corner Cases
        test_id345_transfer(8'hA3, 2'b00); 
        test_id345_transfer(8'hFF, 2'b11); 
        test_id345_transfer(8'b1101_0010, 2'b01); 
        test_id345_transfer(8'h00, 2'b01); 
        test_id345_transfer(8'b1101_0010, 2'b10);
        test_id345_transfer(8'hFF, 2'b10);

        // Randomized Tests
        $display("[%0t] --- RUNNING RANDOMIZED TESTS ---", $time);
        for (loop_idx = 0; loop_idx < 10; loop_idx = loop_idx + 1) begin
            // Hàm sinh số ngẫu nhiên chuẩn Verilog ($random)
            test_id345_transfer({$random} % 256, {$random} % 4);
        end

        // Báo cáo
        $display("==================================================");
        if (err_count == 0)
            $display("SIMULATION PASSED. No bugs found.");
        else
            $display("SIMULATION FAILED. Total Bugs Found: %0d", err_count);
        $display("==================================================");
        
        $finish;
    end

    initial begin
        $dumpfile("dump.vcd");
        $dumpvars(0, tb_top);
    end
endmodule
