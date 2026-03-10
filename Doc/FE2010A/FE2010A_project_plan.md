# Faraday FE2010A Chipset — FPGA Implementation Plan for PCXT MiST Core

## 1. Project Overview

### Objective
Implement a Verilog module (`FE2010A.v`) that recreates the Faraday FE2010A PC Bus CPU & Peripheral Controller for the PCXT MiST FPGA core. The FE2010A integrates the functionality of five Intel peripheral controllers plus glue logic onto a single chip, and is the chipset used in many late-80s XT-compatible motherboards (including systems using the pin-compatible Proton PT8010AF clone).

### Scope
The new `FE2010A.v` module will wrap the existing KFPC-XT SystemVerilog sub-modules (KF8259, KF8253, KF8237, KF8288) and replace the current KF8255 with a custom FE2010A-specific PPI implementation. It will add all FE2010A-specific registers and behavior on top, providing a single chipset module that can be instantiated from `Chipset.sv`.

### Target Repository
- **Repo:** `https://github.com/Maverick-Shark/PCXT_MiST`
- **Branch:** `claude/improve-pcxt-mist-core-KFuwL`
- **Reference sources (read-only):** `https://github.com/Maverick-Shark/PCXT_MiSTer/tree/main/rtl/KFPC-XT/HDL`

---

## 2. Architecture Analysis

### 2.1 Current PCXT MiST Architecture

The existing code has a three-layer structure:

```
PCXT.sv (top-level)
  └── Chipset.sv (chipset + RAM wrapper)
        ├── Bus_Arbiter.sv
        │     ├── KF8288  (Bus Controller)
        │     ├── KF8237  (DMA Controller)
        │     └── DMA Page Registers (74xx670)
        ├── Peripherals.sv
        │     ├── KF8259  (Interrupt Controller / PIC)
        │     ├── KF8253  (Timer / PIT)
        │     ├── KF8255  (PPI — standard 8255)
        │     ├── KFPS2KB (PS/2 Keyboard)
        │     ├── Video   (CGA / MDA / Tandy)
        │     ├── Audio   (OPL2 / CMS / Tandy)
        │     ├── UART    (COM1/COM2)
        │     ├── IDE     (XT2IDE)
        │     ├── EMS     (Expanded Memory)
        │     ├── RTC, Joysticks, LPT, etc.
        │     └── I/O address decode + data bus mux
        ├── Ready.sv (wait state / ready signal — partial 8284 replacement)
        └── RAM.sv (SDRAM controller)
```

### 2.2 Target FE2010A Architecture

The FE2010A replaces the following Intel chips:

| Intel IC | Function | Current Module | FE2010A Role |
|----------|----------|---------------|--------------|
| 8284A | Clock Generator | `Ready.sv` (partial) | Clock selection (4.77/7.15/9.54 MHz), ready signal |
| 8288 | Bus Controller | `KF8288` in `Bus_Arbiter.sv` | CPU bus control, command generation |
| 8259A | Interrupt Controller (PIC) | `KF8259` in `Peripherals.sv` | Interrupt handling, IRQ0-IRQ7 |
| 8237A | DMA Controller | `KF8237` in `Bus_Arbiter.sv` | 4-channel DMA, refresh via Ch0 |
| 8253 | Timer (PIT) | `KF8253` in `Peripherals.sv` | 3-channel timer, speaker, refresh timing |
| 8255A | PPI | `KF8255` in `Peripherals.sv` | **Custom implementation** (see below) |

Plus FE2010A-specific additions not present in the discrete chip design:

- Configuration Register at port `0x63` (turbo mode, wait states, RAM size, freeze)
- Modified PPI with swapped Control Register bits 2/3
- Switch Register with write mode and multiplexed read mode
- NMI Mask Register at port `0xA0`
- DMA Page Registers at `0x81-0x83` (integrated, not separate 74xx670)
- XT-compatible I/O decode (only lower 10 address bits used)
- DRAM refresh control via PIT Channel 1 / DMA Channel 0 coupling
- FE2010A-specific wait state table based on clock speed and configuration

### 2.3 Proposed New Architecture

```
PCXT.sv (top-level)
  └── Chipset.sv (modified — instantiates FE2010A instead of Bus_Arbiter)
        ├── FE2010A.v  ←── NEW MODULE
        │     ├── KF8288  (Bus Controller — reused)
        │     ├── KF8237  (DMA Controller — reused)
        │     ├── KF8259  (PIC — reused)
        │     ├── KF8253  (PIT — reused)
        │     ├── fe2010a_ppi.v      ←── NEW: Custom PPI (replaces KF8255)
        │     ├── fe2010a_config.v   ←── NEW: Configuration Register (0x63)
        │     ├── fe2010a_clkgen.v   ←── NEW: Clock generator / selector
        │     ├── fe2010a_waitgen.v  ←── NEW: Wait state generator
        │     ├── DMA Page Registers (integrated)
        │     ├── NMI Mask Register
        │     └── I/O address decode (XT-compatible)
        ├── Peripherals.sv (modified — PIC/PIT/PPI removed, only keeps video/audio/etc.)
        ├── Ready.sv (may be superseded by fe2010a_waitgen.v)
        └── RAM.sv (SDRAM controller — unchanged)
```

---

## 3. FE2010A Register Map (from datasheet + reverse engineering)

### 3.1 I/O Address Map

| Address Range | Resource | Notes |
|---------------|----------|-------|
| `0x00–0x0F` | 8237-compatible DMA Controller | Directly wraps KF8237 |
| `0x20–0x21` | 8259-compatible PIC | Directly wraps KF8259 |
| `0x40–0x42` | 8253-compatible Timer (Ch0-Ch2) | Directly wraps KF8253 |
| `0x43` | Timer Control Register | Writing with counter 1 selected disables refresh |
| `0x60` | Keyboard Data Register | Read-only; cleared via Control Reg bit 7 |
| `0x61` | Control Register (Port B) | R/W; **bits 2 and 3 are swapped** vs. standard IBM XT |
| `0x62` | Switch Register (Port C) | R/W; write sets DIP switch values, read is multiplexed |
| `0x63` | **Configuration Register** | Write-only; FE2010A-specific turbo/wait/RAM/freeze |
| `0x81–0x83` | DMA Page Registers | Write-only; address bits 16-19 for DMA |
| `0xA0` | NMI Mask Register | Write-only; bit 7 enables NMI |

I/O decoding is XT-compatible: upper 6 address bits (`A[15:10]`) are not used (don't care).

### 3.2 Control Register (`0x61`) — Port B

| Bit | Function | Notes |
|-----|----------|-------|
| 0 | Timer 2 Gate | Gates PIT Channel 2 |
| 1 | Enable Speaker | AND with Timer 2 output for speaker |
| **2** | **Switch Select** | **Swapped with bit 3 vs. standard IBM XT** |
| **3** | **Not Used** | **Swapped with bit 2 vs. standard IBM XT** |
| 4 | Disable Parity Check | |
| 5 | Disable I/O Check | |
| 6 | Enable Keyboard Clock | |
| 7 | Clear Keyboard Data Register | Pulse high then low to clear |

This swap is critical: in the standard IBM XT 8255 PPI, bit 2 is "Not Used" and bit 3 is "Switch Select". The FE2010A reverses these.

### 3.3 Switch Register (`0x62`) — Port C

**Write mode** — sets virtual DIP switch values:

| Bit | Function |
|-----|----------|
| 0 | Not used (SW1) |
| 1 | 8087 Installed (SW2) |
| 2–3 | On Board Memory Size (SW3–SW4) |
| 4–5 | Not used (SW5–SW6 are from VID0/VID1 pins) |
| 6–7 | Number of Floppies (SW7–SW8) |

**Read mode** — multiplexed by Control Register bit 2 (Switch Select):

When Switch Select = 0 (bits 4–7 of DIP switches):

| Bit | Source |
|-----|--------|
| 0–1 | VID0, VID1 pins (SW5, SW6) |
| 2–3 | Number of Floppies from bits 6–7 written (SW7, SW8) |
| 4–5 | Timer 2 Output (both bits) |
| 6 | I/O Channel Check |
| 7 | RAM Parity Check |

When Switch Select = 1 (bits 0–3 of DIP switches):

| Bit | Source |
|-----|--------|
| 0 | SW1 value (written bit 0) |
| 1 | 8087 Installed (written bit 1) |
| 2–3 | Memory Size (written bits 2–3) |
| 4–5 | Timer 2 Output (both bits) |
| 6 | I/O Channel Check |
| 7 | RAM Parity Check |

### 3.4 Configuration Register (`0x63`) — FE2010A Only

Write-only register at port `0x63`:

| Bit | Function | Values |
|-----|----------|--------|
| 0 | Disable Parity Checker | 1 = disabled (must be 1 for SRAM systems) |
| 1 | Enable 8087 NMI | 0 = no 8087, 1 = 8087 present |
| 2 | On Board RAM size (bit 0) | See RAM size table |
| 3 | Lock Register | Writing 1 freezes bits 0–4 and Switch Register until reset |
| 4 | On Board RAM size (bit 1) | See RAM size table |
| 5 | Fast Mode (0 RAM wait states) | 1 = zero on-board memory wait states |
| 6 | 7.15 MHz CPU clock | See clock/wait table |
| 7 | 9.54 MHz CPU clock | See clock/wait table |

**RAM Size (bits 4, 2):**

| Bit 4 | Bit 2 | Banks | Size |
|-------|-------|-------|------|
| 0 | 1 | 1 | 256 KB |
| 1 | 0 | 2 | 512 KB |
| 0 | 0 | 3 | 640 KB |

**Clock and Wait States (bits 7, 6, 5):**

| Bit 7 | Bit 6 | Bit 5 | CPU Speed | I/O WS | Memory Bus WS |
|-------|-------|-------|-----------|--------|---------------|
| 0 | 0 | X | 4.77 MHz | 1 | 0 |
| 0 | 1 | 0 | 7.15 MHz | 4 | 2 |
| 0 | 1 | 1 | 7.15 MHz | 4 | 0 |
| 1 | 0 | 0 | 9.54 MHz | 6 | 4 |
| 1 | 1 | 0 | 9.54 MHz | 4 | 2 |
| 1 | 0 | 1 | 9.54 MHz | 6 | 0 |
| 1 | 1 | 1 | 9.54 MHz | 4 | 0 |

Note: At 9.54 MHz, the CPU clock duty cycle is 50% (instead of 33%), which may cause issues with some 8088 CPUs.

### 3.5 DRAM Refresh

- PIT Channel 1 drives DMA Channel 0 for DRAM refresh
- Refresh is disabled by writing `0x54` to port `0x43` (PIT control reg, selecting counter 1)
- Refresh is enabled by writing to port `0x41` (typically value `0x12` for 15 µs interval)
- Refresh causes ~15% system slowdown due to inserted DMA cycles

### 3.6 Proton PT8010AF Differences

The PT8010AF is a pin-compatible clone with two known behavioral differences:

1. **PIT Channel 1 read values**: PT8010AF returns `0x00–0x0F` range; FE2010A returns `0x10` or `0x05`
2. **IORDY sampling timing**: PT8010AF samples IORDY later, which better handles VGA cards that assert IO_CH_RDY late (observable at 9.54 MHz with zero memory wait states)

For the initial implementation, we target FE2010A behavior and can add a PT8010AF compatibility mode later.

---

## 4. Implementation Plan

### Phase 1: Module Skeleton and I/O Decode

**Files to create:**
- `rtl/KFPC-XT/HDL/FE2010A/FE2010A.v` — top-level chipset module
- `rtl/KFPC-XT/HDL/FE2010A/fe2010a_ppi.v` — custom PPI replacement
- `rtl/KFPC-XT/HDL/FE2010A/fe2010a_config.v` — configuration register
- `rtl/KFPC-XT/HDL/FE2010A/fe2010a_clkgen.v` — clock generation/selection
- `rtl/KFPC-XT/HDL/FE2010A/fe2010a_waitgen.v` — wait state generator

**Tasks:**
1. Create `FE2010A.v` with all port declarations matching the interface currently provided by `Bus_Arbiter.sv` + the chipset-related subset of `Peripherals.sv`
2. Implement XT-compatible I/O address decode (lower 10 bits only, matching the datasheet map)
3. Wire up placeholder instantiations of KF8259, KF8253, KF8237, KF8288
4. Implement DMA page registers (replaces the 74xx670 in `Bus_Arbiter.sv`)
5. Implement NMI Mask Register at `0xA0`

### Phase 2: Custom PPI (`fe2010a_ppi.v`)

This is the most complex new sub-module. The FE2010A does **not** implement a standard 8255 — it provides a fixed-function PPI with the following behavior:

**Tasks:**
1. Implement Keyboard Data Register at `0x60` (read-only, cleared by Control Reg bit 7)
2. Implement Control Register at `0x61` (read/write) with the swapped bits 2/3
3. Implement Switch Register at `0x62` (write: set DIP switch values; read: multiplexed output controlled by Control Reg bit 2)
4. Port `0x63` write decode routing to `fe2010a_config.v`
5. Internal wiring: Timer 2 gate (bit 0), speaker enable (bit 1), keyboard clock enable (bit 6)
6. Timer 2 output connection to Switch Register read bits 4–5
7. I/O Channel Check and RAM Parity Check connections to Switch Register read bits 6–7

**Key difference from current KF8255 usage:** The current code uses the standard KF8255 with ports A/B/C routed externally. The FE2010A PPI is hard-wired internally — port A is always the keyboard data register, port B is always the control register, port C is always the switch register. No mode programming via the 8255 control word is supported.

### Phase 3: Configuration Register (`fe2010a_config.v`)

**Tasks:**
1. Implement write-only register at `0x63`
2. Implement lock mechanism (bit 3): once set, bits 0–4 and the Switch Register become read-only until system reset
3. Output decoded signals: clock select (2 bits), fast mode, RAM size (2 bits), parity enable, 8087 NMI enable
4. Provide initial/reset defaults matching IBM XT standard (4.77 MHz, parity enabled)

### Phase 4: Clock Generator (`fe2010a_clkgen.v`)

**Tasks:**
1. Implement clock selection logic based on Configuration Register bits 7:6
2. Support for XSEL pin (14.31818 MHz vs 28.63636 MHz crystal) — in the MiST context this maps to the PLL configuration
3. Generate the 1.19 MHz timer clock (OSC ÷ 12) and peripheral clock
4. Manage CPU clock duty cycle: 33% at 4.77 MHz, 50% at 9.54 MHz
5. Integrate with existing MiST PLL infrastructure (`rtl/pll.v`)

**Note:** The actual clock switching on MiST is already handled in `PCXT.sv` via `clk_select`. The `fe2010a_clkgen.v` module needs to provide the `clk_select` output based on the Configuration Register, and the upper level handles the actual PLL reconfiguration.

### Phase 5: Wait State Generator (`fe2010a_waitgen.v`)

**Tasks:**
1. Implement the wait state table from the Configuration Register (see section 3.4)
2. Generate I/O wait states: 1 WS at 4.77 MHz, 4 WS at 7.15 MHz, 4–6 WS at 9.54 MHz
3. Generate Memory Bus wait states: 0–4 WS depending on config bits 7:5
4. On-board memory always gets 0 wait states (this is handled by the RAM controller)
5. IORDY input sampling for external device wait states
6. Integration with or replacement of current `Ready.sv` module

### Phase 6: DRAM Refresh Integration

**Tasks:**
1. Wire PIT Channel 1 output to DMA Channel 0 request (DRQ0)
2. Implement refresh enable/disable via PIT Channel 1 control writes
3. DMA Channel 0 is reserved for refresh — NDAK0 indicates refresh cycle
4. Insert refresh cycles at the standard 15 µs interval when enabled

### Phase 7: Integration into Chipset.sv

**Tasks:**
1. Modify `Chipset.sv` to instantiate `FE2010A` instead of `Bus_Arbiter`
2. Modify `Peripherals.sv` to remove KF8259, KF8253, KF8255 instantiations (these move into FE2010A)
3. Define clean interfaces between FE2010A and the remaining peripherals in `Peripherals.sv`
4. Route FE2010A-provided signals (interrupt_to_cpu, timer outputs, speaker, etc.) to `Peripherals.sv`
5. Update `files.qip` to include new FE2010A source files
6. Update SDC constraints if clock topology changes

### Phase 8: Testing and Validation

**Tasks:**
1. Verify boot with pcxt_pcxt31.rom BIOS (standard PCXT)
2. Verify boot with micro8088.rom BIOS (Micro 8088 / Faraday-specific)
3. Test Commodore PC-10-III BIOS (known FE2010A-based system)
4. Test turbo mode switching via Configuration Register
5. Test DRAM refresh enable/disable
6. Test DIP switch configuration (memory size, floppy count, video type)
7. Test keyboard operation (data register, clear, interrupt)
8. Test parity check disable (important for SRAM systems like Micro 8088)
9. Test configuration register freeze (lock bit)
10. Verify wait state behavior at each clock speed

---

## 5. Module Interface Specifications

### 5.1 FE2010A.v Top-Level Ports

```verilog
module FE2010A (
    // System clocks
    input  wire        clock,          // System clock (50 MHz)
    input  wire        cpu_clock,      // CPU clock (from PLL)
    input  wire        peripheral_clock, // 1.19 MHz peripheral clock
    input  wire        reset,          // System reset
    
    // CPU interface
    input  wire [19:0] cpu_address,    // CPU address bus
    input  wire [7:0]  cpu_data_bus,   // CPU data bus (output from CPU)
    input  wire [2:0]  processor_status, // S0, S1, S2
    input  wire        processor_lock_n, // LOCK#
    output wire        processor_transmit_or_receive_n,
    output wire        processor_ready, // READY to CPU
    output wire        interrupt_to_cpu, // INT to CPU
    
    // Bus signals (directly from FE2010A to ISA bus)
    output wire [19:0] address,        // Latched address bus
    input  wire [19:0] address_ext,    // External address (DMA slave)
    output wire        address_direction,
    output wire [7:0]  internal_data_bus, // Internal data bus
    input  wire [7:0]  data_bus_ext,   // External data bus input
    output wire        data_bus_direction,
    output wire        address_latch_enable,
    
    // Bus command signals
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
    
    // DMA interface
    input  wire        ext_access_request,
    input  wire [3:0]  dma_request,     // DRQ1-DRQ3 from ISA bus, DRQ0 internal
    output wire [3:0]  dma_acknowledge_n,
    output wire        address_enable_n,
    output wire        terminal_count_n,
    
    // Interrupt inputs (directly to internal PIC)
    input  wire [7:0]  interrupt_request, // IRQ0=timer, IRQ1=kbd, IRQ2-7 from bus
    
    // I/O channel signals
    input  wire        io_channel_check,
    input  wire        io_channel_ready, // IORDY from expansion bus
    
    // Keyboard interface
    input  wire [7:0]  keyboard_data_in, // Scan code from PS/2 converter
    input  wire        keyboard_irq,     // IRQ from PS/2 converter
    
    // Timer/Speaker outputs
    output wire [2:0]  timer_counter_out, // PIT Ch0, Ch1, Ch2 outputs
    output wire        speaker_out,       // Speaker output (Ch2 & enable)
    
    // Configuration inputs (from pins/OSD)
    input  wire [1:0]  vid_in,           // VID0, VID1 display type inputs
    
    // Configuration outputs (active signals from config register)
    output wire [1:0]  clk_select,       // Clock speed selection to PLL
    output wire        fast_mode,        // Zero memory wait states
    output wire [1:0]  ram_size,         // On-board RAM size config
    output wire        parity_enable,    // Parity checker enable
    output wire        nmi_enable,       // NMI enable (from 0xA0)
    
    // Internal data bus output (for Peripherals.sv data mux)
    output wire [7:0]  chipset_data_out,
    output wire        chipset_data_out_valid,
    
    // NMI output
    output wire        nmi_to_cpu,
    
    // Ready logic interface
    output wire        dma_ready,
    input  wire        dma_wait_n
);
```

### 5.2 fe2010a_ppi.v Ports

```verilog
module fe2010a_ppi (
    input  wire        clock,
    input  wire        reset,
    
    // Bus interface
    input  wire        chip_select_n,    // Directly from I/O decode (0x60-0x63)
    input  wire        read_enable_n,
    input  wire        write_enable_n,
    input  wire [1:0]  address,          // A[1:0] selects port 0x60-0x63
    input  wire [7:0]  data_bus_in,
    output reg  [7:0]  data_bus_out,
    
    // Keyboard
    input  wire [7:0]  keyboard_data,    // Scan code input
    input  wire        keyboard_irq_in,  // Raw IRQ from PS/2 converter
    output wire        keyboard_irq_out, // Processed IRQ (cleared by bit 7)
    
    // Timer 2 interface
    output wire        timer2_gate,      // Control Reg bit 0
    output wire        speaker_enable,   // Control Reg bit 1
    input  wire        timer2_output,    // From PIT Channel 2
    
    // Switch select
    output wire        switch_select,    // Control Reg bit 2 (swapped!)
    
    // Parity / I/O check control
    output wire        disable_parity,   // Control Reg bit 4
    output wire        disable_io_check, // Control Reg bit 5
    
    // Keyboard clock control
    output wire        enable_kbd_clock, // Control Reg bit 6
    output wire        clear_keyboard,   // Control Reg bit 7
    
    // Switch register inputs
    input  wire [1:0]  vid_in,           // VID0, VID1 from pins
    input  wire        io_channel_check, // I/O CH CHK from bus
    input  wire        ram_parity_check, // RAM parity error
    
    // Configuration register interface (address == 2'b11, port 0x63)
    output wire        config_write,     // Pulse: writing to 0x63
    output wire [7:0]  config_data,      // Data being written to 0x63
    
    // Configuration lock input
    input  wire        config_locked     // From config register lock bit
);
```

---

## 6. Key Implementation Details

### 6.1 PPI Bits 2/3 Swap

The FE2010A/FE2010 datasheet (page 17) shows the Control Register at `0x61`:

- **FE2010/FE2010A:** Bit 2 = Switch Register Select, Bit 3 = Not Used
- **Standard IBM XT 8255:** Bit 2 = Not Used, Bit 3 = Switch Register Select

The Faraday FE2010A markdown document confirms: *"Bits 2 and 3 are swapped when compared to the standard IBM PC architecture"*

The current PCXT MiST core uses the standard mapping. The FE2010A PPI must implement the Faraday mapping. BIOSes designed for Faraday chipsets (e.g., Commodore PC-10-III, Micro 8088) expect this swap.

### 6.2 Switch Register Multiplexing

The FE2010 datasheet (page 17) shows the read multiplexing:

- Control Reg bit 2 = 0 → Switch Register Read returns bits 4–7 of the virtual DIP switch on data bits 0–3
- Control Reg bit 2 = 1 → Switch Register Read returns bits 0–3 of the virtual DIP switch on data bits 0–3
- Bits 4–5 always return Timer 2 Output
- Bit 6 always returns I/O Channel Check
- Bit 7 always returns RAM Parity Check

This is how BIOS reads the full 8-bit DIP switch state using only 4 data bits.

### 6.3 Configuration Register Freeze

When bit 3 of the Configuration Register is written as 1:
- Bits 0–4 of the Configuration Register become frozen (writes have no effect)
- The Switch Register (port `0x62`) write mode is also frozen
- Only bits 5–7 (Fast Mode, Clock Speed) remain writable
- The freeze persists until system reset

This is used by BIOS to prevent application software from accidentally changing hardware configuration.

### 6.4 DRAM Refresh Mechanism

The refresh mechanism in the FE2010A works differently from the standard IBM XT:

- **Standard XT:** PIT Channel 1 → DRQ0 → DMA Channel 0 → DACK0 triggers refresh
- **FE2010A:** Same basic mechanism, but with specific enable/disable behavior:
  - Writing `0x54` to port `0x43` (PIT control word selecting counter 1) **disables** refresh
  - A subsequent write to port `0x41` (PIT counter 1 data) **enables** refresh
  - On FE2010A, writing `0x40` to port `0x43` also disables refresh (PT8010AF differs here)

For SRAM-based systems (like Micro 8088), refresh can be disabled to avoid the ~15% performance penalty.

### 6.5 Clock Duty Cycle

At 4.77 MHz and 7.15 MHz, the standard 8088 clock duty cycle is 33% high / 67% low.
At 9.54 MHz on the FE2010A, the duty cycle changes to 50% high / 50% low.

This may cause issues with some 8088 CPU implementations and should be taken into account in the clock generator.

---

## 7. File Inventory

### New Files

| File | Description |
|------|-------------|
| `rtl/KFPC-XT/HDL/FE2010A/FE2010A.v` | Top-level FE2010A chipset module |
| `rtl/KFPC-XT/HDL/FE2010A/fe2010a_ppi.v` | Custom PPI (keyboard, control, switch, config) |
| `rtl/KFPC-XT/HDL/FE2010A/fe2010a_config.v` | Configuration register with lock/freeze |
| `rtl/KFPC-XT/HDL/FE2010A/fe2010a_clkgen.v` | Clock selection logic |
| `rtl/KFPC-XT/HDL/FE2010A/fe2010a_waitgen.v` | Wait state generation per clock/config |

### Modified Files

| File | Changes |
|------|---------|
| `rtl/KFPC-XT/HDL/Chipset.sv` | Instantiate FE2010A; remove Bus_Arbiter instantiation |
| `rtl/KFPC-XT/HDL/Peripherals.sv` | Remove KF8259/KF8253/KF8255 instantiations; receive signals from FE2010A |
| `files.qip` | Add new FE2010A source files |
| `PCXT.sv` | Route FE2010A clock select output to PLL control |

### Unchanged Files (reused as sub-modules)

| File | Usage |
|------|-------|
| `KF8259/HDL/KF8259.sv` (+ sub-modules) | Instantiated inside FE2010A |
| `KF8253/HDL/KF8253.sv` (+ sub-modules) | Instantiated inside FE2010A |
| `KF8237/HDL/KF8237.sv` (+ sub-modules) | Instantiated inside FE2010A |
| `KF8288/HDL/KF8288.sv` (+ sub-modules) | Instantiated inside FE2010A |
| `RAM.sv` | Unchanged |
| `KFPS2KB/` | Unchanged (stays in Peripherals.sv, feeds keyboard_data to FE2010A) |

---

## 8. Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| BIOS incompatibility with PPI bit swap | Boot failure with standard BIOSes | Implement configurable swap (OSD option) |
| Wait state count incorrect | Timing issues, software failures | Cross-reference with PT8010AF measurements |
| Config register lock breaks BIOS init | System hangs after lock | Verify lock semantics against multiple BIOSes |
| Clock duty cycle change at 9.54 MHz | MCL86 core may not handle 50% duty | Test MCL86 with both duty cycles |
| MiST FPGA resource limits | May exceed Cyclone III capacity | Monitor LUT usage; FE2010A is simpler than discrete chips |
| DRAM refresh interaction with SDRAM controller | Refresh DMA cycles may conflict | Ensure SDRAM controller ignores DACK0 refresh cycles properly |

---

## 9. Testing Strategy

### 9.1 BIOS Compatibility Matrix

| BIOS | Chipset Expected | Test Priority |
|------|-----------------|---------------|
| pcxt_pcxt31.rom | Generic XT (standard PPI) | High — baseline |
| micro8088.rom | FE2010A (swapped PPI) | High — primary target |
| IBM 5160 | Standard XT | Medium |
| Commodore PC-10-III | FE2010A | High — real FE2010A system |
| Juko ST | Generic XT | Medium |

### 9.2 Functional Tests

1. **Cold boot** — verify POST, memory count, boot to DOS
2. **Turbo switching** — write to port 0x63, verify speed change
3. **Keyboard** — type characters, verify scan codes and IRQ1
4. **Speaker** — BASIC `BEEP` command, verify audio
5. **DIP switches** — change floppy count, verify BIOS detection
6. **DRAM refresh** — disable for SRAM, verify no performance loss
7. **Config freeze** — set lock bit, verify bits 0–4 are frozen
8. **Parity disable** — required for Micro 8088 SRAM operation
9. **NMI mask** — enable/disable NMI, verify 8087 coprocessor interaction

---

## 10. Dependencies and Prerequisites

1. Access to PCXT_MiST `claude` branch for PR generation
2. Working Quartus compilation environment for MiST (Cyclone III EP3C25E144)
3. Test BIOSes: pcxt_pcxt31.rom, micro8088.rom, Commodore PC-10-III BIOS
4. Understanding of existing `PCXT.sv` clock/PLL infrastructure
5. The KF* SystemVerilog modules must be usable from Verilog (`.v`) wrapper via mixed-language support in Quartus (SystemVerilog is a superset of Verilog, so this should work natively)

---

## 11. Phase Timeline Estimate

| Phase | Description | Complexity | Est. Effort |
|-------|-------------|-----------|-------------|
| 1 | Module skeleton + I/O decode | Low | 1 session |
| 2 | Custom PPI | High | 2 sessions |
| 3 | Configuration register | Medium | 1 session |
| 4 | Clock generator | Medium | 1 session |
| 5 | Wait state generator | High | 1–2 sessions |
| 6 | DRAM refresh integration | Medium | 1 session |
| 7 | Chipset.sv integration | High | 2 sessions |
| 8 | Testing and validation | High | 2–3 sessions |

**Total estimated effort: 11–13 working sessions**

---

## 12. References

1. **Faraday FE2010 Datasheet** — `Faraday-XT_Controller-FE2010.pdf` (original FE2010, 23 pages)
2. **Faraday FE2010 Description** — `fe2010-description.pdf` (cleaner scan of same datasheet)
3. **Faraday FE2010A Reverse-Engineered Documentation** — `Faraday-XT_Controller-FE2010A.md` (by skiselev)
4. **Proton PT8010AF Documentation** — `Proton_PT8010AF.md` (by skiselev, clone differences)
5. **KFPC-XT Source** — `https://github.com/kitune-san/KFPC-XT` (original SystemVerilog implementation)
6. **PCXT MiSTer** — `https://github.com/Maverick-Shark/PCXT_MiSTer` (MiSTer port reference)
7. **PCXT MiST** — `https://github.com/Maverick-Shark/PCXT_MiST` (target platform)
8. **Micro 8088 Project** — `https://github.com/skiselev/micro_8088` (FE2010A-based system, testing reference)
