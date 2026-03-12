# Appendix L — PC10/PC20 Video Modes

## Resumen de Vídeo Integrado

### VIDEO

| Adaptador | Modos disponibles | Integrado |
|---|---|---|
| **CGA** | 80 column color alpha/numeric | Built in |
| | 40 column color alpha/numeric | |
| | 640×200 black and white graphics | |
| | 320×200 4 color graphics | |
| **MDA** | 80 column monochrome alpha/numeric | Built in |
| **Hercules** | 720×348 monochrome graphics | Built in |
| **Plantronics Color Plus** | 640×200 4 color graphics | Built in |
| | 320×200 16 color graphics | |

### COMPATIBLE MONITORS

- TTL monochrome
- RGBI
- Composite NTSC color
- Composite NTSC/PAL monochrome

---



> **NOTE:** See Appendix E for information on setting the configuration dip switches to select video modes.

---

## Video Mode Characteristics

### CGA (Color Graphics Adapter)

| Resolution | Colors |
|---|---|
| 80 column alpha (8×8 cell) | 16 of 16 colors |
| 40 column alpha (8×8 cell) | 16 of 16 colors |
| 320×200 graphics | 4 colors |
| 640×200 graphics | black & white |

- **Monitor type:** 9Pin Video—RGBI (CGA or MultiSync Monitor); Composite Connector—NTSC color (40 columns); Composite Connector—NTSC mono (80 columns)
- **Vert. Update:** 60 Hz
- **Horz. Update:** 15.7 KHz
- **Max. Dot Clock:** 14.318 MHz

---

### PLANTRONICS

| Resolution | Colors |
|---|---|
| 320×200 graphics | 16 of 16 colors |
| 640×200 graphics | 4 of 16 colors |

- **Monitor type:** same as CGA
- **Vert. Update:** same as CGA
- **Horz. Update:** same as CGA
- **Max. Dot Clock:** 14.318 MHz

---

### MDA (Monochrome Display Adapter)

| Resolution | Colors |
|---|---|
| 80 column alpha (9×14 cell) | monochrome |

- **Monitor type:** 9Pin Video/TTL Monochrome; Composite Connector—monochrome PAL monitor
- **Vert. Update:** 50 Hz
- **Horz. Update:** 18.432 KHz
- **Max. Dot Clock:** 16.257 MHz

---

### HERCULES

| Resolution | Colors |
|---|---|
| 720×348 graphics | monochrome |

- **Monitor type:** same as MDA
- **Vert. Update:** same as MDA
- **Horz. Update:** same as MDA
- **Max. Dot Clock:** 16.257 MHz

---

### ALPHA132

| Resolution | Colors |
|---|---|
| 132×43 alpha (8×8 cell) | monochrome |

- **Monitor type:** 9Pin Video/TTL monochrome monitor
- **Vert. Update:** 48.7 Hz
- **Horz. Update:** 18.52 KHz
- **Max. Dot Clock:** 24.000 MHz

---

## Video Specifics for the Programmer

### IBM CGA and MDA Modes

The standard IBM compatible Video modes are:

**Color Graphics Adapter (CGA):**

| Mode | Type |
|---|---|
| 40×25 | color alpha |
| 80×25 | color alpha |
| 320×200 | color graphics |
| 640×200 | b&w graphics |

**Monochrome Display Adapter (MDA):**

| Mode | Type |
|---|---|
| 80×25 | mono alpha |

Specific details concerning hardware registers and memory organization for the IBM compatible adapters are available in the PC Technical Reference as well as adapter specific Technical Reference guides which can be obtained from IBM. Because this information is readily available from many sources, this appendix focuses on the information which is less readily obtained.

---

## Hercules Graphics Mode

This mode is essentially a bitmapped version of the MDA. The video dot clock (16.257 MHz) and the screen resolution (720×348 pels) are identical. The memory requirement to hold one full display is just less than 32 Kbytes; therefore, two display pages are available.

| Page | Address Range |
|---|---|
| Page 0 | `b000:0000h` to `b000:7fffh` |
| Page 1 | `b000:8000h` to `b000:ffffh` |

> **NOTE:** Page 1 occupies address space used by CGA video memory. **DO NOT** switch to this page if an EXPANSION CGA adapter is installed. Hardware damage to the EXPANSION card and/or the PC10/PC20 motherboard may result!

### Hercules Enable Register — I/O addr 3BFh

| Bit | Value | Description |
|---|---|---|
| bit0 | 0 | disable setting graphics mode |
| bit0 | 1 | enable setting graphics mode |
| bit1 | 0 | disable changing graphics pages |
| bit1 | 1 | enable changing graphics pages |

### Mode Register — I/O addr 3B8h

| Bit | Value | Description |
|---|---|---|
| bit1 | 0 | disable Hercules mode (default MDA) |
| bit1 | 1 | enable Hercules graphics |
| bit3 | 0 | video disable |
| bit3 | 1 | video enable |
| bit5 | 0 | blink disable |
| bit5 | 1 | blink enable |
| bit7 | 0 | Hercules Page0 |
| bit7 | 1 | Hercules Page1 |

### Hercules 6845 CRTC Parameters

| Register | Value |
|---|---|
| #0 | 36h |
| #1 | 2Dh |
| #2 | 2Fh |
| #3 | 07h |
| #4 | 5Bh |
| #5 | 00h |
| #6 | 57h |
| #7 | 53h |
| #8 | 02h |
| #9 | 03h |
| #A | 00h |
| #B | 00h |
| #C | 00h |
| #D | 00h |

### Pixel Addressing

Locating specific pixels within the bitmap may be performed with the following equation:

```
byte offset = (8192 * (Y mod 4)) + (90 * INT(Y mod 4)) + INT(X/8)
bit position = 7 − (X mod 8)
```

Where:
- `0 <= X <= 719`
- `0 <= Y <= 347`

---

## Plantronics Color Bit Organization

### 320×200 16-Color Bit Organization

| bplane# | bit7 | bit6 | bit5 | bit4 | bit3 | bit2 | bit1 | bit0 |
|---|---|---|---|---|---|---|---|---|
| plane0 | c1 | c0 | c1 | c0 | c1 | c0 | c1 | c0 |
| plane1 | c3 | c2 | c3 | c2 | c3 | c2 | c3 | c2 |
| pixel# | pixel0 | | pixel1 | | pixel2 | | pixel3 | |

### 640×200 4-Color Bit Organization

| bplane# | bit7 | bit6 | bit5 | bit4 | bit3 | bit2 | bit1 | bit0 |
|---|---|---|---|---|---|---|---|---|
| plane0 | c0 | c0 | c0 | c0 | c0 | c0 | c0 | c0 |
| plane1 | c1 | c1 | c1 | c1 | c1 | c1 | c1 | c1 |
| pixel# | pixel0 | pixel1 | pixel2 | pixel3 | pixel4 | pixel5 | pixel6 | pixel7 |

### Color Table

| c2/I | c1/R | c0/G | c3/B | Color |
|---|---|---|---|---|
| 0 | 0 | 0 | 0 | black |
| 0 | 0 | 0 | 1 | blue |
| 0 | 0 | 1 | 0 | green |
| 0 | 0 | 1 | 1 | cyan |
| 0 | 1 | 0 | 0 | red |
| 0 | 1 | 0 | 1 | magenta |
| 0 | 1 | 1 | 0 | brown |
| 0 | 1 | 1 | 1 | white |
| 1 | 0 | 0 | 0 | gray |
| 1 | 0 | 0 | 1 | lt. blue |
| 1 | 0 | 1 | 0 | lt. green |
| 1 | 0 | 1 | 1 | lt. cyan |
| 1 | 1 | 0 | 0 | lt. red |
| 1 | 1 | 0 | 1 | lt. magenta |
| 1 | 1 | 1 | 0 | yellow |
| 1 | 1 | 1 | 1 | bright white |
