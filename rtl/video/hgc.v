// Graphics Gremlin
//
// Copyright (c) 2021 Eric Schlaepfer
// This work is licensed under the Creative Commons Attribution-ShareAlike 4.0
// International License. To view a copy of this license, visit
// http://creativecommons.org/licenses/by-sa/4.0/ or send a letter to Creative
// Commons, PO Box 1866, Mountain View, CA 94042, USA.
//
`default_nettype none
module hgc(
    // Clocks
    input clk,

    // ISA bus
    input[14:0] bus_a,
    input bus_ior_l,
    input bus_iow_l,
    input bus_memr_l,
    input bus_memw_l,
    input[7:0] bus_d,
    output[7:0] bus_out,
    output bus_dir,
    input bus_aen,
    output bus_rdy,

    // RAM
    output ram_we_l,
    output[18:0] ram_a,
    input[7:0] ram_d,

    // Video outputs
    output hsync,
    output hblank,
    output vsync,
    output vblank,
    output de_o,
    output video,
    output intensity,
    output grph_mode,
    output grph_page,
    output std_hsyncwidth,
    output vblank_border,
    input hercules_hw,

    // Scandoubled (decimated) video outputs for VGA
    output dbl_hsync,
    output dbl_hblank,
    output dbl_video,
    output dbl_intensity
    );

    parameter HGC_70HZ = 1;
    parameter BLINK_MAX = 0;
    localparam STD_HSYNCWIDTH = 4'd15;

    parameter IO_BASE_ADDR = 16'h3b0; // HGC is 3B0, CGA is 3D0
    wire crtc_cs;
    wire status_cs;
    wire control_cs;
    wire bus_mem_cs;
    wire config_sw_cs;

    reg[7:0] bus_int_out;
    wire[7:0] bus_out_crtc;
    wire[7:0] bus_out_mem;
    wire[7:0] hgc_status_reg;
    reg[7:0] hgc_control_reg = 8'b0010_1000;
    reg[1:0] config_sw_reg = 2'b00;
    wire video_enabled;
    wire blink_enabled;

    wire hsync_int;
    wire hblank_crtc;
    wire vblank_crtc;
    wire vsync_l;
    wire vsync_sd_l;
    wire vblank_sd;
    wire cursor;
//    wire video;
    wire display_enable;
    wire display_enable_sd;
//    wire intensity;

    wire[13:0] crtc_addr;
    wire[4:0] row_addr;

    wire charrom_read;
    wire disp_pipeline;
    wire isa_op_enable;
    wire vram_read_char;
    wire vram_read_att;
    wire vram_read;
    wire vram_read_a0;
    wire[4:0] clkdiv;
    wire crtc_clk;
    wire[7:0] ram_1_d;
    wire[3:0] hsync_width_crtc;
    wire[1:0] dbl_video_int;

    // Half-rate clock enable for pixel decimation (57 MHz -> 28.6 MHz)
    reg ce_half = 1'b0;
    always @(posedge clk) ce_half <= ~ce_half;

    reg[23:0] blink_counter;
    reg blink;

    reg bus_memw_synced_l;
    reg bus_memr_synced_l;
    reg bus_ior_synced_l;
    reg bus_iow_synced_l;

    //wire cpu_memsel;
    //reg[1:0] wait_state = 2'd0;
    //reg bus_rdy_latch;

	 assign de_o = display_enable_sd;
	 assign hblank = ~display_enable_sd;

	 assign ram_a = grph_mode ? {4'b0000, row_addr[1:0], crtc_addr[11:0], vram_read_a0} :
                               {7'b0000000, crtc_addr[10:0], vram_read_a0};

	 assign ram_1_d = ram_d;
	 //assign ram_1_d = 8'hFF;
	 assign ram_we_l = vram_read;


    // Synchronize ISA bus control lines to our clock
    always @ (posedge clk)
    begin
        //bus_memw_synced_l <= bus_memw_l;
        //bus_memr_synced_l <= bus_memr_l;
        bus_ior_synced_l <= bus_ior_l;
        bus_iow_synced_l <= bus_iow_l;
    end

    // VSYNC and VBLANK from scandoubler (latched versions of CRTC signals)
    assign vsync = ~vsync_sd_l;
    assign vblank = vblank_sd;

    // Mapped IO
    assign crtc_cs = (bus_a[14:3] == IO_BASE_ADDR[14:3]) & ~bus_aen & hercules_hw; // 3B4/3B5
    assign status_cs = (bus_a == IO_BASE_ADDR + 20'hA) & ~bus_aen & hercules_hw;
    assign control_cs = (bus_a == IO_BASE_ADDR + 16'h8) & ~bus_aen & hercules_hw;
    assign config_sw_cs = (bus_a == IO_BASE_ADDR + 16'hF) & ~bus_aen & hercules_hw;

    // Memory-mapped from B0000 to B7FFF
    // assign bus_mem_cs = (bus_a[19:15] == 5'b10110);

    // Mux ISA bus data from every possible internal source.
    always @ (*)
    begin
//        if (bus_mem_cs & ~bus_memr_l) begin
//            bus_int_out <= bus_out_mem;
        if (status_cs & ~bus_ior_l) begin
            bus_int_out <= hgc_status_reg;
        end else if (crtc_cs & ~bus_ior_l & (bus_a[0] == 1)) begin
            bus_int_out <= bus_out_crtc;
        end else begin
            bus_int_out <= 8'h00;
        end
    end

    // Only for read operations does bus_dir go high.
    assign bus_dir = (crtc_cs | status_cs) & ~bus_ior_l;
    //                | (bus_mem_cs & ~bus_memr_l);
	 //assign bus_dir = (crtc_cs | status_cs);
    assign bus_out = bus_int_out;


    // Hercules status register (read only at 3BA)
    assign hgc_status_reg = {vsync_l, 3'b111, video, 2'b00, hsync_int};

    // Hercules mode control register (write only)
    assign grph_page = hgc_control_reg[7];
    assign blink_enabled = hgc_control_reg[5];
    assign video_enabled = hgc_control_reg[3];
    assign grph_mode = hgc_control_reg[1];

    // Standard sync width detection
    assign std_hsyncwidth = (hsync_width_crtc == STD_HSYNCWIDTH);
    assign vblank_border = vblank;

    // Hsync only present when video is enabled
    assign hsync = video_enabled & hsync_int;

    // Update control register
    always @ (posedge clk)
    begin
        if (control_cs & ~bus_iow_synced_l) begin
            hgc_control_reg <= {(bus_d[7] & config_sw_reg[1]), bus_d[6:2], (bus_d[1] & config_sw_reg[0]), bus_d[0]};
        end
        if (config_sw_cs & ~bus_iow_synced_l) begin
            config_sw_reg <= bus_d[1:0];
        end
    end

    UM6845R crtc (
        .CLOCK(clk),
		  .CLKEN(crtc_clk),
		  // .nCLKEN(),
		  .nRESET(1'b1),
		  .CRTC_TYPE(1'b1),

		  .ENABLE(1'b1),
		  .nCS(~crtc_cs),
		  .R_nW(bus_iow_synced_l),
		  .RS(bus_a[0]),
		  .DI(bus_d),
		  .DO(bus_out_crtc),

		  .hblank(hblank_crtc),
		  .vblank(vblank_crtc),

		  .VSYNC(vsync_l),
		  .HSYNC(hsync_int),
		  .DE(display_enable),
		  // .FIELD(),
		  .CURSOR(cursor),

		  .MA(crtc_addr),
		  .RA(row_addr),
		  .hsync_width(hsync_width_crtc)

	 );

//    if (HGC_70HZ) begin
        defparam crtc.LOCK = 1;
        defparam crtc.H_TOTAL = 8'd99;
        defparam crtc.H_DISP = 8'd80;
        defparam crtc.H_SYNCPOS = 8'd84;       // centered: FP=36px, BP=34px (was 82: FP=18, BP=52)
        defparam crtc.H_SYNCWIDTH = 4'd12;
        defparam crtc.V_TOTAL = 7'd36;          // 37 rows × 14 lines + 7 adj = 525 total
        defparam crtc.V_TOTALADJ = 5'd7;
        defparam crtc.V_DISP = 7'd25;
        defparam crtc.V_SYNCPOS = 7'd31;        // centered: VFP=84, VBP=89 (was 28: VFP=42, VBP=117)
        defparam crtc.V_SYNCWIDTH = 4'd2;       // 2-line vsync (standard VGA, was 16 lines)
        defparam crtc.V_MAXSCAN = 5'd13;
        defparam crtc.C_START = 7'd11;
        defparam crtc.C_END = 5'd12;
//    end else begin
	 /*
        defparam crtc.H_TOTAL = 8'd97;
        defparam crtc.H_DISP = 8'd80;
        defparam crtc.H_SYNCPOS = 8'd82;
        defparam crtc.H_SYNCWIDTH = 4'd15;
        defparam crtc.V_TOTAL = 7'd25;
        defparam crtc.V_TOTALADJ = 5'd6;
        defparam crtc.V_DISP = 7'd25;
        defparam crtc.V_SYNCPOS = 7'd25;
        defparam crtc.V_MAXSCAN = 5'd13;
        defparam crtc.C_START = 7'd11;
        defparam crtc.C_END = 5'd12;
    //end

    // Interface to video SRAM chip
    hgc_vram video_buffer (
        .clk(clk),
        .isa_addr({3'b000, bus_a[15:0]}),
        .isa_din(bus_d),
        .isa_dout(bus_out_mem),
        .isa_read(bus_mem_cs & ~bus_memr_synced_l),
        .isa_write(bus_mem_cs & ~bus_memw_synced_l),
        .pixel_addr({7'h00, crtc_addr[10:0], vram_read_a0}),
        .pixel_data(ram_1_d),
        .pixel_read(vram_read),
        .ram_a(ram_a),
        .ram_d(ram_d),
        .ram_we_l(ram_we_l),
        .isa_op_enable(isa_op_enable)
    );

    defparam video_buffer.HGC_70HZ = HGC_70HZ;
*/
    // Sequencer state machine
    hgc_sequencer sequencer (
        .clk(clk),
        .clk_seq(clkdiv),
        .vram_read(vram_read),
        .vram_read_a0(vram_read_a0),
        .vram_read_char(vram_read_char),
        .vram_read_att(vram_read_att),
        .crtc_clk(crtc_clk),
        .charrom_read(charrom_read),
        .disp_pipeline(disp_pipeline),
        .isa_op_enable(isa_op_enable),
        .grph_mode(grph_mode)
    );

    defparam sequencer.HGC_70HZ = HGC_70HZ;

    // Pixel pusher
    hgc_pixel pixel (
        .clk(clk),
        .clk_seq(clkdiv),
        .vram_data(ram_1_d),
        .vram_read_char(vram_read_char),
        .vram_read_att(vram_read_att),
        .disp_pipeline(disp_pipeline),
        .charrom_read(charrom_read),
        .display_enable(display_enable),
        .cursor(cursor),
        .row_addr(row_addr),
        .blink_enabled(blink_enabled),
        .blink(blink),
        .video_enabled(video_enabled),
        .video(video),
        .intensity(intensity),
        .grph_mode(grph_mode)
    );

    // Generate blink signal for cursor and character
    always @ (posedge clk)
    begin
        if (blink_counter == BLINK_MAX) begin
            blink_counter <= 0;
            blink <= ~blink;
        end else begin
            blink_counter <= blink_counter + 1;
        end
    end

    // Pixel decimator using generic video_scandoubler:
    // ce_pix = ce_2x = half-rate toggle gives 1:1 decimation (1800 -> 900 pixels)
    // Dynamic HSYNC positioning ensures correct h-center from CRTC H_SYNCPOS
    video_scandoubler #(
        .PIXEL_WIDTH(2),
        .H_TOTAL_MAX(1024)
    ) scandoubler_inst (
        .clk(clk),
        .ce_pix(ce_half),
        .ce_2x(ce_half),
        .scandouble_en(1'b1),
        .pixel_in({intensity, video}),
        .hsync_in(hsync_int),
        .vsync_in(vsync_l),
        .vblank_in(vblank_crtc),
        .display_enable_in(display_enable),
        .pixel_out(dbl_video_int),
        .hsync_out(dbl_hsync),
        .vsync_out(vsync_sd_l),
        .vblank_out(vblank_sd),
        .display_enable_out(display_enable_sd)
    );

    assign dbl_video = dbl_video_int[0];
    assign dbl_intensity = dbl_video_int[1];
    assign dbl_hblank = ~display_enable_sd;

endmodule
