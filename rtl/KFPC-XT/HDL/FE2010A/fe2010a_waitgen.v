//
// FE2010A Wait State Generator
//
// Generates additional wait states for I/O and memory bus operations
// based on the CPU clock speed and Configuration Register settings.
//
// The FE2010A inserts different numbers of wait states depending on
// the current clock speed (config reg bits 7:6) and fast mode (bit 5):
//
// +---------+---------+---------+-----------+--------+-------------+
// | Bit 7   | Bit 6   | Bit 5   | CPU Speed | I/O WS | Mem Bus WS  |
// +---------+---------+---------+-----------+--------+-------------+
// | 0       | 0       | X       | 4.77 MHz  | 1      | 0           |
// | 0       | 1       | 0       | 7.15 MHz  | 4      | 2           |
// | 0       | 1       | 1       | 7.15 MHz  | 4      | 0           |
// | 1       | 0       | 0       | 9.54 MHz  | 6      | 4           |
// | 1       | 1       | 0       | 9.54 MHz  | 4      | 2           |
// | 1       | 0       | 1       | 9.54 MHz  | 6      | 0           |
// | 1       | 1       | 1       | 9.54 MHz  | 4      | 0           |
// +---------+---------+---------+-----------+--------+-------------+
//
// "On-Board Memory Wait States" are always 0 — the SDRAM controller
// handles its own timing independently.
//
// The base Ready.sv logic already provides 1 wait state on I/O
// operations at 4.77 MHz. This module generates ADDITIONAL wait states
// on top of that base by holding its 'ready' output low for the
// required number of extra CPU clock cycles.
//
// Integration:
//   The output `fe2010a_ready` is ANDed with io_channel_ready and
//   memory_access_ready before being fed into the Ready logic.
//   When fe2010a_ready is low, the CPU will see additional wait states.
//
// Note on IORDY:
//   The external io_channel_ready (IORDY) signal from ISA bus devices
//   can insert further wait states on top of what this module generates.
//   The PT8010AF clone samples IORDY later than the FE2010A, which
//   gives VGA cards more time to assert it.
//

module fe2010a_waitgen (
    input  wire        clock,           // System clock (~50 MHz)
    input  wire        cpu_clock,       // CPU clock
    input  wire        reset,           // System reset

    // Configuration Register inputs
    input  wire [2:0]  config_clk_bits, // {bit7, bit6, bit5}

    // Bus operation signals
    input  wire        io_read_n,       // I/O read (active-low)
    input  wire        io_write_n,      // I/O write (active-low)
    input  wire        memory_read_n,   // Memory read (active-low)
    input  wire        memory_write_n,  // Memory write (active-low)
    input  wire        address_enable_n,// Address enable (low=CPU drives bus)
    input  wire [19:0] address,         // Current bus address

    // RAM address select (from RAM module — indicates on-board memory)
    // When asserted, memory access is to on-board RAM (0 WS always)
    input  wire        onboard_ram_access,

    // Wait state control output
    output wire        fe2010a_ready    // 1=ready (no extra wait), 0=inserting wait states
);

    // ========================================================================
    // CPU clock edge detection
    // ========================================================================
    reg prev_cpu_clock;

    always @(posedge clock or posedge reset) begin
        if (reset)
            prev_cpu_clock <= 1'b0;
        else
            prev_cpu_clock <= cpu_clock;
    end

    wire cpu_clock_posedge = ~prev_cpu_clock &  cpu_clock;
    wire cpu_clock_negedge =  prev_cpu_clock & ~cpu_clock;

    // ========================================================================
    // Decode wait state counts from Configuration Register
    // ========================================================================
    //
    // We compute the ADDITIONAL wait states beyond what Ready.sv provides.
    // Ready.sv already provides 1 base wait state on I/O operations.
    //
    // Additional I/O wait states = (total I/O WS from table) - 1
    // Memory bus wait states = as per table (Ready.sv doesn't add base WS for memory)
    //

    wire cfg_bit7 = config_clk_bits[2];  // 9.54 MHz select
    wire cfg_bit6 = config_clk_bits[1];  // 7.15 MHz select
    wire cfg_bit5 = config_clk_bits[0];  // Fast mode (0 memory WS)

    reg [2:0] extra_io_wait_states;
    reg [2:0] mem_bus_wait_states;

    always @(*) begin
        casez ({cfg_bit7, cfg_bit6, cfg_bit5})
            3'b00?: begin
                // 4.77 MHz: 1 I/O WS total (0 extra), 0 Mem Bus WS
                extra_io_wait_states = 3'd0;
                mem_bus_wait_states  = 3'd0;
            end
            3'b010: begin
                // 7.15 MHz, fast=0: 4 I/O WS (3 extra), 2 Mem Bus WS
                extra_io_wait_states = 3'd3;
                mem_bus_wait_states  = 3'd2;
            end
            3'b011: begin
                // 7.15 MHz, fast=1: 4 I/O WS (3 extra), 0 Mem Bus WS
                extra_io_wait_states = 3'd3;
                mem_bus_wait_states  = 3'd0;
            end
            3'b100: begin
                // 9.54 MHz (bit6=0), fast=0: 6 I/O WS (5 extra), 4 Mem Bus WS
                extra_io_wait_states = 3'd5;
                mem_bus_wait_states  = 3'd4;
            end
            3'b110: begin
                // 9.54 MHz (bit6=1), fast=0: 4 I/O WS (3 extra), 2 Mem Bus WS
                extra_io_wait_states = 3'd3;
                mem_bus_wait_states  = 3'd2;
            end
            3'b101: begin
                // 9.54 MHz (bit6=0), fast=1: 6 I/O WS (5 extra), 0 Mem Bus WS
                extra_io_wait_states = 3'd5;
                mem_bus_wait_states  = 3'd0;
            end
            3'b111: begin
                // 9.54 MHz (bit6=1), fast=1: 4 I/O WS (3 extra), 0 Mem Bus WS
                extra_io_wait_states = 3'd3;
                mem_bus_wait_states  = 3'd0;
            end
            default: begin
                extra_io_wait_states = 3'd0;
                mem_bus_wait_states  = 3'd0;
            end
        endcase
    end

    // ========================================================================
    // Bus operation detection
    // ========================================================================
    //
    // Detect start of I/O or memory bus operations (active when CPU drives bus)
    //
    wire io_operation     = (~io_read_n | ~io_write_n) & ~address_enable_n;
    wire mem_bus_operation = (~memory_read_n | ~memory_write_n) & ~address_enable_n & ~onboard_ram_access;

    // Edge detection for bus operation start
    reg prev_io_operation;
    reg prev_mem_bus_operation;

    always @(posedge clock or posedge reset) begin
        if (reset) begin
            prev_io_operation      <= 1'b0;
            prev_mem_bus_operation <= 1'b0;
        end else begin
            prev_io_operation      <= io_operation;
            prev_mem_bus_operation <= mem_bus_operation;
        end
    end

    wire io_start      = io_operation      & ~prev_io_operation;
    wire mem_bus_start  = mem_bus_operation & ~prev_mem_bus_operation;

    // ========================================================================
    // Wait state counter
    // ========================================================================
    //
    // When a bus operation starts:
    //   - Load counter with appropriate wait state count
    //   - Count down on each CPU clock positive edge
    //   - While counter > 0, fe2010a_ready is held low
    //   - When counter reaches 0, release ready (go high)
    //
    // If both an I/O and memory operation somehow start simultaneously
    // (shouldn't happen), I/O wait states take priority.
    //

    reg [2:0] wait_counter;
    reg       wait_active;

    always @(posedge clock or posedge reset) begin
        if (reset) begin
            wait_counter <= 3'd0;
            wait_active  <= 1'b0;
        end else if (io_start && extra_io_wait_states != 3'd0) begin
            // Start I/O wait state insertion
            wait_counter <= extra_io_wait_states;
            wait_active  <= 1'b1;
        end else if (mem_bus_start && mem_bus_wait_states != 3'd0) begin
            // Start memory bus wait state insertion
            wait_counter <= mem_bus_wait_states;
            wait_active  <= 1'b1;
        end else if (wait_active && cpu_clock_posedge) begin
            // Count down on CPU clock edges
            if (wait_counter == 3'd1) begin
                wait_counter <= 3'd0;
                wait_active  <= 1'b0;
            end else begin
                wait_counter <= wait_counter - 3'd1;
            end
        end else if (~io_operation & ~mem_bus_operation) begin
            // Bus operation ended — clear any remaining wait
            wait_counter <= 3'd0;
            wait_active  <= 1'b0;
        end
    end

    // ========================================================================
    // Output
    // ========================================================================
    //
    // fe2010a_ready is high (ready) when no extra wait states are needed,
    // and low (not ready) when the wait counter is active.
    //
    assign fe2010a_ready = ~wait_active;

endmodule
