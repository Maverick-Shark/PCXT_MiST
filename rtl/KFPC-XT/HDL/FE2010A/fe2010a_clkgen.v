//
// FE2010A Clock Generator / Selector
//
// Translates the FE2010A Configuration Register clock bits into the
// clk_select format used by the MiST top-level (PCXT.sv).
//
// The FE2010A supports three clock speeds using two crystal oscillator
// options:
//
//   14.31818 MHz crystal (XSEL pin high):
//     - 4.77 MHz (÷3) — standard PC/XT speed
//     - 7.15 MHz (÷2) — turbo mode
//
//   28.63636 MHz crystal (XSEL pin low):
//     - 4.77 MHz (÷6)
//     - 7.15 MHz (÷4)
//     - 9.54 MHz (÷3) — max turbo mode
//
// In the MiST implementation, all three clocks are always available
// from the PLL infrastructure. This module simply selects which one
// to use based on the configuration register.
//
// Configuration Register bits [7:6] -> Clock speed:
//   2'b00 = 4.77 MHz
//   2'b01 = 7.15 MHz
//   2'b10 = 9.54 MHz
//   2'b11 = 9.54 MHz (both bit 7 and 6 set still means 9.54)
//
// Additional output: CPU clock duty cycle information
//   At 4.77 MHz and 7.15 MHz: standard 33% duty (high 1/3, low 2/3)
//   At 9.54 MHz: FE2010A uses 50% duty cycle
//
// Note on MiST integration:
//   The actual clock muxing happens in PCXT.sv, not here.
//   This module provides the clk_select[1:0] output that PCXT.sv
//   uses to select among clk_4_77, clk_7_16, clk_9_54.
//
// References:
//   - FE2010A documentation: "Faraday FE2010A uses XSEL signal - pin 16
//     to indicate the crystal frequency"
//   - FE2010A timing note: "when running at 9.54 MHz, the CPU clock
//     duty cycle is 50% (instead of 33%)"
//

module fe2010a_clkgen (
    input  wire        clock,           // System clock
    input  wire        reset,           // System reset

    // Configuration Register inputs (bits 7:5)
    input  wire [2:0]  config_clk_bits, // {bit7_9_54, bit6_7_15, bit5_fast_mode}

    // Clock select output (directly drives PCXT.sv clock mux)
    //   2'b00 = 4.77 MHz
    //   2'b01 = 7.15 MHz
    //   2'b10 = 9.54 MHz
    output reg  [1:0]  clk_select,

    // CPU clock duty cycle: 0 = 33% (standard), 1 = 50% (9.54 MHz mode)
    output wire        duty_cycle_50,

    // Fast mode: zero on-board memory wait states (config bit 5)
    output wire        fast_mode,

    // Current clock period in system clock ticks (approximate, for wait
    // state counting). At 50 MHz system clock:
    //   4.77 MHz -> ~10.5 sys clks per CPU clk (use 10)
    //   7.15 MHz -> ~7.0 sys clks per CPU clk (use 7)
    //   9.54 MHz -> ~5.2 sys clks per CPU clk (use 5)
    output reg  [3:0]  cpu_clk_period
);

    // ========================================================================
    // Clock speed decode from Configuration Register bits [7:6]
    // ========================================================================
    //
    // The FE2010A configuration register uses a priority encoding:
    //   Bit 7 set (regardless of bit 6) -> 9.54 MHz
    //   Bit 6 set (bit 7 clear) -> 7.15 MHz
    //   Both clear -> 4.77 MHz
    //
    // From the FE2010A documentation table:
    //   bit7=0, bit6=0 -> 4.77 MHz
    //   bit7=0, bit6=1 -> 7.15 MHz
    //   bit7=1, bit6=0 -> 9.54 MHz
    //   bit7=1, bit6=1 -> 9.54 MHz
    //

    wire cfg_9_54 = config_clk_bits[2];           // bit 7
    wire cfg_7_15 = config_clk_bits[1] & ~cfg_9_54; // bit 6, only if bit 7 is 0

    always @(posedge clock or posedge reset) begin
        if (reset) begin
            clk_select     <= 2'b00;  // Default: 4.77 MHz
            cpu_clk_period <= 4'd10;
        end else begin
            if (cfg_9_54) begin
                clk_select     <= 2'b10;  // 9.54 MHz
                cpu_clk_period <= 4'd5;
            end else if (cfg_7_15) begin
                clk_select     <= 2'b01;  // 7.15 MHz
                cpu_clk_period <= 4'd7;
            end else begin
                clk_select     <= 2'b00;  // 4.77 MHz
                cpu_clk_period <= 4'd10;
            end
        end
    end

    // ========================================================================
    // Duty cycle and fast mode outputs
    // ========================================================================

    // 50% duty cycle only at 9.54 MHz
    assign duty_cycle_50 = cfg_9_54;

    // Fast mode from configuration register bit 5
    assign fast_mode = config_clk_bits[0];

endmodule
