//
// MiSTer PCXT Chipset
// Ported by @spark2k06
//
// Based on KFPC-XT written by @kitune-san
//
module CHIPSET #(
        parameter clk_rate = 28'd50000000)
        (
        input   logic           clock,
        input   logic           cpu_clock,
        input   logic           clk_sys,
        input   logic           peripheral_clock,
        input   logic   [1:0]   clk_select,
        input   logic           color,
        input   logic           reset,
        input   logic           sdram_reset,
        // Chipset selection: 0=Standard (IBM XT), 1=Faraday FE2010A
        input   logic           chipset_select,
        // CPU
        input   logic   [19:0]  cpu_address,
        input   logic   [7:0]   cpu_data_bus,
        input   logic   [2:0]   processor_status,
        input   logic           processor_lock_n,
        output  logic           processor_transmit_or_receive_n,
        output  logic           processor_ready,
        output  logic           interrupt_to_cpu,
        // SplashScreen
        input   logic           splashscreen,
        // VGA
   //   output  logic           std_hsyncwidth,
   //   input   logic           composite,
        input   logic           video_output,
        input   logic           clk_vga_cga,
        input   logic           enable_cga,
        input   logic           clk_vga_mda,
        input   logic           enable_mda,
        input   logic   [1:0]   mda_rgb,
        output  logic           hgc_grph_mode,
        output  logic           hgc_grph_page,
        output  logic           de_o,
        output  logic   [5:0]   VGA_R,
        output  logic   [5:0]   VGA_G,
        output  logic   [5:0]   VGA_B,
        output  logic           VGA_HSYNC,
        output  logic           VGA_VSYNC,
        output  logic           VGA_HBlank,
        output  logic           VGA_VBlank,
   //   output  logic           VGA_VBlank_border,
        input   logic           scandoubler,
        output  reg     [6:0]   comp_video,
        output  logic   [1:0]   composite_out,
        input   logic           composite_on,
        input   logic           vga_composite,
        input   logic   [17:0]  rgb_18b,
        // I/O Ports
        output  logic   [19:0]  address,
        input   logic   [19:0]  address_ext,
        output  logic           address_direction,
        output  logic   [7:0]   data_bus,
        input   logic   [7:0]   data_bus_ext,
        output  logic           data_bus_direction,
        output  logic           address_latch_enable,
        input   logic           io_channel_check,
        input   logic           io_channel_ready,
        input   logic   [7:0]   interrupt_request,
        output  logic           io_read_n,
        input   logic           io_read_n_ext,
        output  logic           io_read_n_direction,
        output  logic           io_write_n,
        input   logic           io_write_n_ext,
        output  logic           io_write_n_direction,
        output  logic           memory_read_n,
        input   logic           memory_read_n_ext,
        output  logic           memory_read_n_direction,
        output  logic           memory_write_n,
        input   logic           memory_write_n_ext,
        output  logic           memory_write_n_direction,
        input   logic           ext_access_request,
        input   logic   [3:0]   dma_request,
        output  logic   [3:0]   dma_acknowledge_n,
        output  logic           address_enable_n,
        output  logic           terminal_count_n,
        // Peripherals
        output  logic   [2:0]   timer_counter_out,
        output  logic           speaker_out,
        output  logic   [7:0]   port_a_out,
        output  logic           port_a_io,
        input   logic   [7:0]   port_b_in,
        output  logic   [7:0]   port_b_out,
        output  logic           port_b_io,
        input   logic   [7:0]   port_c_in,
        output  logic   [7:0]   port_c_out,
        output  logic   [7:0]   port_c_io,
        input   logic           ps2_clock,
        input   logic           ps2_data,
        output  logic           ps2_clock_out,
        output  logic           ps2_data_out,
        input   logic           ps2_mouseclk_in,
        input   logic           ps2_mousedat_in,
        output  logic           ps2_mouseclk_out,
        output  logic           ps2_mousedat_out,
        input   logic   [4:0]   joy_opts,
        input   logic   [31:0]  joy0,
        input   logic   [31:0]  joy1,
        input   logic   [15:0]  joya0,
        input   logic   [15:0]  joya1,
        // JTOPL
        output  logic   [15:0]  jtopl2_snd_e,
        input   logic   [1:0]   opl2_io,
        // C/MS Audio
        input   logic           cms_en,
        output  logic   [15:0]  o_cms_l,
        output  logic   [15:0]  o_cms_r,
        // TANDY
        input   logic           tandy_video,
        input   logic           tandy_bios_flag,
        output  logic   [10:0]  tandy_snd_e,
   //   output  logic           tandy_16_gfx,
   //   output  logic           tandy_color_16,
        // UART
        input   logic           clk_uart,
        input   logic           clk_uart2,
        input   logic           uart_rx,
        output  logic           uart_tx,
        input   logic           uart_cts_n,
        input   logic           uart_dcd_n,
        input   logic           uart_dsr_n,
        output  logic           uart_rts_n,
        output  logic           uart_dtr_n,
        // SDRAM
        input   logic           enable_sdram,
        output  logic           initilized_sdram,
        input   logic           sdram_clock,    // 50MHz
        output  logic   [12:0]  sdram_address,
        output  logic           sdram_cke,
        output  logic           sdram_cs,
        output  logic           sdram_ras,
        output  logic           sdram_cas,
        output  logic           sdram_we,
        output  logic   [1:0]   sdram_ba,
        input   logic   [15:0]  sdram_dq_in,
        output  logic   [15:0]  sdram_dq_out,
        output  logic           sdram_dq_io,
        output  logic           sdram_ldqm,
        output  logic           sdram_udqm,
        // EMS
        input   logic           ems_enabled,
        input   logic   [1:0]   ems_address,
        // BIOS
        input  logic    [1:0]   bios_protect_flag,
        //
        input   logic   [27:0]  clock_rate,
        // Primary IDE Bus
        output  logic    [3:0]  ide0_addr,
        output  logic   [15:0]  ide0_writedata,
        input   logic   [15:0]  ide0_readdata,
        output  logic           ide0_read,
        output  logic           ide0_write,
        // Real time clock
        input   logic   [63:0]  rtc_data,
        // XTCTL DATA
        output  logic   [7:0]   xtctl,
        // Optional flags
        input   logic           enable_a000h,
        // RAM wait mode
        input   logic           wait_count_clk_en,
        input   logic   [1:0]   ram_read_wait_cycle,
        input   logic   [1:0]   ram_write_wait_cycle,
        output  logic           pause_core
    );

	 logic   [19:0]  latch_address;
	 
    logic           dma_ready;
    logic           dma_wait_n;
    logic           interrupt_acknowledge_n;
    logic           dma_chip_select_n;
    logic           dma_page_chip_select_n;
    logic           memory_access_ready;
    logic           ram_address_select_n;
    logic   [7:0]   internal_data_bus;
    logic   [7:0]   internal_data_bus_ext;
    logic   [7:0]   internal_data_bus_chipset;
    logic   [7:0]   internal_data_bus_ram;
    logic           data_bus_out_from_chipset;
    logic           internal_data_bus_direction;
    logic           no_command_state;

    logic   [6:0]   map_ems[0:3];
    logic           ena_ems[0:3];
    logic           ems_b1;
    logic           ems_b2;
    logic           ems_b3;
    logic           ems_b4;
    logic           tandy_snd_rdy;

    // ========================================================================
    // Standard Chipset path (Bus_Arbiter + Ready)
    // Active when chipset_select = 0
    // ========================================================================

    logic           prev_timer_count_1;
    logic           DRQ0;

    // Standard chipset output wires
    logic           std_processor_ready;
    logic           std_dma_ready;
    logic           std_dma_wait_n;

    always_ff @(posedge clock)
    begin
        if (reset)
            prev_timer_count_1 <= 1'b1;
        else
            prev_timer_count_1 <= timer_counter_out[1];
    end

    always_ff @(posedge clock, posedge reset)
    begin
        if (reset)
            DRQ0 <= 1'b0;
        else if (~dma_acknowledge_n[0])
            DRQ0 <= 1'b0;
        else if (~prev_timer_count_1 & timer_counter_out[1])
            DRQ0 <= 1'b1;
        else
            DRQ0 <= DRQ0;
    end

    READY u_READY 
    (
        .clock                              (clock),
        .cpu_clock                          (cpu_clock),
        .reset                              (reset),
        .processor_ready                    (std_processor_ready),
        .dma_ready                          (std_dma_ready),
        .dma_wait_n                         (std_dma_wait_n),
        .io_channel_ready                   (io_channel_ready & memory_access_ready & tandy_snd_rdy),
        .io_read_n                          (io_read_n),
        .io_write_n                         (io_write_n),
        .memory_read_n                      (memory_read_n),
        .dma0_acknowledge_n                 (dma_acknowledge_n[0]),
        .address_enable_n                   (address_enable_n)
    );

    BUS_ARBITER u_BUS_ARBITER 
    (
        .clock                              (clock),
        .cpu_clock                          (cpu_clock),
        .reset                              (reset),
        .cpu_address                        (cpu_address),
        .cpu_data_bus                       (cpu_data_bus),
        .processor_status                   (processor_status),
        .processor_lock_n                   (processor_lock_n),
        .processor_transmit_or_receive_n    (processor_transmit_or_receive_n),
        .dma_ready                          (dma_ready),
        .dma_wait_n                         (dma_wait_n),
        .interrupt_acknowledge_n            (interrupt_acknowledge_n),
        .dma_chip_select_n                  (dma_chip_select_n),
        .dma_page_chip_select_n             (dma_page_chip_select_n),
        .address                            (address),
        .address_ext                        (address_ext),
        .address_direction                  (address_direction),
        .data_bus_ext                       (internal_data_bus_ext),
        .internal_data_bus                  (internal_data_bus),
        .data_bus_direction                 (internal_data_bus_direction),
        .address_latch_enable               (address_latch_enable),
        .io_read_n                          (io_read_n),
        .io_read_n_ext                      (io_read_n_ext),
        .io_read_n_direction                (io_read_n_direction),
        .io_write_n                         (io_write_n),
        .io_write_n_ext                     (io_write_n_ext),
        .io_write_n_direction               (io_write_n_direction),
        .memory_read_n                      (memory_read_n),
        .memory_read_n_ext                  (memory_read_n_ext),
        .memory_read_n_direction            (memory_read_n_direction),
        .memory_write_n                     (memory_write_n),
        .memory_write_n_ext                 (memory_write_n_ext),
        .memory_write_n_direction           (memory_write_n_direction),
        .no_command_state                   (no_command_state),
        .ext_access_request                 (ext_access_request),
        .dma_request                        ({dma_request[3:1], DRQ0}),
        .dma_acknowledge_n                  (dma_acknowledge_n),
        .address_enable_n                   (address_enable_n),
        .terminal_count_n                   (terminal_count_n)
    );

    // ========================================================================
    // Faraday FE2010A Chipset path
    // Active when chipset_select = 1
    // ========================================================================

    logic           fe_processor_ready;
    logic           fe_dma_ready;
    logic           fe_dma_wait_n;
    logic           fe_interrupt_to_cpu;
    logic   [2:0]   fe_timer_counter_out;
    logic           fe_speaker_out;
    logic   [7:0]   fe_chipset_data_out;
    logic           fe_chipset_data_out_valid;
    logic   [1:0]   fe_clk_select;
    logic           fe_fast_mode;
    logic           fe_nmi_enable;

    // Keyboard data for FE2010A PPI (from KFPS2KB in Peripherals)
    // These are provided by Peripherals via port_a_out when in standard mode.
    // In FE2010A mode, keyboard data comes through the same PS/2 converter
    // but is handled internally by the FE2010A PPI.
    // We pass port_a_out (which Peripherals fills with keycode) to FE2010A.
    // The keyboard IRQ comes from Peripherals' internal keybord_interrupt.

    FE2010A u_FE2010A (
        .clock                      (clock),
        .cpu_clock                  (cpu_clock),
        .peripheral_clock           (peripheral_clock),
        .reset                      (reset),

        // CPU interface (directly from 8088)
        .cpu_address                (cpu_address),
        .cpu_data_bus               (cpu_data_bus),
        .processor_status           (processor_status),
        .processor_lock_n           (processor_lock_n),
        .processor_transmit_or_receive_n (),    // Bus_Arbiter drives this
        .processor_ready            (fe_processor_ready),
        .interrupt_to_cpu           (fe_interrupt_to_cpu),

        // Address bus (directly connected - same as Bus_Arbiter)
        .address                    (),         // Bus_Arbiter drives address
        .address_ext                (address_ext),
        .address_direction          (),
        .address_latch_enable       (),

        // Data bus
        .internal_data_bus          (),         // Bus_Arbiter drives this
        .data_bus_ext               (internal_data_bus_ext),
        .data_bus_direction         (),

        // Bus commands
        .io_read_n                  (),         // Bus_Arbiter drives these
        .io_read_n_ext              (io_read_n_ext),
        .io_read_n_direction        (),
        .io_write_n                 (),
        .io_write_n_ext             (io_write_n_ext),
        .io_write_n_direction       (),
        .memory_read_n              (),
        .memory_read_n_ext          (memory_read_n_ext),
        .memory_read_n_direction    (),
        .memory_write_n             (),
        .memory_write_n_ext         (memory_write_n_ext),
        .memory_write_n_direction   (),
        .no_command_state           (),

        // DMA
        .ext_access_request         (ext_access_request),
        .dma_request                (dma_request),
        .dma_acknowledge_n          (),         // Bus_Arbiter drives this
        .address_enable_n           (),
        .terminal_count_n           (),

        // Interrupts
        .interrupt_request          (interrupt_request),
        .uart_interrupt             (1'b0),     // Connected via Peripherals
        .uart2_interrupt            (1'b0),
        .uart2_active               (1'b0),

        // I/O channel
        .io_channel_check           (io_channel_check),
        .io_channel_ready           (io_channel_ready & memory_access_ready & tandy_snd_rdy),

        // Keyboard (from KFPS2KB via port_a_out)
        .keyboard_data              (port_a_out),
        .keyboard_irq               (1'b0),     // Handled via Peripherals keyboard path

        // Timer / Speaker
        .timer_counter_out          (fe_timer_counter_out),
        .speaker_out                (fe_speaker_out),

        // Config inputs
        .vid_in                     (2'b00),    // TODO: connect to actual video type

        // Config outputs
        .clk_select_out             (fe_clk_select),
        .fast_mode                  (fe_fast_mode),
        .ram_size_cfg               (),
        .nmi_enable                 (fe_nmi_enable),

        // Chipset data output
        .chipset_data_out           (fe_chipset_data_out),
        .chipset_data_out_valid     (fe_chipset_data_out_valid),

        // Ready
        .dma_ready                  (fe_dma_ready),
        .dma_wait_n                 (fe_dma_wait_n)
    );

    // ========================================================================
    // Chipset output mux
    // ========================================================================
    // Select between Standard and FE2010A chipset based on chipset_select.
    // Bus_Arbiter always drives the bus signals (address, data, commands)
    // since both chipsets generate identical bus cycles from 8088 status.
    // The difference is in ready timing, PIC/PIT/PPI behavior.

    assign processor_ready = chipset_select ? fe_processor_ready : std_processor_ready;
    assign dma_ready       = chipset_select ? fe_dma_ready       : std_dma_ready;
    assign dma_wait_n      = chipset_select ? fe_dma_wait_n      : std_dma_wait_n;

    PERIPHERALS #(.clk_rate(clk_rate)) u_PERIPHERALS 
    (
        .clock                              (clock),
        .clk_sys                            (clk_sys),
        .cpu_clock                          (cpu_clock),
        .clk_uart                           (clk_uart),
        .clk_uart2                          (clk_uart2),
        .peripheral_clock                   (peripheral_clock),
        .color                              (color),
        .clk_select                         (clk_select),
        .reset                              (reset),
        // FE2010A mode: disables PIC/PIT/PPI in Peripherals
        .fe2010a_mode                       (chipset_select),
        // In FE2010A mode, use FE2010A's interrupt/timer/speaker outputs
        .fe2010a_interrupt_to_cpu           (fe_interrupt_to_cpu),
        .fe2010a_timer_counter_out          (fe_timer_counter_out),
        .fe2010a_speaker_out                (fe_speaker_out),
        .fe2010a_chipset_data_out           (fe_chipset_data_out),
        .fe2010a_chipset_data_out_valid     (fe_chipset_data_out_valid),
        .interrupt_to_cpu                   (interrupt_to_cpu),
        .interrupt_acknowledge_n            (interrupt_acknowledge_n),
        .dma_chip_select_n                  (dma_chip_select_n),
        .dma_page_chip_select_n             (dma_page_chip_select_n),
        .splashscreen                       (splashscreen),
     // .std_hsyncwidth                     (std_hsyncwidth),
     // .composite                          (composite),
        .video_output                       (video_output),
        .clk_vga_cga                        (clk_vga_cga),
        .enable_cga                         (enable_cga),
        .clk_vga_mda                        (clk_vga_mda),
        .enable_mda                         (enable_mda),
        .mda_rgb                            (mda_rgb),
        .hgc_grph_mode                      (hgc_grph_mode),
        .hgc_grph_page                      (hgc_grph_page),
        .de_o                               (de_o),
        .VGA_R                              (VGA_R),
        .VGA_G                              (VGA_G),
        .VGA_B                              (VGA_B),
        .VGA_HSYNC                          (VGA_HSYNC),
        .VGA_VSYNC                          (VGA_VSYNC),
        .VGA_HBlank                         (VGA_HBlank),
        .VGA_VBlank                         (VGA_VBlank),
        .VGA_VBlank_border                  (VGA_VBlank_border),		  
        .scandoubler						(scandoubler),
        .comp_video                         (comp_video),
        .composite_on                       (composite_on),       
        .vga_composite                      (vga_composite),
        .composite_out                      (composite_out),
        .rgb_18b                            (rgb_18b),
        .address                            (address),
	    .latch_address                      (latch_address),
        .internal_data_bus                  (internal_data_bus),
        .data_bus_out                       (internal_data_bus_chipset),
        .data_bus_out_from_chipset          (data_bus_out_from_chipset),
        .interrupt_request                  (interrupt_request),
        .io_read_n                          (io_read_n),
        .io_write_n                         (io_write_n),
        .memory_read_n                      (memory_read_n),
        .memory_write_n                     (memory_write_n),
        .address_enable_n                   (address_enable_n),
        .timer_counter_out                  (timer_counter_out),
        .speaker_out                        (speaker_out),
        .port_a_out                         (port_a_out),
        .port_a_io                          (port_a_io),
        .port_b_in                          (port_b_in),
        .port_b_out                         (port_b_out),
        .port_b_io                          (port_b_io),
        .port_c_in                          (port_c_in),
        .port_c_out                         (port_c_out),
        .port_c_io                          (port_c_io),
        .ps2_clock                          (ps2_clock),
        .ps2_data                           (ps2_data),
        .ps2_mouseclk_in                    (ps2_mouseclk_in),
        .ps2_mousedat_in                    (ps2_mousedat_in),
        .ps2_mouseclk_out                   (ps2_mouseclk_out),
        .ps2_mousedat_out                   (ps2_mousedat_out),
        .joy_opts                           (joy_opts),
        .joy0                               (joy0),
        .joy1                               (joy1),
        .joya0                              (joya0),
        .joya1                              (joya1),
        .ps2_clock_out                      (ps2_clock_out),
        .ps2_data_out                       (ps2_data_out),
        .jtopl2_snd_e                       (jtopl2_snd_e),
        .opl2_io                            (opl2_io),
        .cms_en                             (cms_en),
        .o_cms_l                            (o_cms_l),
        .o_cms_r                            (o_cms_r),
        .tandy_video                        (tandy_video),
        .tandy_snd_e                        (tandy_snd_e),
        .tandy_snd_rdy                      (tandy_snd_rdy),
    //  .tandy_16_gfx                       (tandy_16_gfx),
	// .tandy_color_16                     (tandy_color_16),
        .uart_rx                           (uart_rx),
        .uart_tx                           (uart_tx),
        .uart_cts_n                        (uart_cts_n),
        .uart_dcd_n                        (uart_dcd_n),
        .uart_dsr_n                        (uart_dsr_n),
        .uart_rts_n                        (uart_rts_n),
        .uart_dtr_n                        (uart_dtr_n),
        .ems_enabled                       (ems_enabled),
        .ems_address                       (ems_address),
        .map_ems                           (map_ems),
        .ena_ems                           (ena_ems),
        .ems_b1                            (ems_b1),
        .ems_b2                            (ems_b2),
        .ems_b3                            (ems_b3),
        .ems_b4                            (ems_b4),
        .ide0_addr                          (ide0_addr),
        .ide0_writedata                     (ide0_writedata),
        .ide0_readdata                      (ide0_readdata),
        .ide0_read                          (ide0_read),
        .ide0_write                         (ide0_write),
        .rtc_data                           (rtc_data),
        .xtctl                              (xtctl),
        .pause_core                         (pause_core)
    );

    RAM u_RAM 
    (
        .clock                              (sdram_clock),
        .reset                              (sdram_reset),
        .enable_sdram                       (enable_sdram),
        .initilized_sdram                   (initilized_sdram),
        .address                            (latch_address),
        .internal_data_bus                  (internal_data_bus),
        .data_bus_out                       (internal_data_bus_ram),
        .memory_read_n                      (memory_read_n),
        .memory_write_n                     (memory_write_n),
        .no_command_state                   (no_command_state),
        .memory_access_ready                (memory_access_ready),
        .ram_address_select_n               (ram_address_select_n),
        .sdram_address                      (sdram_address),
        .sdram_cke                          (sdram_cke),
        .sdram_cs                           (sdram_cs),
        .sdram_ras                          (sdram_ras),
        .sdram_cas                          (sdram_cas),
        .sdram_we                           (sdram_we),
        .sdram_ba                           (sdram_ba),
        .sdram_dq_in                        (sdram_dq_in),
        .sdram_dq_out                       (sdram_dq_out),
        .sdram_dq_io                        (sdram_dq_io),
        .sdram_ldqm                         (sdram_ldqm),
        .sdram_udqm                         (sdram_udqm),
        .map_ems                            (map_ems),
        .ems_b1                             (ems_b1),
        .ems_b2                             (ems_b2),
        .ems_b3                             (ems_b3),
        .ems_b4                             (ems_b4),
        .tandy_bios_flag                    (tandy_bios_flag),
        .bios_protect_flag                  (bios_protect_flag),
        .enable_a000h                       (enable_a000h),
        .wait_count_clk_en                  (wait_count_clk_en),
        .ram_read_wait_cycle                (ram_read_wait_cycle),
        .ram_write_wait_cycle               (ram_write_wait_cycle)
    );

    assign  data_bus = internal_data_bus;

    always_comb
    begin
        if (data_bus_out_from_chipset)
        begin
            internal_data_bus_ext = internal_data_bus_chipset;
            data_bus_direction    = 1'b0;
        end
        else if ((~ram_address_select_n) && (~memory_read_n))
        begin
            internal_data_bus_ext = internal_data_bus_ram;
            data_bus_direction    = 1'b0;
        end
        else
        begin
            if (internal_data_bus_direction == 1'b1)
            begin
                internal_data_bus_ext = data_bus_ext;
                data_bus_direction    = 1'b1;
            end
            else
            begin
                internal_data_bus_ext = 0;
                data_bus_direction    = 1'b0;
            end
        end
    end

endmodule

