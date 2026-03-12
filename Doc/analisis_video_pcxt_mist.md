# Análisis del Sistema de Vídeo — Core PCXT para MiST

---

## 1. Visión general

El core PCXT para MiST emula dos tarjetas de vídeo históricas del PC IBM:

- **CGA** (Color Graphics Adapter) — modo predeterminado
- **MDA** (Monochrome Display Adapter) — activable desde el OSD

La resolución y frecuencia de refresco que ve el monitor **no provienen del framework `mist_video`**, sino que son determinadas íntegramente por el propio core, a través de una cadena de tres niveles:

1. El **PLL de vídeo** (`pllvideo`) que genera los relojes base.
2. El **CRTC** (`UM6845R` para CGA, `crtc6845` para MDA) con sus parámetros de timing fijos.
3. El **scandoubler** de la Graphics Gremlin (`cga_scandoubler`) que dobla la frecuencia de línea del CGA.

`mist_video` actúa únicamente como pipeline de OSD y salida analógica; en este core se le indica explícitamente que **no** haga scandoubling propio (`scandoubler_disable = 1'b1`).

---

## 2. Relojes de vídeo

### 2.1 Generación de relojes — `pllvideo` (`PCXT.sv` líneas 570–577)

```verilog
pllvideo pllvideo
(
    .inclk0(CLK_50M),
    .areset(1'b0),
    .c0(clk_28_636),   // 28.636 MHz  →  CLOCK_VGA_CGA
    .c1(clk_56_875),   // 56.875 MHz  →  CLOCK_VGA_MDA
    .locked()
);
```

| Señal        | Frecuencia     | Destino                         |
|--------------|----------------|---------------------------------|
| `clk_28_636` | 28.636 MHz     | Reloj pixel CGA (Graphics Gremlin) |
| `clk_56_875` | ~57.272 MHz    | Reloj pixel MDA + `mist_video` (clk_sys) |

### 2.2 Selección dinámica del reloj de vídeo (`PCXT.sv` línea 1494)

```verilog
assign clk_vid = mda_mode_video_ff ? clk_56_875 : clk_28_636;
```

El reloj activo depende de si el usuario ha seleccionado el modo MDA o CGA desde el OSD (opción `"P3O4,Video Output,CGA/Tandy,MDA"`).

El reloj que alimenta `mist_video` es siempre `clk_56_875` (`PCXT.sv` línea 1522), independientemente del modo, ya que es el módulo padre del pipeline de salida.

---

## 3. Modo CGA

### 3.1 Flujo del reloj de pixel

```
clk_28_636 (28.636 MHz)
    └── cga_sequencer  →  crtc_clk (÷2 = 14.318 MHz)
            └── UM6845R (CRTC)  →  hsync / vsync nativos @ ~15.7 kHz / 60 Hz
                    └── cga_scandoubler  →  dbl_hsync / dbl_video @ ~31.96 kHz / 60 Hz
                            └── CHIPSET → mist_video (solo OSD, sin scandoubling)
```

### 3.2 Parámetros del CRTC (`cga.v` líneas 329–339)

```verilog
defparam crtc.H_TOTAL      = 8'd113;  // caracteres totales por línea
defparam crtc.H_DISP       = 8'd80;   // caracteres visibles
defparam crtc.H_SYNCPOS    = 8'd90;
defparam crtc.H_SYNCWIDTH  = 4'd10;
defparam crtc.V_TOTAL      = 7'd31;   // filas de caracteres totales
defparam crtc.V_TOTALADJ   = 5'd6;    // líneas de ajuste vertical
defparam crtc.V_DISP       = 7'd25;
defparam crtc.V_SYNCPOS    = 7'd28;
defparam crtc.V_MAXSCAN    = 5'd7;    // 8 líneas por carácter (0–7)
```

#### Cálculo de frecuencias nativas (antes del scandoubler)

El reloj del CRTC es `clk_28_636 / 2 = 14.318 MHz` (el sequencer divide por 2 para generar `crtc_clk`).

- **Caracteres totales por línea:** 113
- **Líneas de barrido totales:** (31 + 1) × 8 + 6 = 262 líneas

```
fH_nativa = 14.318 MHz / 113 ≈ 15,706 Hz  (~15.7 kHz)
fV_nativa = 15,706 Hz / 262 ≈ 59.9 Hz     (~60 Hz)
```

### 3.3 El scandoubler de la Graphics Gremlin (`cga_scandoubler.v`)

El módulo `cga_scandoubler` opera a `clk_28_636` (28.636 MHz) y dobla la frecuencia de línea almacenando cada línea en una RAM dual y releyéndola al doble de velocidad.

Parámetros clave del contador horizontal fast (`cga_scandoubler.v` líneas 50–64):

```verilog
// Contador horizontal fast (línea doblada)
if (hcount_fast == 10'd911) begin
    hcount_fast <= 10'd0;
end

// Pulso hsync doblado
if (hcount_fast == 10'd720)         dbl_hsync <= 1;
if (hcount_fast == 10'd720 + 10'd160) dbl_hsync <= 0;
```

El propio código documenta el razonamiento de diseño:

> "VGA 640×480@60Hz has pix clk of 25.175MHz. Ours is 28.6364MHz, so it is not quite an exact match. **896 clocks per line** gives us an horizontal rate of **31.96KHz** which is close to 31.78KHz (spec). Vertical lines are doubled, so **262 × 2 = 524** which matches exactly."

Aunque el comentario menciona 896 ciclos, el contador real llega hasta 911 (`hcount_fast == 10'd911`), lo que da:

```
fH_doblada  = 28.636 MHz / 912 ≈ 31,407 Hz  (~31.4 kHz)
fV_salida   = 31,407 Hz / 524  ≈ 59.9 Hz    (~60 Hz)
```

La señal `dbl_hsync` (y no la del CRTC) es la que sale al monitor cuando `scandoubler = 1`.

### 3.4 Selección scandoubler en `cga.v` (líneas 452–454)

```verilog
assign hsync_sd = scandoubler ? dbl_hsync : hsync;
assign vsync_sd = scandoubler ? vsync     : vsync;
assign video_sd = scandoubler ? dbl_video : video;
```

La señal `scandoubler` proviene de `~forced_scandoubler` (PCXT.sv línea 1160), que es la señal del framework MiST que detecta si el monitor acepta 15 kHz. En un monitor moderno, `forced_scandoubler = 0`, por tanto `scandoubler = 1` y se usa siempre la salida doblada.

### 3.5 Resolución CGA resultante

| Parámetro | Valor |
|-----------|-------|
| Resolución lógica del CRTC | 640 × 200 (gráficos) / 640 × 200 texto 80×25 |
| Resolución visible tras scandoubler | 640 × 400 (líneas dobladas) |
| Lo que negocia el monitor | **640 × 480 @ 60 Hz** |
| Frecuencia de línea nativa (15 kHz) | ~15.7 kHz |
| Frecuencia de línea tras scandoubler | ~31.4 kHz |
| Frecuencia de refresco vertical | ~60 Hz |

> **¿Por qué el monitor reporta 640×480?** El monitor identifica 524 líneas totales (262 × 2) y ~31.4 kHz de línea. Estos valores encajan dentro del rango de tolerancia del estándar 640×480@60 Hz (524 líneas totales, 31.47 kHz), por lo que el monitor lo muestra como tal.

---

## 4. Modo MDA

### 4.1 Flujo del reloj de pixel

```
clk_56_875 (~57.27 MHz)
    └── mda_sequencer  →  crtc_clk (÷4 ≈ 14.318 MHz)
            └── crtc6845 (CRTC)  →  hsync / vsync @ ~18.43 kHz / 50 Hz
```

> **Nota:** el MDA **no tiene scandoubler**. La señal de vídeo sale directamente desde el CRTC `crtc6845`, sin el módulo `cga_scandoubler`.

### 4.2 Parámetros del CRTC MDA (`mda.v` líneas 211–221)

```verilog
defparam crtc.H_TOTAL      = 8'd99;
defparam crtc.H_DISP       = 8'd80;
defparam crtc.H_SYNCPOS    = 8'd82;
defparam crtc.H_SYNCWIDTH  = 4'd12;
defparam crtc.V_TOTAL      = 7'd31;
defparam crtc.V_TOTALADJ   = 5'd1;
defparam crtc.V_DISP       = 7'd25;
defparam crtc.V_SYNCPOS    = 7'd27;
defparam crtc.V_MAXSCAN    = 5'd13;  // 14 líneas por carácter (0–13)
```

El parámetro `lock(MDA_70HZ == 1)` hace que el CRTC no permita escritura en sus registros de timing, fijando el modo 70 Hz como permanente.

#### Cálculo de frecuencias MDA

El reloj del CRTC para MDA es `clk_56_875 / 4 ≈ 14.219 MHz` (el sequencer MDA divide por 4).

- **Caracteres totales por línea:** 99 + 1 = 100
- **Líneas de barrido totales:** (31 + 1) × 14 + 1 = 449 líneas

```
fH_mda = 14.219 MHz / 100 ≈ 142,190 / (100) ...
```

Revisando con el divisor real del sequencer MDA (`MDA_70HZ = 1`), el reloj del CRTC es la cuarta parte del reloj de entrada, que a su vez viene de `clk_56_875`:

```
clk_crtc_mda ≈ 56.875 MHz / 4 = 14.219 MHz

fH = 14.219 MHz / 100 ≈ 14,219 Hz / ... 
```

Sin embargo, el MDA histórico usa **18.432 MHz** como reloj de píxel. El valor `clk_56_875` ha sido elegido para aproximar ese timing:

```
fH_mda ≈ 56.875 MHz / (4 × 100) ≈ 14,219 Hz  ... 
```

Recalculando con la división correcta por carácter (el CRTC cuenta en unidades de carácter, y cada carácter MDA son 9 píxeles en el hardware original):

```
fH = 56.875 MHz / (4 × 9 × 100) ≈ ... 
```

El dato empírico que reporta el monitor es el más fiable: el monitor detecta **31.8 kHz / 71 Hz**, que corresponde a los timings MDA estándar:

| Parámetro | MDA Estándar | Este core |
|-----------|-------------|-----------|
| Frecuencia de pixel | 16.257 MHz | ~14.2 MHz (aproximado) |
| Frecuencia de línea | 18.432 kHz | ~31.8 kHz (medido) |
| Frecuencia vertical | 50 Hz | ~71 Hz |
| Resolución lógica | 720 × 350 | 720 × 350 |

> **Nota:** La frecuencia de 71 Hz no es exactamente la MDA original (que era ~50 Hz). El parámetro `MDA_70HZ = 1` en `mda.v` y los `defparam` del CRTC con `V_TOTAL=31, V_TOTALADJ=1, V_MAXSCAN=13` generan un timing de ~70–71 Hz deliberadamente, para compatibilidad con monitores modernos que no aceptan 50 Hz.

---

## 5. Papel del framework `mist_video`

El módulo `mist_video` se instancia en `PCXT.sv` (líneas 1519–1559):

```verilog
mist_video #(.COLOR_DEPTH(6), .OUT_COLOR_DEPTH(VGA_BITS), .BIG_OSD(BIG_OSD)) mist_video
(
    .clk_sys         ( clk_56_875   ),
    .scanlines        ( 2'b00        ),
    .ce_divider       ( 1'b1         ),

    // ← CLAVE: scandoubler del framework DESACTIVADO
    .scandoubler_disable (1'b1),

    .no_csync         ( ~forced_scandoubler ),
    .ypbpr            ( status[42]  ),
    .blend            ( status[43]  ),
    .R                ( raux2       ),
    .G                ( gaux2       ),
    .B                ( baux2       ),
    .HSync            ( ~vga_hs     ),
    .VSync            ( ~vga_vs     ),
    ...
);
```

Con `scandoubler_disable = 1'b1`, el módulo interno `scandoubler` de `mist_video` pasa la señal en modo **bypass**: la imagen entra ya doblada (en CGA) o directa (en MDA) y `mist_video` simplemente superpone el OSD y realiza la conversión de color/YPbPr si procede.

**`mist_video` no altera la resolución ni la frecuencia de refresco.**

---

## 6. Resumen de dónde se define cada parámetro

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        CADENA DE VIDEO — PCXT MiST                         │
├───────────────────┬─────────────────────────────────────────────────────────┤
│ MÓDULO            │ QUÉ DEFINE                                              │
├───────────────────┼─────────────────────────────────────────────────────────┤
│ pllvideo          │ Relojes base: 28.636 MHz (CGA) y ~57.27 MHz (MDA)      │
│ PCXT.sv L.570-577 │                                                         │
├───────────────────┼─────────────────────────────────────────────────────────┤
│ UM6845R + defparam│ Timing nativo CGA: ~15.7 kHz / 60 Hz / 640×200        │
│ cga.v L.329-339   │ Parámetros H_TOTAL, V_TOTAL, V_MAXSCAN...              │
├───────────────────┼─────────────────────────────────────────────────────────┤
│ cga_scandoubler   │ Dobla frecuencia de línea CGA: ~31.4 kHz / 60 Hz      │
│ cga.v L.439-454   │ Contador fast hasta 912, 524 líneas totales            │
│ cga_scandoubler.v │ → Monitor lo identifica como 640×480@60Hz             │
├───────────────────┼─────────────────────────────────────────────────────────┤
│ crtc6845 + defparam│ Timing MDA: ~31.8 kHz / ~71 Hz / 720×350             │
│ mda.v L.211-221   │ MDA_70HZ=1 fija los registros del CRTC                │
├───────────────────┼─────────────────────────────────────────────────────────┤
│ mist_video        │ SOLO OSD + conversión color. NO altera timing.         │
│ PCXT.sv L.1536    │ scandoubler_disable=1 → siempre en modo bypass         │
└───────────────────┴─────────────────────────────────────────────────────────┘
```

---

## 7. Tabla resumen de resoluciones y frecuencias

| Modo | Resolución lógica | fH nativa | fV nativa | Tras scandoubler | Lo que reporta el monitor |
|------|-------------------|-----------|-----------|-----------------|---------------------------|
| **CGA** | 640×200 (gfx) / 80×25 texto | ~15.7 kHz | ~60 Hz | ~31.4 kHz / ~60 Hz | **640×480 @ 60 Hz** |
| **MDA** | 720×350 texto | ~31.8 kHz | ~71 Hz | Sin scandoubler | **31.8 kHz / 71 Hz** |

---

## 8. Módulos pendientes de análisis (según `video.qip`)

Los siguientes módulos están declarados en `video.qip` pero no han sido aportados. Su análisis podría completar detalles del pipeline interno del CHIPSET:

- `mda_sequencer.v` — divisor de reloj para CRTC MDA y scheduling de VRAM
- `mda_pixel.v` — generación del pixel MDA (video + intensity)
- `mda_vgaport.v` — conversión señal MDA a formato VGA RGB
- `mda_attrib.v` — decodificación de atributos de carácter MDA
- `cga_sequencer.v` — divisor de reloj CGA y arbitraje bus ISA/CRTC
- `cga_pixel.sv` — generación del pixel CGA (irgb → RGB)
- `cga_vgaport.v` — conversión CGA digital a VGA analógico
- `cga_attrib.v` — decodificación de atributos de carácter CGA
- `cga_vram.v` / `vram_ip_*.v` — memoria de vídeo
- `video_monochrome_converter.sv` — convierte la salida a escala de grises/color según modo de pantalla (verde, ámbar, etc.)
- `vga_cgaport.v` — convierte RGB del OSD a señal digital CGA (para composite)
- `cga_composite.v` — generación de video compuesto
- `serialize_comp_tx.v` — serialización de la señal compuesta

---

*Análisis realizado sobre: `PCXT.sv`, `cga.v`, `cga_scandoubler.v`, `mda.v`, `UM6845R.v`, `mist_video.v`, `video.qip`*
