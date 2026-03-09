// HGC pixel decimator for MiST VGA output
//
// The HGC runs at ~57 MHz with 1800 pixel clocks per line (100 chars × 18 clocks).
// Each pixel repeats for 2 clocks (9-pixel chars over 18 clocks), giving 900
// unique pixels per line.
//
// This module captures every other pixel into a line buffer and reads it back
// at half rate, producing 900 output pixels per line with VGA-compatible HSYNC
// timing. The effective pixel rate is ~28.6 MHz, matching the CGA scandoubler
// output.
//
// Based on the cga_scandoubler architecture: two line buffers that alternate
// on line_reset, write at half rate, read at half rate.
//
`default_nettype wire
module hgc_scandoubler(
    input clk,               // ~57 MHz (HGC pixel clock)
    input line_reset,        // from CRTC, marks start of new line
    input [1:0] video,       // {intensity, video_bit}
    output reg dbl_hsync,    // decimated HSYNC
    output [1:0] dbl_video,  // decimated video
    output reg dbl_hblank    // decimated HBLANK
    );

    reg sclk = 1'b0;           // Write half-rate toggle
    reg rclk = 1'b0;           // Read half-rate toggle
    reg [9:0] hcount_slow;     // Write address (0-899)
    reg [9:0] hcount_fast;     // Read address (0-899)
    reg line_reset_old = 1'b0;

    wire [9:0] addr_a;
    wire [9:0] addr_b;

    reg [1:0] data_a;
    reg [1:0] data_b;

    reg [1:0] scan_ram_a [1023:0];
    reg [1:0] scan_ram_b [1023:0];

    reg select = 1'b0;

    // Standard 720x350 VGA mode timing (in decimated pixel units):
    //   H_ACTIVE = 720 (80 chars × 9 pixels)
    //   H_TOTAL  = 900 (100 chars × 9 pixels)
    //   H_FP     = 18  (pixels 720-737)
    //   H_SYNC   = 108 (pixels 738-845)
    //   H_BP     = 54  (pixels 846-899)

    always @ (posedge clk)
    begin
        line_reset_old <= line_reset;
    end

    // Write counter: captures every other pixel (900 per line)
    always @ (posedge clk)
    begin
        sclk <= ~sclk;
        if (line_reset & ~line_reset_old) begin
            hcount_slow <= 10'd0;
            sclk <= 1'b0;
        end else if (sclk) begin
            hcount_slow <= hcount_slow + 10'd1;
        end
    end

    // Read counter: outputs every other clock (900 per line, same line rate)
    always @ (posedge clk)
    begin
        rclk <= ~rclk;
        if (line_reset & ~line_reset_old) begin
            hcount_fast <= 10'd0;
            rclk <= 1'b0;
        end else if (rclk) begin
            hcount_fast <= hcount_fast + 10'd1;
        end

        // Generate HSYNC: standard VGA timing for 720-pixel active
        if (hcount_fast == 10'd738) begin
            dbl_hsync <= 1;
        end
        if (hcount_fast == 10'd846) begin
            dbl_hsync <= 0;
        end

        // Generate HBLANK: active area is pixels 0-719
        if (line_reset & ~line_reset_old) begin
            dbl_hblank <= 0;
        end else if (rclk && hcount_fast == 10'd720) begin
            dbl_hblank <= 1;
        end
    end

    // Select latch lets us swap between line store RAMs A and B
    always @ (posedge clk)
    begin
        if (line_reset & ~line_reset_old) begin
            select = ~select;
        end
    end

    assign addr_a = select ? hcount_slow : hcount_fast;
    assign addr_b = select ? hcount_fast : hcount_slow;

    // RAM A
    always @ (posedge clk)
    begin
        if (select & sclk) begin
            scan_ram_a[(addr_a)] <= video;
        end
        data_a <= scan_ram_a[addr_a];
    end

    // RAM B
    always @ (posedge clk)
    begin
        if (!select & sclk) begin
            scan_ram_b[(addr_b)] <= video;
        end
        data_b <= scan_ram_b[addr_b];
    end

    assign dbl_video = select ? data_b : data_a;

endmodule
