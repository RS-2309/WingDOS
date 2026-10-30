# Flappy Bird — x86 Assembly

A Flappy Bird-style game written in **16-bit x86 assembly** using **NASM**. It runs as a DOS `.COM` program and uses VGA Mode 13h to render the game in 320×200, 256-colour graphics.

The project is built around low-level hardware and DOS interfaces: keyboard input is read through BIOS interrupts, graphics are drawn directly into video memory through an off-screen framebuffer, and the scoring sound is generated using the PC speaker.

## Features

- Bird movement with gravity and flap controls.
- Moving pipes with randomly selected gaps.
- Collision detection against the pipes and screen boundaries.
- Score tracking when the bird successfully passes a pipe.
- Increasing pipe speed as the score rises, up to a fixed maximum.
- Custom VGA palette with a light sky-blue background, clouds, green pipes, and a drawn bird sprite.
- Off-screen rendering followed by a framebuffer copy to reduce visible flicker and tearing.
- A short PC-speaker beep when a point is earned.
- Game-over screen that remains visible until the player exits.

## Requirements

- **NASM** — to assemble the source into a DOS `.COM` executable.
- **DOS-compatible environment** — the program targets 16-bit DOS.
- **DOSBox Staging** (or another DOS emulator with VGA Mode 13h and PC-speaker support) — recommended for running it on a modern computer.

The game uses VGA Mode 13h (`320×200`, 256 colours), BIOS keyboard and video services, DOS memory-allocation services, and the PC speaker. It is not a native macOS, Windows, or Linux application.

## Project files

| File | Description |
|---|---|
| `main.asm` | NASM source code for the game. |
| `main.com` | Assembled DOS `.COM` executable. |

## Build

From the project directory, run:

```bash
nasm -f bin main.asm -o main.com
```

This assembles `main.asm` into the flat binary `main.com`.

## Run

Open the project directory in DOSBox Staging and run:

```dos
main.com
```

If you already have the supplied `main.com`, you can run it directly without assembling the source first.

## Controls

| Key | Action |
|---|---|
| `SPACE` | Flap / move the bird upward. |
| `ESC` | Exit the game. |

After a collision, the game-over screen stays on display. Press `ESC` to return to DOS.

## How it works

### Program setup

The program starts as a DOS `.COM` executable. It first reduces its DOS memory block and allocates a separate 64,000-byte buffer for drawing. It then switches the display to VGA Mode 13h, configures a light sky-blue palette entry, hides the text cursor, and initializes the pseudo-random gap generator.

### Game loop and physics

The main loop checks for keyboard input, updates the bird and pipe positions, checks for scoring and collisions, and renders a frame. Pressing `SPACE` gives the bird an upward velocity. Gravity is applied on each update, with the downward velocity capped so that it cannot increase indefinitely.

The pipe moves from right to left. When it has passed the bird, the score increases once. Pipe speed increases at score intervals, up to the game's maximum speed. A new gap position is selected when the pipe is reset.

### Collision and scoring

The game checks whether the bird overlaps the pipe horizontally. If it does, the bird must fit completely inside the gap; otherwise, the game ends. The bird also loses if it crosses the upper or lower screen boundary. Successfully passing a pipe awards one point and triggers a short PC-speaker beep.

### Graphics and rendering

Graphics are drawn into the allocated off-screen framebuffer rather than directly onto the visible display. Rectangles are used to construct the background, clouds, pipes, bird sprite, and text. Once a frame is ready, the program waits for vertical retrace and copies the framebuffer to VGA memory. This helps reduce visible tearing and flicker.

The game uses a small built-in 8×8 bitmap font for its score and game-over text. The pipe gaps are varied using a lightweight 16-bit pseudo-random state.

### Game-over and exit

When a collision occurs, the speaker is silenced and the game-over text is drawn. The screen remains displayed while the program waits for `ESC`. On exit, the program silences the speaker, restores the standard text display mode, and returns control to DOS.
