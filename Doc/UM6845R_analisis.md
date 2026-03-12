# Análisis del Módulo UM6845R

> **Implementación Verilog del CRTC UM6845R**  
> Autor original: Sorgelig (2018) — Compatible Amstrad CPC  
> Licencia: GNU General Public License v2

---

## 1. Descripción General

El **UM6845R** es una implementación en Verilog del **CRTC (Cathode Ray Tube Controller)** compatible con el chip UM6845R original, usado en ordenadores como el **Amstrad CPC**. Su función es generar todas las señales de temporización necesarias para controlar un monitor de tubo de rayos catódicos (o equivalente digital).

El módulo soporta dos modos de operación seleccionables mediante la señal `TYPE`:
- **CRTC0** (`TYPE=0`): comportamiento estándar Motorola 6845.
- **CRTC1** (`TYPE=1`): variante Amstrad con diferencias en recarga de dirección y registro de estado.

---

## 2. Interfaz del Módulo

### Entradas de Control

| Señal | Descripción |
|---|---|
| `CLOCK` | Reloj principal del sistema |
| `CLKEN` | Clock Enable — habilita el funcionamiento por ciclo |
| `nRESET` | Reset activo en bajo |
| `TYPE` | Tipo de CRTC: `0` = CRTC0, `1` = CRTC1 (Amstrad) |
| `ENABLE` | Habilita el acceso al bus |
| `nCS` | Chip Select activo en bajo |
| `R_nW` | Read/Write: `1` = lectura, `0` = escritura |
| `RS` | Register Select: `0` = dirección, `1` = dato |
| `DI[7:0]` | Bus de datos de entrada |

### Salidas

| Señal | Descripción |
|---|---|
| `DO[7:0]` | Bus de datos de salida |
| `HSYNC` | Sincronismo horizontal |
| `VSYNC` | Sincronismo vertical |
| `DE` | Display Enable — indica píxel visible |
| `FIELD` | Campo actual en modo entrelazado |
| `CURSOR` | Señal activa cuando el haz está sobre el cursor |
| `MA[13:0]` | Memory Address — dirección de vídeo actual |
| `RA[4:0]` | Row Address — línea dentro del carácter |

---

## 3. Registros Internos (R0–R15)

El chip expone **16 registros programables** accesibles mediante el bus, que controlan toda la geometría del vídeo:

| Registro | Nombre | Bits | Función |
|---|---|---|---|
| R0 | `h_total` | 8 | Número total de caracteres por línea horizontal |
| R1 | `h_displayed` | 8 | Caracteres visibles por línea |
| R2 | `h_sync_pos` | 8 | Posición del pulso HSYNC |
| R3 | `h/v_sync_width` | 4+4 | Duración de los pulsos HSYNC y VSYNC |
| R4 | `v_total` | 7 | Total de filas de caracteres por frame |
| R5 | `v_total_adj` | 5 | Ajuste fino vertical (líneas de relleno) |
| R6 | `v_displayed` | 7 | Filas de caracteres visibles |
| R7 | `v_sync_pos` | 7 | Posición del pulso VSYNC |
| R8 | `skew / interlace` | 2+2 | Retardo de DE y modo entrelazado |
| R9 | `v_max_line` | 5 | Máximo de líneas por fila de caracteres |
| R10 | `cursor_start / mode` | 5+2 | Línea de inicio del cursor y modo de parpadeo |
| R11 | `cursor_end` | 5 | Línea de fin del cursor |
| R12 | `start_addr_h` | 6 | Dirección alta de inicio del frame en VRAM |
| R13 | `start_addr_l` | 8 | Dirección baja de inicio del frame en VRAM |
| R14 | `cursor_h` | 6 | Dirección alta de la posición del cursor |
| R15 | `cursor_l` | 8 | Dirección baja de la posición del cursor |

### Acceso a Registros

El acceso se realiza en dos pasos:
1. Con `RS=0`, escribir en `DI[4:0]` el número de registro a seleccionar.
2. Con `RS=1`, leer o escribir el valor del registro seleccionado.

Solo los registros R10–R15 son legibles. El resto devuelven `0x00` en lectura (o `0xFF` para el registro 31 en modo CRTC0).

---

## 4. Generación de Temporización — Los Tres Contadores

El núcleo del módulo son tres contadores anidados que reproducen el barrido del haz electrónico:

```
CLOCK/CLKEN
    │
    ├─► hcc  (horizontal)      ──► HSYNC, hde
    │       │
    │       └─► line (líneas/carácter) ──► RA
    │               │
    │               └─► row (filas)    ──► VSYNC, vde
    │                       │
    │                       └─► frame_new ──► recarga row_addr
```

### 4.1 Contador Horizontal (`hcc`)

- Cuenta de `0` a `R0_h_total` (total de caracteres por línea).
- Al llegar al final (`hcc_last`), se reinicia a `0` → nueva línea horizontal.
- Genera `hde` (Horizontal Display Enable) activo mientras `hcc < R1_h_displayed`.
- Dispara el pulso **HSYNC** cuando `hcc == R2_h_sync_pos`, con duración `R3_h_sync_width` ciclos.

### 4.2 Contador de Línea (`line`)

- Cuenta las líneas de píxeles dentro de una fila de caracteres, de `0` a `R9_v_max_line`.
- En modo entrelazado, avanza de dos en dos (bit `interlace`).
- Al completar todas las líneas de una fila de caracteres → señal `row_new`.
- Su valor se expone directamente como `RA` (Row Address) hacia la memoria de vídeo.

### 4.3 Contador de Fila (`row`)

- Cuenta las filas de caracteres de `0` a `R4_v_total`.
- Al terminar la última fila, puede entrar en **modo de ajuste** (`in_adj`) para añadir líneas de relleno configuradas en `R5_v_total_adj`, permitiendo frecuencias de refresco no múltiplos enteros del número de líneas.
- Al completar el frame → señal `frame_new`, que reinicia el ciclo.

---

## 5. Generación de Dirección de Memoria (`MA`)

```verilog
MA = row_addr + hcc
RA = line | (field & interlace)
```

- `row_addr` se incrementa al final de cada fila visible (`hcc == R1_h_displayed` en la última línea), apuntando al inicio de la siguiente fila en la VRAM.
- En `frame_new` se recarga con la dirección base `{R12_start_addr_h, R13_start_addr_l}`.
- `MA` es, por tanto, la dirección absoluta del carácter actual que debe leerse de la VRAM en cada ciclo.

### Diferencia entre CRTC0 y CRTC1

| Comportamiento | CRTC0 | CRTC1 |
|---|---|---|
| Recarga de `row_addr` | Solo en `frame_new` | También en cada línea de la primera fila |
| Registros R12/R13 legibles | Sí | No (devuelven `0x00`) |
| Ancho VSYNC | Configurable (R3) | Fijo (4 líneas) |
| Registro de estado | No | `0x00` en zona visible, `0x20` fuera |

---

## 6. Display Enable (`DE`) y Skew

```verilog
wire [3:0] de = {1'b0, dde[1:0], hde & vde & |R6_v_displayed};
assign DE = de[R8_skew & ~{2{TYPE}}];
```

- `DE` se activa únicamente cuando tanto `hde` (zona horizontal visible) como `vde` (zona vertical visible) están activos simultáneamente.
- El campo `R8_skew` permite **retrasar la señal DE** 0, 1 o 2 ciclos de reloj. Este retardo compensa las latencias introducidas por circuitos externos de acceso a memoria, garantizando que los datos lleguen a tiempo al DAC de vídeo.
- En modo **CRTC1** (`TYPE=1`), el skew se ignora y se fuerza a 0.

---

## 7. Sincronismo Vertical (`VSYNC`)

- Se activa cuando `row == R7_v_sync_pos` al inicio de una nueva fila de caracteres.
- La duración está controlada por `R3_v_sync_width` en CRTC0. En CRTC1 la duración es fija.
- En **modo entrelazado**, el VSYNC del campo impar se dispara a mitad de línea (`hcc == R0_h_total / 2`), produciendo el desplazamiento de medio período horizontal necesario para el entrelazado correcto.
- Incluye lógica para **separar dos VSYNCs consecutivos**: usando `old_hs` detecta el flanco de bajada de HSYNC para desactivar VSYNC, evitando que dos pulsos contiguos se fusionen en uno solo.

---

## 8. Control del Cursor

El cursor tiene dos niveles de control independientes:

### 8.1 Posición

El cursor es visible cuando se cumplen todas estas condiciones simultáneamente:

- El haz está en zona visible (`hde & vde`).
- La dirección actual coincide con la del cursor: `MA == {R14_cursor_h, R15_cursor_l}`.
- La línea de rasterizado está dentro del rango `[R10_cursor_start, R11_cursor_end]`.

### 8.2 Modo de Parpadeo

Controlado por el campo `R10_cursor_mode` (2 bits):

| Modo | Código | Comportamiento |
|---|---|---|
| Siempre visible | `00` | El cursor no parpadea |
| Invisible | `01` | El cursor nunca se muestra |
| Parpadeo lento | `10` | Alterna cada 16 frames (`curcc[4]`) |
| Parpadeo rápido | `11` | Alterna cada 32 frames (`curcc[5]`) |

El contador `curcc` se incrementa en cada `frame_new`, proporcionando la base de tiempo para el parpadeo.

---

## 9. Modo Entrelazado

Activado cuando `R8_interlace == 2'b11`. Efectos sobre el sistema:

| Elemento | Comportamiento en modo entrelazado |
|---|---|
| Contador `line` | Avanza de 2 en 2 (omite líneas alternas) |
| `FIELD` | Indica campo par (`0`) o impar (`1`) |
| `RA` | Incorpora el bit de campo para seleccionar líneas alternas |
| `VSYNC` | Campo impar desplazado media línea horizontal |
| `row_addr` | Se recarga con la dirección base en cada frame |

---

## 10. Reset y Condiciones Iniciales

Al activarse `nRESET` (bajo), el módulo inicializa:

```
hcc    = 0   (inicio de línea)
line   = 0   (primera línea de carácter)
row    = 0   (primera fila)
in_adj = 0   (fuera del período de ajuste)
field  = 0   (campo par)
hsc    = 0   (contador HSYNC)
vsc    = 0   (contador VSYNC)
hde    = 0
vde    = 0
HSYNC  = 0
VSYNC  = 0
cursor_line = 0
```

Los registros de configuración R0–R15 **no se resetean**, conservando sus valores previos.

---

## 11. Flujo Completo de Operación

```
[Reset]
   │
   └─► Inicializa contadores y señales de sincronismo
          │
          ▼
[Por cada ciclo CLKEN activo]
   │
   ├─► Incrementa hcc
   │       ├─► hcc < R1_h_displayed  ──► hde = 1 (zona visible horizontal)
   │       ├─► hcc == R2_h_sync_pos  ──► HSYNC = 1, duración R3_h_sync_width
   │       └─► hcc == R0_h_total     ──► hcc = 0, line_new
   │
   ├─► line_new
   │       ├─► Incrementa line
   │       └─► line == R9_v_max_line ──► row_new
   │
   ├─► row_new
   │       ├─► Incrementa row_addr (si línea visible)
   │       ├─► row == R7_v_sync_pos  ──► VSYNC = 1
   │       ├─► row == R6_v_displayed ──► vde = 0
   │       └─► row == R4_v_total     ──► frame_new
   │
   ├─► frame_new
   │       ├─► row_addr = {R12, R13}  (recarga dirección base)
   │       ├─► vde = 1               (inicio zona visible vertical)
   │       └─► field = ~field        (si modo entrelazado)
   │
   └─► Salidas
           ├─► MA = row_addr + hcc
           ├─► RA = line
           ├─► DE = hde & vde (con skew opcional)
           └─► CURSOR = (MA == cursor_addr) & cursor_line & cde
```

---

## 12. Parámetros Hercules 6845 CRTC

Valores de referencia usados en el PC10/PC20 para el modo Hercules (720×348):

| Registro | Valor |
|---|---|
| R0 | `36h` |
| R1 | `2Dh` |
| R2 | `2Fh` |
| R3 | `07h` |
| R4 | `5Bh` |
| R5 | `00h` |
| R6 | `57h` |
| R7 | `53h` |
| R8 | `02h` |
| R9 | `03h` |
| R10–R13 | `00h` |

---

*Documento generado a partir del análisis del fichero `UM6845R.v` y la documentación técnica del Commodore PC10/PC20.*
