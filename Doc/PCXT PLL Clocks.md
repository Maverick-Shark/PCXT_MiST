
# PCXT Clocks

##MiSTer
* Cyclone V SE

### pll_system_0002.v
.output_clock_frequency0("28.636363 MHz"),
.phase_shift0("0 ps"),
.duty_cycle0(50),
.output_clock_frequency1("57.272727 MHz"),
.phase_shift1("0 ps"),
.duty_cycle1(50),
.output_clock_frequency2("114.545454 MHz"),
.phase_shift2("0 ps"),
.duty_cycle2(50),
.output_clock_frequency3("9.545454 MHz"),
.phase_shift3("0 ps"),
.duty_cycle3(50),
.output_clock_frequency4("7.159090 MHz"),
.phase_shift4("0 ps"),
.duty_cycle4(50),
.output_clock_frequency5("4.772727 MHz"),

### pll_system.v
.outclk_0 (outclk_0), // outclk0.clk
.outclk_1 (outclk_1), // outclk1.clk
.outclk_2 (outclk_2), // outclk2.clk
.outclk_3 (outclk_3), // outclk3.clk
.outclk_4 (outclk_4), // outclk4.clk
.outclk_5 (outclk_5), // outclk5.clk

### pcxt.sv
// pll_system_inst
.refclk(CLK_50M),
.outclk_0(clk_28_636),
.outclk_1(clk_57_272),
.outclk_2(clk_114_544),
.outclk_3(clk_9_54),
.outclk_4(clk_7_16),
.outclk_5(clk_4_77),
// u_CHIPSET
.clk_vga_cga               (clk_28_636),
.enable_cga                (`ENABLE_CGA),
.clk_vga_hgc               (clk_57_272),
.enable_hgc                (enable_hgc_sel),
.hgc_rgb                   (hgc_rgb_sel),

## MiST (Poseidon)
* Cyclone IV E

### pcxt.sv
.refclk(CLK_50M),
// pll
.outclk_0(clk_100),			//100                   CLOCK_CORE
.outclk_1(clk_chipset),		//50                    CLOCK_CHIP
.outclk_2(clk_uart),		//14.7456 -> 14.7541    CLOCK_UART
// pllvideo
.outclk_0(clk_28_636),		//28.636                CLOCK_VGA_CGA
.outclk_1(clk_56_875),		//56.875 -> 57.272      CLOCK_VGA_MDA
// u_CHIPSET
.clk_vga_cga                (clk_28_636),
.enable_cga                 (1'b1),
.clk_vga_mda                (clk_56_875),
.enable_mda                 (1'b1),
.mda_rgb                    (2'b10), // always B&W - monochrome monitor tint handled down below

### pll.v
altpll_component.clk0_divide_by = 1,
altpll_component.clk0_duty_cycle = 50,
altpll_component.clk0_multiply_by = 2,
altpll_component.clk0_phase_shift = "0",
altpll_component.clk1_divide_by = 1,
altpll_component.clk1_duty_cycle = 50,
altpll_component.clk1_multiply_by = 1,
altpll_component.clk1_phase_shift = "0",
altpll_component.clk2_divide_by = 1,
altpll_component.clk2_duty_cycle = 50,
altpll_component.clk2_multiply_by = 1,
altpll_component.clk2_phase_shift = "-2000",
altpll_component.clk3_divide_by = 15625,
altpll_component.clk3_duty_cycle = 50,
altpll_component.clk3_multiply_by = 4608,
altpll_component.clk3_phase_shift = "0",
altpll_component.clk4_divide_by = 2000,
altpll_component.clk4_duty_cycle = 50,
altpll_component.clk4_multiply_by = 143,
altpll_component.clk4_phase_shift = "0",
altpll_component.compensate_clock = "CLK0",
altpll_component.inclk0_input_frequency = 20000,

### pllvideo.v
altpll_component.clk0_divide_by = 12500,
altpll_component.clk0_duty_cycle = 50,
altpll_component.clk0_multiply_by = 7159,
altpll_component.clk0_phase_shift = "0",
altpll_component.clk1_divide_by = 6250,
altpll_component.clk1_duty_cycle = 50,
altpll_component.clk1_multiply_by = 7159,
altpll_component.clk1_phase_shift = "0",
altpll_component.clk2_divide_by = 15625,
altpll_component.clk2_duty_cycle = 50,
altpll_component.clk2_multiply_by = 576,
altpll_component.clk2_phase_shift = "0",
altpll_component.compensate_clock = "CLK0",
altpll_component.inclk0_input_frequency = 20000,



		