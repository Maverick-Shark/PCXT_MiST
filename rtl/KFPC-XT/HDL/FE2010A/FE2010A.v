//
// Faraday FE2010A - PC Bus, CPU & Peripheral Controller
//
// FPGA implementation for PCXT MiST core
//
// This module integrates the functionality of:
//   - Intel 8284A Clock Generator (clock selection + ready signal)
//   - Intel 8288  Bus Controller
//   - Intel 8259A Programmable Interrupt Controller (PIC)
//   - Intel 8237A DMA Controller (4 channels)
//   - Intel 8253  Programmable Interval Timer (PIT)
//   - Intel 8255A Programmable Peripheral Interface (PPI) - Custom FE2010A version
//
// Also includes FE2010A-specific features:
//   - Configuration Register at port 0x63 (turbo, wait states, RAM size, freeze)
//   - Modified PPI with swapped Control Register bits 2/3
//   - NMI Mask Register at port 0xA0
//   - Integrated DMA Page Registers at ports 0x81-0x83
//   - XT-compatible I/O address decoding (lower 10 bits only)
//   - DRAM refresh control via PIT Channel 1 / DMA Channel 0
//
// Based on:
//   - Faraday FE2010 datasheet
//   - Faraday FE2010A reverse-engineered documentation by skiselev
//   - Proton PT8010AF documentation by skiselev
//   - KFPC-XT by kitune-san (KF8259, KF8253, KF8237, KF8288 sub-modules)
//
// References:
//   - https://github.com/skiselev/micro_8088/blob/master/Documentation/Faraday-XT_Controller-FE2010.pdf
//   - https://github.com/skiselev/micro_8088/blob/master/Documentation/Faraday-XT_Controller-FE2010A.md
//

module FE2010A (
    // ========================================================================
    // System clocks and reset
    // ========================================================================
    input  wire        clock,              // System clock (active-high, ~50 MHz)
    input  wire        cpu_clock,          // CPU clock from PLL
    input  wire        peripheral_clock,   // Peripheral clock (~1.19 MHz toggle)
    input  wire        reset,              // System reset (active-high)

    // ========================================================================
    // CPU interface (directly from 8088)
    // ========================================================================
    input  wire [19:0] cpu_address,        // CPU address bus A[19:0]
    input  wire [7:0]  cpu_data_bus,       // CPU data bus (output from CPU)
    input  wire [2:0]  processor_status,   // S0, S1, S2 status signals
    input  wire        processor_lock_n,   // LOCK# from CPU
    output wire        processor_transmit_or_receive_n,  // T/R# to data transceivers
    output wire        processor_ready,    // READY to CPU (active-high)
    output wire        interrupt_to_cpu,   // INT to CPU (active-high)

    // ========================================================================
    // Address bus interface
    // ========================================================================
    output wire [19:0] address,            // Latched/muxed address bus
    input  wire [19:0] address_ext,        // External address (for bus master)
    output wire        address_direction,  // 0=internal drives, 1=external drives
    output wire        address_latch_enable, // ALE signal

    // ========================================================================
    // Data bus interface
    // ========================================================================
    output wire [7:0]  internal_data_bus,  // Internal data bus
    input  wire [7:0]  data_bus_ext,       // External data input
    output wire        data_bus_direction, // 0=internal drives, 1=external drives

    // ========================================================================
    // Bus command signals
    // ========================================================================
    output wire        io_read_n,
    input  wire        io_read_n_ext,
    output wire        io_read_n_direction,
    output wire        io_write_n,
    input  wire        io_write_n_ext,
    output wire        io_write_n_direction,
    output wire        memory_read_n,
    input  wire        memory_read_n_ext,
    output wire        memory_read_n_direction,
    output wire        memory_write_n,
    input  wire        memory_write_n_ext,
    output wire        memory_write_n_direction,
    output wire        no_command_state,

    // ========================================================================
    // DMA interface
    // ========================================================================
    input  wire        ext_access_request, // External bus master request
    input  wire [3:0]  dma_request,        // DMA request inputs [3:1] from bus, [0] internal refresh
    output wire [3:0]  dma_acknowledge_n,  // DMA acknowledge outputs (active-low)
    output wire        address_enable_n,   // Address enable (active-low)
    output wire        terminal_count_n,   // Terminal count (active-low)

    // ========================================================================
    // Interrupt request inputs (directly to internal PIC)
    // ========================================================================
    //   IRQ[0] = timer (internal, PIT Channel 0)
    //   IRQ[1] = keyboard (internal)
    //   IRQ[2:7] = directly from input, but IRQ3/IRQ4 may be overridden by UART
    input  wire [7:0]  interrupt_request,

    // UART interrupts (directly wired to PIC IRQ3/IRQ4)
    input  wire        uart_interrupt,     // COM1 IRQ4
    input  wire        uart2_interrupt,    // COM2 IRQ3
    input  wire        uart2_active,       // COM2 chip select (forces IRQ low)

    // ========================================================================
    // I/O channel signals
    // ========================================================================
    input  wire        io_channel_check,   // I/O CH CHK from expansion bus
    input  wire        io_channel_ready,   // IORDY from expansion bus

    // ========================================================================
    // Keyboard interface (from PS/2 converter)
    // ========================================================================
    input  wire [7:0]  keyboard_data,      // Scan code from KFPS2KB module
    input  wire        keyboard_irq,       // IRQ from KFPS2KB module

    // ========================================================================
    // Timer / Speaker outputs
    // ========================================================================
    output wire [2:0]  timer_counter_out,  // PIT Channel 0, 1, 2 outputs
    output wire        speaker_out,        // Speaker output (Ch2 AND enable)

    // ========================================================================
    // Configuration inputs (from physical pins or OSD)
    // ========================================================================
    input  wire [1:0]  vid_in,             // VID0, VID1 display type

    // ========================================================================
    // Configuration outputs (active signals from config register 0x63)
    // ========================================================================
    output wire [1:0]  clk_select_out,     // Clock speed: 00=4.77, 01=7.15, 10=9.54 MHz
    output wire        fast_mode,          // 1=zero on-board memory wait states
    output wire [1:0]  ram_size_cfg,       // RAM size config (bits 4,2 of config reg)

    // ========================================================================
    // NMI output
    // ========================================================================
    output wire        nmi_enable,         // NMI enable (bit 7 of NMI mask register 0xA0)

    // ========================================================================
    // Internal chipset data bus output (for Peripherals.sv data bus mux)
    // ========================================================================
    output reg  [7:0]  chipset_data_out,
    output reg         chipset_data_out_valid,

    // ========================================================================
    // Ready logic interface
    // ========================================================================
    output wire        dma_ready,
    output wire        dma_wait_n
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
    // Peripheral clock edge detection (for PIT timer clock generation)
    // ========================================================================
    reg prev_p_clock_1;
    reg prev_p_clock_2;

    always @(posedge clock or posedge reset) begin
        if (reset) begin
            prev_p_clock_1 <= 1'b0;
            prev_p_clock_2 <= 1'b0;
        end else begin
            prev_p_clock_1 <= peripheral_clock;
            prev_p_clock_2 <= prev_p_clock_1;
        end
    end

    wire p_clock_posedge = prev_p_clock_1 & ~prev_p_clock_2;

    // Timer clock: divide peripheral_clock by 2 to get ~1.19 MHz / 2
    reg timer_clock;
    always @(posedge clock or posedge reset) begin
        if (reset)
            timer_clock <= 1'b0;
        else if (p_clock_posedge)
            timer_clock <= ~timer_clock;
    end

    // ========================================================================
    // I/O Address Decode — XT Compatible
    // ========================================================================
    // The FE2010A decodes I/O addresses using only the lower 10 bits (A[9:0]).
    // Upper bits A[15:10] are "don't care" per the original IBM PC I/O scheme.
    //
    // Address Map:
    //   0x00-0x0F : DMA Controller (8237)
    //   0x20-0x21 : Interrupt Controller (8259)
    //   0x40-0x43 : Timer (8253)
    //   0x60-0x63 : PPI (FE2010A custom: keyboard, control, switch, config)
    //   0x80-0x83 : DMA Page Registers
    //   0xA0      : NMI Mask Register
    //
    // Decode: A[9:8] must be 00 for all internal peripherals, then A[7:5]
    // selects the chip group.
    //

    wire iorq = ~io_read_n | ~io_write_n;

    reg [7:0] chip_select_n;

    always @(*) begin
        if (iorq & ~address_enable_n & ~address[9] & ~address[8]) begin
            case (address[7:5])
                3'b000: chip_select_n = 8'b11111110;  // 0x00-0x1F: DMA
                3'b001: chip_select_n = 8'b11111101;  // 0x20-0x3F: PIC
                3'b010: chip_select_n = 8'b11111011;  // 0x40-0x5F: PIT
                3'b011: chip_select_n = 8'b11110111;  // 0x60-0x7F: PPI
                3'b100: chip_select_n = 8'b11101111;  // 0x80-0x9F: DMA Page
                3'b101: chip_select_n = 8'b11011111;  // 0xA0-0xBF: NMI Mask
                default: chip_select_n = 8'b11111111;
            endcase
        end else begin
            chip_select_n = 8'b11111111;
        end
    end

    wire dma_chip_select_n       = chip_select_n[0];  // 0x00-0x1F
    wire interrupt_chip_select_n = chip_select_n[1];  // 0x20-0x3F
    wire timer_chip_select_n     = chip_select_n[2];  // 0x40-0x5F
    wire ppi_chip_select_n       = chip_select_n[3];  // 0x60-0x7F
    wire dma_page_chip_select_n  = chip_select_n[4];  // 0x80-0x9F
    wire nmi_chip_select_n       = chip_select_n[5];  // 0xA0-0xBF


    // ========================================================================
    // Hold/Acknowledge and Address Enable logic (from Bus_Arbiter)
    // ========================================================================
    reg  hold_request_ff_1;
    reg  hold_request_ff_2;
    wire dma_hold_request;

    wire hold_request     = dma_hold_request | ext_access_request;
    wire hold_acknowledge = hold_request ? hold_request_ff_2 : 1'b0;

    always @(posedge clock or posedge reset) begin
        if (reset)
            hold_request_ff_1 <= 1'b0;
        else if (cpu_clock_posedge) begin
            if (processor_status[0] & processor_status[1] & processor_lock_n & hold_request)
                hold_request_ff_1 <= 1'b1;
            else
                hold_request_ff_1 <= 1'b0;
        end
    end

    always @(posedge clock or posedge reset) begin
        if (reset)
            hold_request_ff_2 <= 1'b0;
        else if (cpu_clock_negedge) begin
            if (~hold_request)
                hold_request_ff_2 <= 1'b0;
            else if (hold_request_ff_2)
                hold_request_ff_2 <= 1'b1;
            else
                hold_request_ff_2 <= hold_request_ff_1;
        end
    end

    // Address Enable
    reg address_enable_n_reg;
    always @(posedge clock or posedge reset) begin
        if (reset)
            address_enable_n_reg <= 1'b1;
        else if (cpu_clock_posedge)
            address_enable_n_reg <= hold_acknowledge;
    end
    assign address_enable_n = address_enable_n_reg;

    // DMA Wait
    reg dma_wait;
    always @(posedge clock or posedge reset) begin
        if (reset)
            dma_wait <= 1'b0;
        else if (cpu_clock_posedge)
            dma_wait <= address_enable_n_reg;
    end
    assign dma_wait_n = ~dma_wait;

    // DMA Enable
    wire dma_enable_n = ~(dma_wait & address_enable_n_reg);


    // ========================================================================
    // 8288 Bus Controller (KF8288)
    // ========================================================================
    wire bc_io_write_n;
    wire bc_io_read_n;
    wire bc_enable_io;
    wire bc_memory_write_n;
    wire bc_memory_read_n;
    wire bc_memory_enable;
    wire direction_transmit_or_receive_n;
    wire data_enable;
    wire interrupt_acknowledge_n;

    KF8288 u_KF8288 (
        .clock                              (clock),
        .cpu_clock                          (cpu_clock),
        .reset                              (reset),
        .address_enable_n                   (address_enable_n_reg),
        .command_enable                     (~address_enable_n_reg),
        .io_bus_mode                        (1'b0),
        .processor_status                   (processor_status),
        .enable_io_command                  (bc_enable_io),
        .advanced_io_write_command_n        (bc_io_write_n),
        .io_read_command_n                  (bc_io_read_n),
        .interrupt_acknowledge_n            (interrupt_acknowledge_n),
        .enable_memory_command              (bc_memory_enable),
        .advanced_memory_write_command_n    (bc_memory_write_n),
        .memory_read_command_n              (bc_memory_read_n),
        .direction_transmit_or_receive_n    (direction_transmit_or_receive_n),
        .data_enable                        (data_enable),
        .address_latch_enable               (address_latch_enable)
    );

    assign processor_transmit_or_receive_n = direction_transmit_or_receive_n;


    // ========================================================================
    // 8237 DMA Controller (KF8237)
    // ========================================================================
    wire        dma_io_write_n;
    wire [7:0]  dma_data_out;
    wire        dma_io_read_n;
    wire        terminal_count;
    wire [15:0] dma_address_out;
    wire        dma_memory_read_n;
    wire        dma_memory_write_n;

    KF8237 u_KF8237 (
        .clock                              (clock),
        .cpu_clock                          (cpu_clock),
        .reset                              (reset),
        .chip_select_n                      (dma_chip_select_n),
        .ready                              (dma_ready),
        .hold_acknowledge                   (hold_acknowledge & ~ext_access_request),
        .dma_request                        (dma_request),
        .data_bus_in                        (internal_data_bus),
        .data_bus_out                       (dma_data_out),
        .io_read_n_in                       (io_read_n),
        .io_read_n_out                      (dma_io_read_n),
        .io_write_n_in                      (io_write_n),
        .io_write_n_out                     (dma_io_write_n),
        .end_of_process_n_in                (1'b1),
        .end_of_process_n_out               (terminal_count),
        .address_in                         (address[3:0]),
        .address_out                        (dma_address_out),
        .hold_request                       (dma_hold_request),
        .dma_acknowledge                    (dma_acknowledge_n),
        .memory_read_n                      (dma_memory_read_n),
        .memory_write_n                     (dma_memory_write_n)
    );

    assign terminal_count_n = ~terminal_count;


    // ========================================================================
    // DMA Page Registers (integrated, replaces external 74xx670)
    // ========================================================================
    // Address mapping:
    //   0x81 = DMA Channel 2
    //   0x82 = DMA Channel 3
    //   0x83 = DMA Channel 1
    // Data bits 0-3 = Address bits 16-19

    reg [3:0] dma_page_register [0:3];

    integer dma_page_i;
    always @(posedge clock or posedge reset) begin
        if (reset) begin
            dma_page_register[0] <= 4'd0;
            dma_page_register[1] <= 4'd0;
            dma_page_register[2] <= 4'd0;
            dma_page_register[3] <= 4'd0;
        end else if (~dma_page_chip_select_n & ~io_write_n) begin
            dma_page_register[address[1:0]] <= internal_data_bus[3:0];
        end
    end


    // ========================================================================
    // R/W Command Signal Generation
    // ========================================================================
    wire ab_io_write_n     = ~((~bc_io_write_n     & bc_enable_io)     | ~dma_io_write_n);
    wire ab_io_read_n      = ~((~bc_io_read_n      & bc_enable_io)     | ~dma_io_read_n);
    wire ab_memory_write_n = ~((~bc_memory_write_n  & bc_memory_enable) | ~dma_memory_write_n);
    wire ab_memory_read_n  = ~((~bc_memory_read_n   & bc_memory_enable) | ~dma_memory_read_n);

    assign io_write_n_direction     = ab_io_write_n;
    assign io_read_n_direction      = ab_io_read_n;
    assign memory_write_n_direction = ab_memory_write_n;
    assign memory_read_n_direction  = ab_memory_read_n;

    assign io_write_n     = io_write_n_direction     ? io_write_n_ext     : ab_io_write_n;
    assign io_read_n      = io_read_n_direction      ? io_read_n_ext      : ab_io_read_n;
    assign memory_write_n = memory_write_n_direction ? memory_write_n_ext : ab_memory_write_n;
    assign memory_read_n  = memory_read_n_direction  ? memory_read_n_ext  : ab_memory_read_n;

    assign no_command_state = io_write_n & io_read_n & memory_write_n & memory_read_n;


    // ========================================================================
    // Address Bus Mux
    // ========================================================================
    reg  [19:0] address_mux;
    reg         address_dir_mux;

    always @(*) begin
        if (~dma_enable_n && ~(&dma_acknowledge_n)) begin
            // DMA is active — select DMA address with page register
            if (~dma_acknowledge_n[2]) begin
                address_mux   = {dma_page_register[1], dma_address_out};
                address_dir_mux = 1'b0;
            end else if (~dma_acknowledge_n[3]) begin
                address_mux   = {dma_page_register[2], dma_address_out};
                address_dir_mux = 1'b0;
            end else begin
                address_mux   = {dma_page_register[3], dma_address_out};
                address_dir_mux = 1'b0;
            end
        end else if (~address_enable_n_reg) begin
            // CPU is driving the bus
            address_mux   = cpu_address;
            address_dir_mux = 1'b0;
        end else begin
            // External bus master
            address_mux   = address_ext;
            address_dir_mux = 1'b1;
        end
    end

    assign address           = address_mux;
    assign address_direction = address_dir_mux;


    // ========================================================================
    // Data Bus Mux
    // ========================================================================
    reg [7:0] internal_data_bus_mux;
    reg       data_bus_dir_mux;

    always @(*) begin
        if (~interrupt_acknowledge_n) begin
            internal_data_bus_mux = data_bus_ext;
            data_bus_dir_mux      = 1'b0;
        end else if (data_enable & direction_transmit_or_receive_n) begin
            internal_data_bus_mux = cpu_data_bus;
            data_bus_dir_mux      = 1'b0;
        end else if (~dma_chip_select_n & ~io_read_n) begin
            internal_data_bus_mux = dma_data_out;
            data_bus_dir_mux      = 1'b0;
        end else begin
            internal_data_bus_mux = data_bus_ext;
            data_bus_dir_mux      = 1'b1;
        end
    end

    assign internal_data_bus = internal_data_bus_mux;
    assign data_bus_direction = data_bus_dir_mux;


    // ========================================================================
    // 8259 Programmable Interrupt Controller (KF8259)
    // ========================================================================
    wire [7:0] interrupt_data_bus_out;
    wire       interrupt_to_cpu_buf;
    wire       timer_interrupt;
    wire       keyboard_interrupt_out;

    KF8259 u_KF8259 (
        .clock                      (clock),
        .reset                      (reset),
        .chip_select_n              (interrupt_chip_select_n),
        .read_enable_n              (io_read_n),
        .write_enable_n             (io_write_n),
        .address                    (address[0]),
        .data_bus_in                (internal_data_bus),
        .data_bus_out               (interrupt_data_bus_out),

        .cascade_in                 (3'b000),
        .slave_program_n            (1'b1),
        .interrupt_acknowledge_n    (interrupt_acknowledge_n),
        .interrupt_to_cpu           (interrupt_to_cpu_buf),
        .interrupt_request          ({interrupt_request[7:5],
                                      uart_interrupt,
                                      uart2_interrupt & ~uart2_active,
                                      interrupt_request[2],
                                      keyboard_interrupt_out,
                                      timer_interrupt})
    );

    // Synchronize interrupt output to CPU clock
    reg interrupt_to_cpu_reg;
    always @(posedge clock or posedge reset) begin
        if (reset)
            interrupt_to_cpu_reg <= 1'b0;
        else if (cpu_clock_negedge)
            interrupt_to_cpu_reg <= interrupt_to_cpu_buf;
    end
    assign interrupt_to_cpu = interrupt_to_cpu_reg;


    // ========================================================================
    // 8253 Programmable Interval Timer (KF8253)
    // ========================================================================
    wire [7:0] timer_data_bus_out;

    // Timer 2 gate and speaker control — from PPI control register
    wire tim2gatespk;
    wire spkdata;

    KF8253 u_KF8253 (
        .clock                      (clock),
        .reset                      (reset),
        .chip_select_n              (timer_chip_select_n),
        .read_enable_n              (io_read_n),
        .write_enable_n             (io_write_n),
        .address                    (address[1:0]),
        .data_bus_in                (internal_data_bus),
        .data_bus_out               (timer_data_bus_out),

        // Channel 0: System timer -> IRQ0
        .counter_0_clock            (timer_clock),
        .counter_0_gate             (1'b1),
        .counter_0_out              (timer_counter_out[0]),

        // Channel 1: DRAM refresh -> DRQ0
        .counter_1_clock            (timer_clock),
        .counter_1_gate             (1'b1),
        .counter_1_out              (timer_counter_out[1]),

        // Channel 2: Speaker tone generation
        .counter_2_clock            (timer_clock),
        .counter_2_gate             (tim2gatespk),
        .counter_2_out              (timer_counter_out[2])
    );

    assign timer_interrupt = timer_counter_out[0];
    assign speaker_out     = timer_counter_out[2] & spkdata;


    // ========================================================================
    // FE2010A Custom PPI (replaces standard 8255)
    // ========================================================================
    wire [7:0] ppi_data_bus_out;
    wire       config_write;
    wire [7:0] config_data;
    wire       config_locked;
    wire       switch_select;
    wire       ppi_disable_parity;
    wire       ppi_disable_io_check;

    fe2010a_ppi u_ppi (
        .clock                      (clock),
        .reset                      (reset),

        // Bus interface
        .chip_select_n              (ppi_chip_select_n),
        .read_enable_n              (io_read_n),
        .write_enable_n             (io_write_n),
        .address                    (address[1:0]),
        .data_bus_in                (internal_data_bus),
        .data_bus_out               (ppi_data_bus_out),

        // Keyboard
        .keyboard_data              (keyboard_data),
        .keyboard_irq_in            (keyboard_irq),
        .keyboard_irq_out           (keyboard_interrupt_out),

        // Timer 2
        .timer2_gate                (tim2gatespk),
        .speaker_enable             (spkdata),
        .timer2_output              (timer_counter_out[2]),

        // Switch select
        .switch_select              (switch_select),

        // Parity / I/O check
        .disable_parity             (ppi_disable_parity),
        .disable_io_check           (ppi_disable_io_check),

        // Switch register inputs
        .vid_in                     (vid_in),
        .io_channel_check           (io_channel_check),
        .ram_parity_check           (1'b0),  // No RAM parity in SRAM/SDRAM systems

        // Configuration register interface
        .config_write               (config_write),
        .config_data                (config_data),

        // Configuration lock input
        .config_locked              (config_locked)
    );


    // ========================================================================
    // FE2010A Configuration Register (port 0x63)
    // ========================================================================
    //
    // Bit 7: 9.54 MHz CPU clock
    // Bit 6: 7.15 MHz CPU clock
    // Bit 5: Fast Mode (0 RAM wait states)
    // Bit 4: On Board RAM size bit 1
    // Bit 3: Lock register (bits 0-4 frozen until reset)
    // Bit 2: On Board RAM size bit 0
    // Bit 1: Enable 8087 NMI
    // Bit 0: Disable Parity Checker
    //
    reg [7:0] config_reg;
    reg       config_lock;

    always @(posedge clock or posedge reset) begin
        if (reset) begin
            // Default: 4.77 MHz, parity enabled, no freeze
            config_reg  <= 8'h00;
            config_lock <= 1'b0;
        end else if (config_write) begin
            if (~config_lock) begin
                // Full register write
                config_reg  <= config_data;
                config_lock <= config_data[3];
            end else begin
                // Only bits 5-7 can be changed when locked
                config_reg[7:5] <= config_data[7:5];
            end
        end
    end

    assign config_locked = config_lock;

    // RAM size: bits [4,2]
    //   00 = 640 KB (3 banks), 01 = 256 KB (1 bank), 10 = 512 KB (2 banks)
    assign ram_size_cfg = {config_reg[4], config_reg[2]};


    // ========================================================================
    // FE2010A Clock Generator (fe2010a_clkgen)
    // ========================================================================
    //
    // Translates Configuration Register bits [7:5] into the clk_select
    // format used by PCXT.sv, plus duty cycle and fast mode signals.
    //
    wire [3:0] cpu_clk_period;
    wire       duty_cycle_50;

    fe2010a_clkgen u_clkgen (
        .clock              (clock),
        .reset              (reset),
        .config_clk_bits    (config_reg[7:5]),
        .clk_select         (clk_select_out),
        .duty_cycle_50      (duty_cycle_50),
        .fast_mode          (fast_mode),
        .cpu_clk_period     (cpu_clk_period)
    );


    // ========================================================================
    // NMI Mask Register (port 0xA0)
    // ========================================================================
    // Write-only register. Bit 7 enables NMI to CPU.
    //
    reg [7:0] nmi_mask_reg;

    always @(posedge clock or posedge reset) begin
        if (reset)
            nmi_mask_reg <= 8'h00;
        else if (~nmi_chip_select_n & ~io_write_n)
            nmi_mask_reg <= internal_data_bus;
    end

    assign nmi_enable = nmi_mask_reg[7];


    // ========================================================================
    // FE2010A Wait State Generator (fe2010a_waitgen)
    // ========================================================================
    //
    // Generates additional wait states for I/O and memory bus operations
    // based on the CPU clock speed and Configuration Register bits [7:5].
    //
    // The output fe2010a_ready is ANDed with io_channel_ready before
    // entering the base ready logic. When fe2010a_ready goes low, extra
    // wait states are inserted beyond the base 1 WS that the ready logic
    // already provides.
    //
    wire fe2010a_ws_ready;

    fe2010a_waitgen u_waitgen (
        .clock              (clock),
        .cpu_clock          (cpu_clock),
        .reset              (reset),
        .config_clk_bits    (config_reg[7:5]),
        .io_read_n          (io_read_n),
        .io_write_n         (io_write_n),
        .memory_read_n      (memory_read_n),
        .memory_write_n     (memory_write_n),
        .address_enable_n   (address_enable_n_reg),
        .address            (address),
        .onboard_ram_access (1'b0),  // TODO: connect to RAM address decode
        .fe2010a_ready      (fe2010a_ws_ready)
    );

    // Combined ready signal: external IORDY AND FE2010A wait state generator
    wire combined_io_ready = io_channel_ready & fe2010a_ws_ready;


    // ========================================================================
    // Ready / Wait State Logic (replaces Ready.sv)
    // ========================================================================
    //
    // Base ready logic from the original Ready.sv, now driven by the
    // combined ready signal that includes FE2010A-generated wait states.
    //
    // At 4.77 MHz: fe2010a_ws_ready is always 1, so behavior is identical
    // to the original Ready.sv (1 base wait state on I/O operations).
    //
    // At higher speeds: fe2010a_ws_ready goes low for extra clock cycles,
    // causing the ready logic to insert additional wait states per the
    // FE2010A configuration table.
    //

    reg  prev_bus_state;
    reg  ready_n_or_wait;
    reg  ready_n_or_wait_Qn;
    reg  prev_ready_n_or_wait;

    wire bus_state = ~io_read_n | ~io_write_n | (dma_acknowledge_n[0] & ~memory_read_n & address_enable_n_reg);

    always @(posedge clock or posedge reset) begin
        if (reset)
            prev_bus_state <= 1'b1;
        else
            prev_bus_state <= bus_state;
    end

    always @(posedge clock or posedge reset) begin
        if (reset) begin
            ready_n_or_wait    <= 1'b1;
            ready_n_or_wait_Qn <= 1'b0;
        end else if (~combined_io_ready & prev_ready_n_or_wait) begin
            ready_n_or_wait    <= 1'b1;
            ready_n_or_wait_Qn <= 1'b1;
        end else if (~combined_io_ready & ~prev_ready_n_or_wait) begin
            ready_n_or_wait    <= 1'b1;
            ready_n_or_wait_Qn <= 1'b0;
        end else if (combined_io_ready & prev_ready_n_or_wait) begin
            ready_n_or_wait    <= 1'b0;
            ready_n_or_wait_Qn <= 1'b1;
        end else if (~prev_bus_state & bus_state) begin
            ready_n_or_wait    <= 1'b1;
            ready_n_or_wait_Qn <= 1'b0;
        end
    end

    always @(posedge clock or posedge reset) begin
        if (reset)
            prev_ready_n_or_wait <= 1'b0;
        else if (cpu_clock_posedge)
            prev_ready_n_or_wait <= ready_n_or_wait;
    end

    assign dma_ready = ~prev_ready_n_or_wait & ready_n_or_wait_Qn;

    // Ready signal to CPU (instead of 8284)
    reg processor_ready_ff_1;
    reg processor_ready_ff_2;

    always @(posedge clock or posedge reset) begin
        if (reset)
            processor_ready_ff_1 <= 1'b0;
        else if (cpu_clock_posedge)
            processor_ready_ff_1 <= dma_wait_n & ~ready_n_or_wait;
    end

    always @(posedge clock or posedge reset) begin
        if (reset)
            processor_ready_ff_2 <= 1'b0;
        else if (cpu_clock_negedge)
            processor_ready_ff_2 <= processor_ready_ff_1 & dma_wait_n & ~ready_n_or_wait;
    end

    assign processor_ready = processor_ready_ff_2;


    // ========================================================================
    // Chipset Data Bus Output Mux
    // ========================================================================
    // Priority: interrupt ack > PIC read > PIT read > PPI read > NMI mask read
    //
    always @(posedge clock) begin
        if (~interrupt_acknowledge_n) begin
            chipset_data_out_valid <= 1'b1;
            chipset_data_out       <= interrupt_data_bus_out;
        end else if (~interrupt_chip_select_n & ~io_read_n) begin
            chipset_data_out_valid <= 1'b1;
            chipset_data_out       <= interrupt_data_bus_out;
        end else if (~timer_chip_select_n & ~io_read_n) begin
            chipset_data_out_valid <= 1'b1;
            chipset_data_out       <= timer_data_bus_out;
        end else if (~ppi_chip_select_n & ~io_read_n) begin
            chipset_data_out_valid <= 1'b1;
            chipset_data_out       <= ppi_data_bus_out;
        end else if (~nmi_chip_select_n & ~io_read_n) begin
            chipset_data_out_valid <= 1'b1;
            chipset_data_out       <= nmi_mask_reg;
        end else begin
            chipset_data_out_valid <= 1'b0;
            chipset_data_out       <= 8'h00;
        end
    end

endmodule
