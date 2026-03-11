//
// FE2010A Custom PPI (Programmable Peripheral Interface)
//
// This module replaces the standard Intel 8255A PPI with the Faraday FE2010A
// specific implementation. Unlike the 8255A which is a general-purpose
// programmable I/O device, the FE2010A PPI is hard-wired for the PC/XT
// architecture with the following fixed register assignments:
//
//   Port 0x60 : Keyboard Data Register (read-only)
//   Port 0x61 : Control Register / Port B (read/write)
//   Port 0x62 : Switch Register / Port C (read: multiplexed, write: DIP switch)
//   Port 0x63 : Configuration Register (write-only, forwarded to config module)
//
// KEY DIFFERENCE from standard IBM XT 8255:
//   In the Control Register (0x61), bits 2 and 3 are SWAPPED:
//     - FE2010A bit 2 = Switch Register Select (IBM XT has this at bit 3)
//     - FE2010A bit 3 = Not Used              (IBM XT has Switch Select at bit 2)
//
// The Switch Register (0x62) in the FE2010A can be WRITTEN to set virtual
// DIP switch values, and READ to retrieve them (multiplexed by the switch
// select bit). This replaces physical DIP switches on the motherboard.
//
// References:
//   - Faraday FE2010 datasheet, pages 16-18
//   - Faraday FE2010A documentation by skiselev
//   - Proton PT8010AF documentation by skiselev
//

module fe2010a_ppi (
    input  wire        clock,
    input  wire        reset,

    // ========================================================================
    // Bus interface
    // ========================================================================
    input  wire        chip_select_n,     // Active-low, from I/O decode (0x60-0x7F)
    input  wire        read_enable_n,     // I/O read strobe (active-low)
    input  wire        write_enable_n,    // I/O write strobe (active-low)
    input  wire [1:0]  address,           // A[1:0]: 00=kbd, 01=ctrl, 10=switch, 11=config
    input  wire [7:0]  data_bus_in,       // Data bus input (from CPU/DMA)
    output reg  [7:0]  data_bus_out,      // Data bus output (to internal data bus)

    // ========================================================================
    // Keyboard interface
    // ========================================================================
    input  wire [7:0]  keyboard_data,     // Scan code from PS/2 keyboard converter
    input  wire        keyboard_irq_in,   // Raw IRQ from keyboard converter
    output wire        keyboard_irq_out,  // Processed IRQ1 (cleared by ctrl reg bit 7)

    // ========================================================================
    // Timer 2 interface
    // ========================================================================
    output wire        timer2_gate,       // Control Register bit 0: gates PIT Ch2
    output wire        speaker_enable,    // Control Register bit 1: enables speaker
    input  wire        timer2_output,     // PIT Channel 2 output (for switch reg read)

    // ========================================================================
    // Switch select output
    // ========================================================================
    output wire        switch_select,     // Control Register bit 2 (swapped from std XT!)

    // ========================================================================
    // Parity / I/O check control
    // ========================================================================
    output wire        disable_parity,    // Control Register bit 4
    output wire        disable_io_check,  // Control Register bit 5

    // ========================================================================
    // Switch register external inputs
    // ========================================================================
    input  wire [1:0]  vid_in,            // VID0, VID1 from display type pins
    input  wire        io_channel_check,  // I/O CH CHK from expansion bus
    input  wire        ram_parity_check,  // RAM parity error
    input  wire [7:0]  sw_default,        // Default DIP switch value (from OSD config)

    // ========================================================================
    // Configuration register interface (address == 2'b11 = port 0x63)
    // ========================================================================
    output wire        config_write,      // Pulse: write strobe to config register
    output wire [7:0]  config_data,       // Data being written to config register

    // ========================================================================
    // Configuration lock input
    // ========================================================================
    input  wire        config_locked      // When 1, switch register write is frozen
);

    // ========================================================================
    // Keyboard Data Register (Port 0x60) — Read Only
    // ========================================================================
    //
    // This register holds the most recent scan code from the keyboard.
    // When a key event occurs, keyboard_irq_in pulses and the scan code
    // is latched. The register is cleared by pulsing bit 7 of the Control
    // Register (write 1 then 0).
    //
    // In the original FE2010A, interrupt 1 (IRQ1) is generated when a
    // new scan code is available.
    //

    reg [7:0] keyboard_data_reg;
    reg       keyboard_irq_ff1;
    reg       keyboard_irq_ff2;
    reg       keyboard_irq_latched;

    // Latch keyboard data with double-FF synchronization for the IRQ
    always @(posedge clock or posedge reset) begin
        if (reset) begin
            keyboard_data_reg   <= 8'h00;
            keyboard_irq_ff1    <= 1'b0;
            keyboard_irq_ff2    <= 1'b0;
            keyboard_irq_latched <= 1'b0;
        end else begin
            // Synchronize IRQ
            keyboard_irq_ff1 <= keyboard_irq_in;
            keyboard_irq_ff2 <= keyboard_irq_ff1;

            // Latch keyboard data when new scan code arrives
            if (keyboard_irq_ff1 & ~keyboard_irq_ff2)
                keyboard_data_reg <= keyboard_data;

            // IRQ management: set on new keycode, cleared by control reg bit 7
            if (control_reg[7])
                keyboard_irq_latched <= 1'b0;
            else if (keyboard_irq_ff1 & ~keyboard_irq_ff2)
                keyboard_irq_latched <= 1'b1;
        end
    end

    assign keyboard_irq_out = keyboard_irq_latched;


    // ========================================================================
    // Control Register (Port 0x61) — Read/Write — "Port B"
    // ========================================================================
    //
    // Emulates the 8255 PPI Port B behavior for the XT architecture, but with
    // FE2010A-specific bit assignments:
    //
    //   Bit 0 : Timer 2 Gate (gates PIT Channel 2 for speaker)
    //   Bit 1 : Enable Speaker (AND with Timer 2 output)
    //   Bit 2 : Switch Select   *** SWAPPED vs. standard IBM XT ***
    //   Bit 3 : Not Used        *** SWAPPED vs. standard IBM XT ***
    //   Bit 4 : Disable Parity Check
    //   Bit 5 : Disable I/O Check
    //   Bit 6 : Enable Keyboard Clock
    //   Bit 7 : Clear Keyboard Data Register (pulse high then low)
    //
    // In the standard IBM XT 8255:
    //   Bit 2 : Not Used
    //   Bit 3 : Switch Select
    //
    // This swap is documented in the FE2010A markdown:
    //   "Bits 2 and 3 are swapped when compared to the standard IBM PC architecture"
    //

    reg [7:0] control_reg;

    always @(posedge clock or posedge reset) begin
        if (reset)
            control_reg <= 8'h00;
        else if (~chip_select_n & ~write_enable_n & (address == 2'b01))
            control_reg <= data_bus_in;
    end

    // Output assignments from control register
    assign timer2_gate      = control_reg[0];
    assign speaker_enable   = control_reg[1];
    assign switch_select    = control_reg[2];  // FE2010A: bit 2 is switch select (swapped!)
    // control_reg[3] is not used in FE2010A
    assign disable_parity   = control_reg[4];
    assign disable_io_check = control_reg[5];
    // control_reg[6] = Enable Keyboard Clock (directly used by keyboard interface)
    // control_reg[7] = Clear Keyboard Data Register (used in keyboard logic above)


    // ========================================================================
    // Switch Register (Port 0x62) — Read/Write — "Port C"
    // ========================================================================
    //
    // WRITE MODE:
    //   Sets the virtual DIP switch values that replace physical switches:
    //     Bit 0   : Not Used (SW1 value)
    //     Bit 1   : 8087 Installed (SW2 value)
    //     Bits 2-3: On Board System Memory Size (SW3-SW4 values)
    //     Bits 4-5: Not Used (SW5-SW6 are from VID0/VID1 pins)
    //     Bits 6-7: Number of Floppies (SW7-SW8 values)
    //
    // READ MODE:
    //   The switch values (bits 0-3) depend on the Switch Select bit
    //   (Control Register bit 2) setting:
    //
    //   When Switch Select = 0 (upper nibble of virtual DIP switch):
    //     Bit 0   : VID0 pin (SW5)
    //     Bit 1   : VID1 pin (SW6)
    //     Bits 2-3: Number of Floppies from written bits 6-7 (SW7-SW8)
    //     Bit 4   : Timer 2 Output
    //     Bit 5   : Timer 2 Output
    //     Bit 6   : I/O Channel Check
    //     Bit 7   : RAM Parity Check
    //
    //   When Switch Select = 1 (lower nibble of virtual DIP switch):
    //     Bit 0   : Written bit 0 (SW1)
    //     Bit 1   : 8087 Installed from written bit 1 (SW2)
    //     Bits 2-3: Memory Size from written bits 2-3 (SW3-SW4)
    //     Bit 4   : Timer 2 Output
    //     Bit 5   : Timer 2 Output
    //     Bit 6   : I/O Channel Check
    //     Bit 7   : RAM Parity Check
    //

    reg [7:0] switch_reg;

    always @(posedge clock or posedge reset) begin
        if (reset)
            switch_reg <= sw_default;  // Initialize from OSD DIP switch config
        else if (~chip_select_n & ~write_enable_n & (address == 2'b10) & ~config_locked)
            switch_reg <= data_bus_in;
    end

    // Switch register read multiplexer
    reg [7:0] switch_read_data;

    always @(*) begin
        // Bits 4-7 are always the same regardless of switch_select
        switch_read_data[4] = timer2_output;
        switch_read_data[5] = timer2_output;
        switch_read_data[6] = io_channel_check;
        switch_read_data[7] = ram_parity_check;

        // Bits 0-3 depend on switch_select (Control Register bit 2)
        if (~switch_select) begin
            // Switch Select = 0: show upper nibble of DIP switch
            // Bits 0-1: VID0, VID1 (from pins, mapped as SW5, SW6)
            switch_read_data[0] = vid_in[0];
            switch_read_data[1] = vid_in[1];
            // Bits 2-3: Number of floppies (from written bits 6-7)
            switch_read_data[2] = switch_reg[6];
            switch_read_data[3] = switch_reg[7];
        end else begin
            // Switch Select = 1: show lower nibble of DIP switch
            // Bits 0-3: SW1-SW4 (from written bits 0-3)
            switch_read_data[0] = switch_reg[0];
            switch_read_data[1] = switch_reg[1];
            switch_read_data[2] = switch_reg[2];
            switch_read_data[3] = switch_reg[3];
        end
    end


    // ========================================================================
    // Configuration Register Write Interface (Port 0x63)
    // ========================================================================
    //
    // Port 0x63 is a write-only register handled externally by the
    // FE2010A config module. We just detect the write and forward the data.
    //

    assign config_write = ~chip_select_n & ~write_enable_n & (address == 2'b11);
    assign config_data  = data_bus_in;


    // ========================================================================
    // Data Bus Output Multiplexer
    // ========================================================================
    //
    // Read operations based on address[1:0]:
    //   00 (0x60): Keyboard Data Register
    //   01 (0x61): Control Register (returns last written value)
    //   10 (0x62): Switch Register (multiplexed read)
    //   11 (0x63): Configuration Register is write-only, reads undefined
    //

    always @(*) begin
        case (address)
            2'b00:   data_bus_out = keyboard_data_reg;   // Port 0x60: Keyboard
            2'b01:   data_bus_out = control_reg;         // Port 0x61: Control (R/W)
            2'b10:   data_bus_out = switch_read_data;    // Port 0x62: Switch (muxed)
            2'b11:   data_bus_out = 8'hFF;               // Port 0x63: Write-only
            default: data_bus_out = 8'hFF;
        endcase
    end

endmodule
