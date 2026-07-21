# Rimon — Chapter One: The Razzia (Godot build)

A native, installable version of the same demo built for the browser (see the
repo root) — a short first-person narrative scene set in Antwerp, 1943. Sara
hides with her son Daniel during a Nazi round-up (razzia); a neighbour,
Mevrouw De Vos, risks herself to protect them. Built with **Godot 3.5**, no
external assets — every mesh, texture, and sound is generated in code.

## Requirements

- **Godot Engine 3.5.x** (the 3.x line, not 4.x — this project uses Godot 3
  node types and GDScript syntax throughout).
- A GPU capable of GLES3 (any GPU from the last ~10 years). The project falls
  back to GLES2 automatically if GLES3 isn't available, though the real-time
  bounced lighting (`GIProbe`) needs GLES3 to bake.
- Linux, since that's the platform this was built and tested for. (Godot 3.5
  itself is cross-platform, so Windows/Mac exports are possible too if you
  ever need them — see below — but this build hasn't been tested on those.)

## Play it (no export needed)

1. Install Godot 3.5: on Debian/Ubuntu-based distros, `sudo apt install
   godot3` gets you a working editor + runtime in one step. Otherwise grab it
   from [godotengine.org/download](https://godotengine.org/download) — pick
   the **3.5.x** release, not 4.x.
2. Open the editor, choose **Import**, and select this `godot/` folder's
   `project.godot` file.
3. Press the **Play** button (▶, top-right) or hit F5. That's it — the game
   runs inside the editor exactly as it would standalone.

You can also skip the editor UI entirely and run it from a terminal:

```sh
godot3 --path /path/to/godot
```

## Building a standalone executable (double-click to play)

This was built and tested in a sandboxed environment with no access to
Godot's own download servers, so **export templates were never downloaded
here** — the project itself is complete and tested, but I couldn't produce a
packaged binary myself. On a normal machine with internet access, this is a
single dialog, not real engine work:

1. Open the project in the Godot 3.5 editor (see above).
2. **Project → Export…**
3. Click **Add…** and choose **Linux/X11**. The first time you do this,
   Godot will prompt to download export templates matching your editor
   version — let it (this needs a normal internet connection, which is the
   one thing this sandbox didn't have).
4. Click **Export Project**, choose a location and filename (e.g. `Rimon`),
   and export. You'll get a single executable file you can double-click or
   run directly — no Godot installation needed to *play* it after that,
   only to build it.
5. (Optional) Repeat with **Windows Desktop** or **Mac OSX** presets if you
   want builds for other platforms — Godot 3.5 supports cross-exporting to
   all three from Linux.

## Project layout

```
godot/
  project.godot          — project settings, autoload registration
  scenes/Main.tscn        — the only hand-authored scene (everything else is
                            built procedurally in code from here)
  scripts/
    main.gd               — bootstraps and wires all systems together
    story.gd               — autoload singleton: the 8-beat story state
                              machine, exposure tracking, 3 endings
    interactable.gd
    interactable_defs.gd   — the interaction contract (10 interactable ids,
                              per-beat availability, prompt text)
    room_builder.gd         — procedural room geometry + set dressing
    lighting.gd             — the candle flicker/tension system + GIProbe
    player_controller.gd    — first-person movement, mouse-look, interact
    soundscape.gd           — procedurally synthesized audio (no sound files)
    ui_controller.gd        — start screen, HUD, choice panel, epilogue
  assets/fonts/            — Liberation Serif (SIL Open Font License 1.1,
                              license text included) — the only external
                              asset in the whole project
```

## Differences from the browser build

Beyond just being a native, installable executable, this version pushes
further than the browser version could:

- **Real bounced light** via Godot's `GIProbe` — the candle's warm light
  genuinely bleeds onto nearby walls, not just a flat falloff (WebGL in a
  browser has no equivalent without a full custom path-tracer).
- **Jewish folk-art visual motifs** — the child's wall drawing and a small
  mizrach-style papercut piece draw on the tradition of Jewish papercut art
  (mizrach/ketubah cutwork), tying visually into the game's title (*rimon*,
  Hebrew for pomegranate).
- A themed UI (bundled serif typeface, warm-amber restrained styling)
  instead of default engine widgets.
- A sparse, restrained emotional audio layer — a few brief tonal touches at
  the warning and at each of the three endings, kept deliberately minimal
  per the game's "no music, or only the sparest" design intent.

## Controls

WASD move · Mouse look · E interact · Shift hold to crouch
