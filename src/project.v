/*
 * Copyright (c) 2026 CTIS
 * SPDX-License-Identifier: Apache-2.0
 *
 * Runner: un robot corre y salta cajas. Base VGA + gamepad de Uri Shaked,
 * driver del Gamepad Pmod de Pat Deegan.
 *
 * Controles: A, B o Arriba = saltar. Start = reiniciar tras perder.
 */

`default_nettype none

module tt_um_vga_example (
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // always 1 when the design is powered, so you can ignore it
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);

  assign uio_out = 0;
  assign uio_oe  = 0;
  wire _unused_ok = &{ena, ui_in[7], ui_in[3:0], uio_in};

  // ---------------------------------------------------------------- VGA
  wire hsync, vsync, video_active;
  wire [9:0] pix_x, pix_y;
  reg [1:0] R, G, B;
  assign uo_out = {hsync, B[0], G[0], R[0], vsync, B[1], G[1], R[1]};

  hvsync_generator vga_sync_gen (
      .clk(clk), .reset(~rst_n),
      .hsync(hsync), .vsync(vsync), .display_on(video_active),
      .hpos(pix_x), .vpos(pix_y)
  );

  // ------------------------------------------------------------ Gamepad
  wire inp_b, inp_y, inp_select, inp_start, inp_up, inp_down;
  wire inp_left, inp_right, inp_a, inp_x, inp_l, inp_r;

  gamepad_pmod_single driver (
      .rst_n(rst_n), .clk(clk),
      .pmod_data(ui_in[6]), .pmod_clk(ui_in[5]), .pmod_latch(ui_in[4]),
      .b(inp_b), .y(inp_y), .select(inp_select), .start(inp_start),
      .up(inp_up), .down(inp_down), .left(inp_left), .right(inp_right),
      .a(inp_a), .x(inp_x), .l(inp_l), .r(inp_r), .is_present()
  );

  wire jump_btn = inp_a | inp_b | inp_up;

  // ---------------------------------------------------------- Constantes
  localparam [9:0] GROUND = 10'd400;   // fila de la línea del suelo
  localparam [9:0] PX     = 10'd80;    // borde izquierdo del robot
  localparam signed [5:0] JUMP_V = 6'sd15;

  // Toda la lógica del juego avanza una vez por cuadro, justo al salir del área visible.
  wire frame_tick = (pix_x == 10'd0) && (pix_y == 10'd480);

  // -------------------------------------------------------- Estado juego
  reg        dead;
  reg  [7:0] h;          // altura del robot sobre el suelo (px)
  reg signed [5:0] vy;   // velocidad vertical (px/cuadro), positiva = sube
  reg [10:0] ox0, ox1;   // borde DERECHO de cada caja; ocupa [ox-16, ox)
  reg        tall0, tall1; // caja alta (40 px) o baja (24 px)
  reg  [9:0] scroll;     // desplazamiento del suelo
  reg [15:0] score;      // 4 dígitos BCD
  reg  [2:0] tick6;      // suma 1 punto cada 6 cuadros (10 por segundo)
  reg  [3:0] anim;       // animación de las piernas
  reg [15:0] lfsr;       // pseudoaleatorio para separar las cajas

  // 2 px/cuadro al inicio, +1 cada 200 puntos, tope de 6 desde los 1000 puntos
  wire [3:0] speed = (score[15:12] != 4'd0) ? 4'd6 : 4'd2 + {1'b0, score[11:9]};
  wire [9:0] obs_h0 = tall0 ? 10'd40 : 10'd24;
  wire [9:0] obs_h1 = tall1 ? 10'd40 : 10'd24;

  // Colisión con 4 px de tolerancia por lado
  function hit_box;
    input [10:0] ox;
    input [9:0]  oh;
    begin
      hit_box = (ox > {1'b0, PX} + 11'd4) && (ox < {1'b0, PX} + 11'd44) && ({2'b00, h} + 10'd4 < oh);
    end
  endfunction
  wire hit = hit_box(ox0, obs_h0) | hit_box(ox1, obs_h1);

  // Una caja reaparece detrás de la otra: mínimo 240 px (siempre se puede aterrizar
  // y volver a saltar, incluso a velocidad 6) más 0..127 px aleatorios.
  localparam [10:0] SPAWN_X = 11'd656, MIN_GAP = 11'd240;
  function [10:0] spawn_after;
    input [10:0] other;
    begin
      spawn_after = ((other + MIN_GAP > SPAWN_X) ? other + MIN_GAP : SPAWN_X) + {4'd0, lfsr[6:0]};
    end
  endfunction
  wire [10:0] spd11 = {7'd0, speed};

  wire signed [9:0] h_next = $signed({2'b00, h}) + $signed({{4{vy[5]}}, vy});

  function [15:0] bcd_inc;
    input [15:0] v;
    begin
      bcd_inc = v;
      if (v[3:0] != 4'd9) bcd_inc[3:0] = v[3:0] + 4'd1;
      else begin
        bcd_inc[3:0] = 4'd0;
        if (v[7:4] != 4'd9) bcd_inc[7:4] = v[7:4] + 4'd1;
        else begin
          bcd_inc[7:4] = 4'd0;
          if (v[11:8] != 4'd9) bcd_inc[11:8] = v[11:8] + 4'd1;
          else begin
            bcd_inc[11:8] = 4'd0;
            bcd_inc[15:12] = (v[15:12] == 4'd9) ? 4'd0 : v[15:12] + 4'd1;
          end
        end
      end
    end
  endfunction

  always @(posedge clk) begin
    if (~rst_n) lfsr <= 16'hACE1;
    else        lfsr <= {lfsr[14:0], lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10]};
  end

  always @(posedge clk) begin
    if (~rst_n || (dead && inp_start)) begin
      dead   <= 1'b0;
      h      <= 8'd0;
      vy     <= 6'sd0;
      ox0    <= 11'd700;
      ox1    <= 11'd1000;
      tall0  <= 1'b0;
      tall1  <= 1'b1;
      scroll <= 10'd0;
      score  <= 16'd0;
      tick6  <= 3'd0;
      anim   <= 4'd0;
    end else if (frame_tick && !dead) begin
      if (hit) begin
        dead <= 1'b1;
      end else begin
        // Salto: solo desde el suelo. Después, gravedad de 1 px/cuadro².
        if (h == 8'd0 && vy <= 6'sd0) begin
          vy <= jump_btn ? JUMP_V : 6'sd0;
        end else if (h_next <= 10'sd0) begin
          h  <= 8'd0;
          vy <= 6'sd0;
        end else begin
          h  <= h_next[7:0];
          vy <= vy - 6'sd1;
        end

        // Cajas: avanzan a la izquierda; al salir reaparecen detrás de la otra.
        if (ox0 <= spd11) begin
          ox0   <= spawn_after(ox1);
          tall0 <= lfsr[8];
        end else begin
          ox0 <= ox0 - spd11;
        end
        if (ox1 <= spd11) begin
          ox1   <= spawn_after(ox0);
          tall1 <= lfsr[9];
        end else begin
          ox1 <= ox1 - spd11;
        end

        scroll <= scroll + {6'd0, speed};
        anim   <= anim + 4'd1;

        if (tick6 == 3'd5) begin
          tick6 <= 3'd0;
          score <= bcd_inc(score);
        end else begin
          tick6 <= tick6 + 3'd1;
        end
      end
    end
  end

  // ------------------------------------------------------------- Dibujo
  // Robot: 8x8 escalado 4x = 32x32. Las dos últimas filas alternan para animar las piernas.
  wire [10:0] py = {1'b0, pix_y} + {3'b000, h};   // y "como si" el robot estuviera en el suelo
  wire in_robot = (pix_x >= PX) && (pix_x < PX + 10'd32) &&
                  (py >= {1'b0, GROUND} - 11'd32) && (py < {1'b0, GROUND});
  wire [10:0] ry = py - ({1'b0, GROUND} - 11'd32);
  wire [9:0]  rx = pix_x - PX;
  wire [2:0] r_row = ry[4:2];
  wire [2:0] r_col = rx[4:2];
  wire legs_b = anim[2] && h == 8'd0;
  reg [7:0] robot_row;
  always @(*) begin
    case (r_row)
      3'd0: robot_row = 8'b00011000;   // antena
      3'd1: robot_row = 8'b01111110;   // cabeza
      3'd2: robot_row = 8'b01011010;   // ojos
      3'd3: robot_row = 8'b01111110;
      3'd4: robot_row = 8'b00111100;   // cuerpo
      3'd5: robot_row = 8'b01111110;   // brazos
      3'd6: robot_row = legs_b ? 8'b01000010 : 8'b00100100;
      3'd7: robot_row = legs_b ? 8'b11000011 : 8'b01100110;
    endcase
  end
  wire robot_px = in_robot && robot_row[3'd7 - r_col];

  // Cajas con borde
  wire [10:0] px11 = {1'b0, pix_x};
  function in_box;
    input [10:0] ox;
    input [9:0]  oh;
    begin
      in_box = (px11 + 11'd16 >= ox) && (px11 < ox) && (pix_y >= GROUND - oh) && (pix_y < GROUND);
    end
  endfunction
  function box_edge;
    input [10:0] ox;
    input [9:0]  oh;
    begin
      box_edge = (px11 + 11'd14 < ox) || (px11 + 11'd2 >= ox) || (pix_y < GROUND - oh + 10'd2);
    end
  endfunction
  wire in_obs0 = in_box(ox0, obs_h0);
  wire in_obs1 = in_box(ox1, obs_h1);
  wire in_obs  = in_obs0 | in_obs1;
  wire obs_edge = in_obs0 ? box_edge(ox0, obs_h0) : box_edge(ox1, obs_h1);

  // Suelo
  wire ground_line = (pix_y == GROUND) || (pix_y == GROUND + 10'd1);
  wire below       = pix_y > GROUND + 10'd1;
  wire [9:0] gx    = pix_x + scroll;
  wire pebble      = below && (gx[4:0] < 5'd3) && (pix_y[3:0] == 4'd8);

  // Marcador: 4 dígitos de 3x5 escalados 4x, esquina superior derecha
  localparam [9:0] SX = 10'd512, SY = 10'd24;
  wire in_score = (pix_x >= SX) && (pix_x < SX + 10'd64) && (pix_y >= SY) && (pix_y < SY + 10'd20);
  wire [9:0] sxr = pix_x - SX;
  wire [9:0] syr = pix_y - SY;
  wire [1:0] d_idx = sxr[5:4];
  wire [1:0] d_col = sxr[3:2];
  wire [2:0] d_row = syr[4:2];
  reg  [3:0] digit;
  always @(*) begin
    case (d_idx)
      2'd0: digit = score[15:12];
      2'd1: digit = score[11:8];
      2'd2: digit = score[7:4];
      2'd3: digit = score[3:0];
    endcase
  end
  reg [14:0] font;   // 5 filas x 3 columnas, fila 0 en los bits altos
  always @(*) begin
    case (digit)
      4'd0: font = 15'b111_101_101_101_111;
      4'd1: font = 15'b010_110_010_010_111;
      4'd2: font = 15'b111_001_111_100_111;
      4'd3: font = 15'b111_001_111_001_111;
      4'd4: font = 15'b101_101_111_001_001;
      4'd5: font = 15'b111_100_111_001_111;
      4'd6: font = 15'b111_100_111_101_111;
      4'd7: font = 15'b111_001_001_001_001;
      4'd8: font = 15'b111_101_111_101_111;
      4'd9: font = 15'b111_101_111_001_111;
      default: font = 15'b0;
    endcase
  end
  wire [3:0] f_bit = 4'd14 - (d_row * 4'd3 + {2'b00, d_col});
  wire score_px = in_score && (d_col != 2'd3) && font[f_bit];

  // Colores {R,G,B}
  localparam [5:0] SKY    = 6'b01_10_11;
  localparam [5:0] SKY_GO = 6'b10_01_01;   // cielo al perder
  localparam [5:0] SAND   = 6'b11_10_01;
  localparam [5:0] DARK   = 6'b01_01_00;
  localparam [5:0] ROBOT  = 6'b00_11_11;
  localparam [5:0] HURT   = 6'b11_00_00;
  localparam [5:0] CRATE  = 6'b11_01_00;
  localparam [5:0] CRATE2 = 6'b10_00_00;
  localparam [5:0] BLACK  = 6'b00_00_00;

  always @(posedge clk) begin
    if (~rst_n || !video_active) begin
      {R, G, B} <= BLACK;
    end else if (score_px) {R, G, B} <= BLACK;
    else if (robot_px)     {R, G, B} <= dead ? HURT : ROBOT;
    else if (in_obs)       {R, G, B} <= obs_edge ? CRATE2 : CRATE;
    else if (ground_line)  {R, G, B} <= DARK;
    else if (pebble)       {R, G, B} <= DARK;
    else if (below)        {R, G, B} <= SAND;
    else                   {R, G, B} <= dead ? SKY_GO : SKY;
  end
endmodule 