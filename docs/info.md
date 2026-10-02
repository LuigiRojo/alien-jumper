<!---

This file is used to generate your project datasheet. Please fill in the information below and delete any unused
sections.

You can also include images in this folder and reference them in the markdown. Each image must be less than
512 kb in size, and the combined size of all images must be less than 1 MB.
-->

## How it works

Alien Jumper is an endless runner game rendered on a VGA monitor (640x480 @ 60 Hz,
25.175 MHz clock). An alien runs across the desert and must jump over crates.

- **Video:** `hvsync_generator` produces the VGA timing. Every pixel is computed on
  the fly (no frame buffer): sky, sandy ground with scrolling pebbles, the player
  sprite (8x8 bitmap scaled 4x), the crates and a 4-digit score.
- **Game logic:** updates once per frame, right after the visible area ends, so the
  picture never shows a half-updated state.
- **Jump physics:** a jump starts at 15 px/frame and gravity subtracts 1 px/frame
  every frame, so it peaks at 120 px and lasts about half a second. You can only
  jump from the ground.
- **Obstacles:** two crates (randomly tall or short, chosen with an LFSR) move to
  the left. Each one respawns behind the other with a minimum gap, so every
  sequence can always be cleared.
- **Difficulty:** speed starts at 2 px/frame and increases by 1 every 200 points,
  up to 6 px/frame.
- **Score:** 10 points per second, shown in decimal (BCD) at the top right.
- **Game over:** on collision the player turns red, the sky darkens and the score
  freezes.
- **Input:** the Gamepad Pmod is read with the `gamepad_pmod_single` driver
  (serial data, clock and latch on `ui[6:4]`).

## How to test

1. Connect the TinyVGA Pmod to the output pins and a VGA monitor to it.
2. Connect the Gamepad Pmod to the input pins.
3. Set the clock to 25.175 MHz (25 MHz also works on most monitors) and reset.
4. Press **A**, **B** or **Up** to jump over the crates.
5. After losing, press **Start** to play again.

## External hardware

- TinyVGA Pmod (VGA output)
- Gamepad Pmod with a SNES-style controller
- VGA monitor

