# SILENT WEIGHT — Godot 4.7.2 Game Development Report

**Envisage 15.0 Coordinator Application — GameDev Vertical (Question 5)**

| Field | Details |
| :--- | :--- |
| **Project Title** | **SILENT WEIGHT** (`inside_lab`) |
| **Genre** | 2.5D Atmospheric Kinematic Puzzle-Platformer (*Playdead's INSIDE / LIMBO* inspired) |
| **Engine & Physics** | Godot 4.7.2 Stable (Forward+ Renderer with `iGPU LIGHT` Scaler, Jolt Physics 3D) |
| **Target Hardware** | Tested & Optimized for Intel UHD Graphics / Intel Core i5-13420H (**Locked 60 FPS**) |
| **GitHub Repository** | [https://github.com/Vex619/Silent-Weight](https://github.com/Vex619/Silent-Weight) ([Mirror: Vex619/Ashwood](https://github.com/Vex619/Ashwood)) |
| **Author** | Vex619 |

---

## 1. Executive Summary & Game Scope

**SILENT WEIGHT** is a complete, playable 3-Act 2.5D atmospheric puzzle-platformer spanning a continuous **325-meter industrial-to-wilderness world (`X = -22m` to `X = +302m`)** with 7 seamless checkpoints and an ending sanctuary sequence. Rather than relying on HUD text prompts or dialogue, the game communicates mechanics through environmental lighting, physical weight, and reactive acoustics:

- **Act I — The Silent Bunker (`X = -22m..56m`)**: The player awakens inside a brutalist concrete facility patrolled by ceiling-rail **Blind Auditor Drones** that track both visual searchlight cones and acoustic footstep decibels. Players must creep silently in the shadows (`Shift`), mantle multi-tiered ledges, and push utility crates onto floor pressure plates to cut off lethal high-pressure steam vents and unlock blast doors.
- **Act II — What Lurks in the Mud (`X = 56m..185m`)**: Transitioning through a rusted drainage pipe and a timed hydraulic **Sluice Gate** crusher, the player enters a waist-deep **Swamp Marsh** stalked by a submerged **Mire Stalker**. The creature is repelled only by the warm volumetric glow of a **220 kg Amber Beacon Crate**, forcing the player to push and hoist the heavy crate across deep mud, water troughs, and shoreline banks.
- **Act III — The Harvester's Field (`X = 185m..302m`)**: Emerging into an open windswept field of **3,000 GPU-instanced tall grass blades**, a towering background **Harvester Titan** fires periodic gale-force shockwaves every `6.0s`. The player must advance up the **Climax Slope** by positioning the `220 kg` crate as a mobile wind-shadow shield, outrun a quad-legged **Hound Pursuer**, and breach the **Sanctuary Resonance Vault**.

---

## 2. How Core Concepts Were Implemented

### A. 11-State Hierarchical Player Controller (`src/player/player_controller_3d.gd`)
- **State Machine Architecture**: Engineered a deterministic `CharacterBody3D` Hierarchical State Machine (HSM) constrained to the `Z = 0` 2.5D plane across 11 states: `Idle`, `CreepWalk`, `Run`, `JumpStart`, `AirborneRise`, `AirborneFall`, `HardLand`, `PushPullHeavy`, `WadingSwamp`, `ClimbLedge`, and `Dead`.
- **Precision Platforming Feel**:
  - **Coyote Time (`0.10s`)**: Allows jump initiation briefly after stepping off a ledge lip.
  - **Jump Input Buffering (`0.12s`)**: Queues jump inputs pressed slightly before floor touchdown and executes them on the exact landing frame.
  - **Variable Jump-Cut Gravity**: Applies `1.85x` gravity when the jump button is released early during ascent and `1.55x` gravity during descent for weighted, non-floaty arcs.
  - **Second-Order Biomechanical Inertia (`src/core/second_order_dynamics.gd`)**: Drives torso pitch lean, head look-ahead, and landing compression using critically damped second-order differential equations (`f = 2.8 Hz, zeta = 0.82`).
- **Contact-Locked 3-Phase Ledge Mantling**:
  - Uses dual forward raycasts (`ClimbLedgeProbe` at chest height and `ClimbClearanceProbe` at head height) to compute the exact world-space ledge corner `(edge_x, top_y)`.
  - Drives a 3-phase climb (`Phase 1: Reach & Hang [0.00..0.32]` -> `Phase 2: Pull-Up Over Edge [0.32..0.72]` -> `Phase 3: Plant Foot & Stand [0.72..1.00]`) where the player's hands remain world-locked to the ledge lip until chest clearance is achieved.
- **Mass-Scaled Heavy Object Pushing (`220 kg` `RigidBody3D`)**:
  - When holding `E` (`grab`) or pushing against a `RigidBody3D` in group `pushable_heavy`, `PlayerController3D._physics_process()` applies mass-proportional horizontal impulses along the contact normal while pitching the character's spine forward into a high-strain bracing posture.
- **Procedural Damage Flinch & Floor-Clamped Death Collapse**:
  - `trigger_damage_flinch()` applies an upper-torso backward recoil (`-24 deg`), raises a defensive forearm, pulses the post-process vignette (`+0.35`), and synthesizes a sharp intake gasp.
  - `trigger_death_collapse()` transitions into `&"Dead"`, keeps gravity active until floor contact, rotates the body onto the ground (`85 deg`), and clamps `_visual_root.position.y >= +0.18m` so zero mesh geometry ever clips beneath the floor plane before fading into a **108-quote non-repeating atmospheric death screen**.

### B. Second-Order Spring-Damper 2.5D Camera Rig (`src/camera/dynamic_camera_rig_3d.gd`)
- Implements analytical second-order spring dynamics (`zeta = 1.0` critical damping) with velocity look-ahead (`1.45m` horizontal lead).
- Blends smoothly between overlapping `CameraRegionVolume3D` (`Area3D`) triggers that dynamically adjust camera distance (`6.8m` claustrophobic bunker -> `11.5m` wide Harvester field), vertical offset, FOV (`38 deg` to `52 deg`), and world-space X/Y framing clamps.
- Applies 3D rotational trauma shake (`pitch`, `yaw`, `roll`) driven by Harvester shockwaves, hard landings, and Sluice Gate impacts.

### C. 3-Layer Playdead Foley & Acoustic Reverb Engine (`src/audio/foley_audio_director_3d.gd`)
- Inspired by Martin Stig Andersen's audio architecture for *INSIDE*:
  - **Layer 1 (Transient Strike)**: Immediate heel/toe impact sample (`concrete_strike_*`, `swamp_strike_*`, `grass_strike_*`).
  - **Layer 2 (Velocity-Bucketed Body/Scuff)**: Grounded grit, mud slosh, or grass swish selected dynamically by horizontal speed (`Creep`, `Walk`, `Run`, `Land`).
  - **Layer 3 (Delayed Release/Suction Tail)**: Fires `45 ms` after foot plant (`swamp_tail_suction_*`, `concrete_tail_release_*`, `grass_tail_rustle_*`).
- **1:1 Visual-to-Audio Stride Synchronization**: Both the skeletal leg swing and `stride_phase_triggered` audio signal are driven by the exact same `_stride_phase` angle, firing footsteps at `PI * 0.5` (left foot nadir) and `PI * 1.5` (right foot nadir).
- **Shoe Wetness Carry-Over & Reverb Zones**: Stepping into `swamp_deep_mud` saturates shoe wetness to `100%`, blending wet suction layers onto dry concrete steps and decaying by `-14%` per dry step. `AcousticReverbZone3D` volumes smoothly interpolate the `Foley` audio bus's `AudioEffectReverb` wet/room size and `AudioEffectLowPassFilter` cutoff frequency.

### D. Custom GLSL Shaders & GPU-Instanced Foliage (`src/shaders/*.gdshader`)
- **`inside_post_process.gdshader`**: Single-pass full-screen shader performing monochromatic S-curve contrast grading, radial vignette, edge chromatic aberration, and subtle animated film grain.
- **`swamp_surface.gdshader`**: Reactive water shader computing dual concentric ripple interference rings around the live `player_world_pos` and submerged `stalker_world_pos` uniforms.
- **GPU-Instanced Tall Grass (`Act3_TallGrassField`)**: A single `MultiMeshInstance3D` rendering `3,000` segmented grass blade tufts across Act III (`X = 185m..300m`) with zero CPU draw-call overhead (`SHADOW_CASTING_SETTING_OFF`). Its custom vertex shader bends blades continuously in the wind, parts blades radially around the player and `220 kg` crate, and flattens the field during Harvester shockwave gusts.

---

## 3. Optimization for Intel UHD Graphics (`Core i5-13420H` — Locked 60 FPS)

Running Godot 4.7.2's Forward+ renderer at `1920x1200` with volumetric fog, SSR, SSAO, SDFGI, and 4-split directional + positional shadow maps initially produced **31.35 ms frame times (~31 FPS)** on the integrated Intel UHD GPU. To achieve a rock-solid **60 FPS (`<16.6 ms`)** without sacrificing the Playdead chiaroscuro aesthetic, we engineered a runtime graphics scaler (`F4` toggle: `iGPU LIGHT` default vs. `RTX ULTRA`) paired with a low-overhead `F3` telemetry profiler (`src/core/perf_hud_overlay.gd`):

1. **Environment & Shadow-Map Gating (`narrative_director.gd`)**:
   - In `iGPU LIGHT` mode, dynamically disables `volumetric_fog_enabled`, `ssr_enabled`, `ssao_enabled`, `ssil_enabled`, `sdfgi_enabled`, and `glow_enabled` on the active `World3D.environment` (relying instead on zero-cost additive `fake_volumetric_shaft.gdshader` beams and distance fog).
   - Disables real-time shadow-map rendering (`shadow_enabled = false`) across all `SpotLight3D`, `OmniLight3D`, and `DirectionalLight3D` nodes.
2. **Dynamic 3D Resolution Scaling (`0.65x` Bilinear)**:
   - Configures `Viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR` and `scaling_3d_scale = 0.65` in `iGPU LIGHT` mode, reducing 3D fragment shader invocations by **58%** while keeping 2D overlays crisp at native resolution.
3. **Act-Based Light/Particle/AI Gating**:
   - Dynamically disables off-screen `Light3D`, `GPUParticles3D`, `FogVolume`, and distant monster AI outside the active Act (`_update_act_optimizations()`), while keeping all `StaticBody3D` physics colliders active.
4. **4 Hz Cached Telemetry HUD (`perf_hud_overlay.gd`)**:
   - Eliminated per-frame `RichTextLabel` BBCode parsing and font glyph shaping by throttling HUD updates to `4 Hz` (`0.25s`) with string-equality dirty checks and starting the HUD hidden (`F3` toggle).

---

## 4. Problems Encountered & Engineering Solutions

| # | Problem Encountered | Root Cause | Engineering Solution Implemented |
| :- | :--- | :--- | :--- |
| **1** | **iGPU Frame-Time Bottleneck (`31.35 ms` / `31 FPS` at `1920x1200`)** | Positional/directional shadow maps, `100%` 3D viewport scaling, and per-frame BBCode text reshaping saturated Intel UHD fill-rate and CPU layout time. | Added `F4` `iGPU LIGHT` mode: gated all `Environment` GI/fog/SSR passes and `Light3D` shadows, enabled `0.65x` bilinear 3D scaling, and throttled `PerfHudOverlay` BBCode reshaping to `4 Hz` (**achieving locked `60 FPS` / `~13.8 ms`**). |
| **2** | **Infinite Fall Through Floor at Act Boundaries (`Y = -24 m/s`)** | Setting `process_mode = PROCESS_MODE_DISABLED` on inactive Act roots disabled `StaticBody3D` floor colliders in Godot 4's `PhysicsServer3D`. | Kept all structural roots at `PROCESS_MODE_INHERIT`, built a continuous 300m floor safety bridge (`X = -25m..310m`), gated only lights/particles/AI by Act, and added an abyss kill-plane failsafe (`Y < -6.0m`). |
| **3** | **Footstep Audio Desync & Dry Concrete Suction Tails** | Independent step timers drifted out of phase with skeletal leg animations, and `45 ms` delayed L3 tails fired after stopping or played wet suction at `0%` wetness. | Drove both leg transforms and `stride_phase_triggered` from a single `_stride_phase` variable (`PI * 0.5` / `PI * 1.5`), pre-biased `_stride_phase` `0.12 rad` before contact on walk start, cancelled pending L3 tails on `Idle`, and gated wet overlays strictly on `wetness > 0.05`. |
| **4** | **Mid-Air Ledge Grabbing & Floor Clipping on Damage/Death** | Ledge probes triggered without forward wall intent or on moving crates, and negative vertical hip offsets pushed character geometry below `Y = 0` on death. | Required active horizontal input toward the wall + vertical drop-in window for ledge grabs, implemented 3-phase contact-locked mantling, and clamped `_visual_root.position.y >= +0.18m` during death collapse. |
| **5** | **220 kg Beacon Crate Wedging Against Swamp Exit Wall** | Water drag and vertical step geometry prevented pushing the heavy `RigidBody3D` crate out of the Act II Swamp Marsh onto the dry bank. | Enabled full-impulse jumps and crate mantling from `WadingSwamp`, added an angled shoreline ramp collider at `X = 160.2m`, and implemented an automatic proximity hoist when the crate reaches within `1.5m` of the bank. |

---

## 5. Where and How Resources Were Obtained

All project assets follow a **100% CC0 Public Domain & Procedural In-Engine Pipeline**:

1. **3D Character Rig & Animations (`assets/models/character/`, `resources/animations/`)**:
   - Base low-poly humanoid mesh (`animated_human.fbx`) obtained from **Quaternius CC0 Universal Base Characters** ([quaternius.com](https://quaternius.com/), CC0 1.0 Public Domain).
   - Retargeted, scaled, and shaded with a custom desaturated Playdead palette (`inside_boy_palette.png` / `inside_boy_material.tres`) via automated Godot scripts (`tools/build_character_scene.gd`, `tools/create_animations.gd`, and `src/player/player_animator.gd`).
2. **Mastered Foley & Ambience Audio (`assets/audio/foley/`, `tools/master_foley_library.py`)**:
   - Raw foley recordings (concrete footsteps, mud sloshes, grass rustles, metal impacts, wind drones, and breathing stems) sourced from **Freesound.org under CC0 1.0 Public Domain** licenses.
   - Processed offline via our custom Python DSP script (`tools/master_foley_library.py`) into **75 velocity-bucketed `.wav` files** with Butterworth high/low-pass filtering, peak/RMS normalization, transient shaping, and phase-aligned loop crossfading.
   - **Real-Time Procedural Synthesis**: *Blind Auditor Drone* rotor hum (`110 Hz + 220 Hz` harmonics), periodic `2.4 kHz` sonar pings, and player damage/death acoustic shocks are generated in real time with zero external samples using Godot's `AudioStreamGenerator`.
3. **Environment Geometry, Shaders & VFX (`scripts/narrative_director.gd`, `src/shaders/`)**:
   - All 300 meters of industrial architecture, pipes, sluice gates, drones, the Mire Stalker, the Harvester Titan, the Hound Pursuer, the 3,000-tuft instanced grass field, and all GLSL spatial/canvas shaders were authored **100% procedurally in-engine**.

---

## 6. Repository Commits (Milestone Log)

The development progression is tracked across **4 structured milestone commits** on GitHub:

- **Commit 1 [`ab15fd4`]** — `feat(core): implement 2.5D HSM player controller, coyote/buffer kinematics, 3-phase ledge climb, and spring-damper camera rig`
  - *Scope*: Initial Godot 4.7.2 project setup (`project.godot`, Jolt Physics 3D), 11-state `PlayerController3D` with `0.10s` coyote time, `0.12s` jump buffering, contact-locked 3-phase ledge mantling, `PlayerAnimator` skeletal/procedural blending, `SecondOrderDynamics` solver, `DynamicCameraRig3D` + `CameraRegionVolume3D`, and `PerfHudOverlay`.
- **Commit 2 [`14f4164`]** — `feat(audio-vfx): add 3-layer Playdead foley engine, acoustic reverb zones, and custom GLSL atmospheric/water shaders`
  - *Scope*: 3-layer velocity-bucketed `FoleyAudioDirector3D`, `SurfaceAudioProfile` resources (`concrete_dry`, `swamp_deep_mud`, `field_tall_grass`), 75 mastered CC0 `.wav` foley/breath/ambience stems, `AcousticReverbZone3D` bus interpolation, and custom GLSL shaders (`inside_post_process.gdshader`, `swamp_surface.gdshader`, `fake_volumetric_shaft.gdshader`).
- **Commit 3 [`b6427b2`]** — `feat(world): build 300m 3-Act narrative world, acoustic drone/stalker/harvester AI, GPU grass field, and iGPU 60-FPS scaler`
  - *Scope*: Full 300m 3-Act world assembly (`NarrativeDirector`, `test_lab_inside.tscn`), acoustic *Blind Auditor Drones* with `AudioStreamGenerator` rotor synthesis, *Mire Stalker* & `220 kg` Beacon Crate repulsion puzzle, *Harvester Titan* shockwaves, `3,000`-blade `MultiMeshInstance3D` interactive tall grass, procedural damage flinch + 108-quote death collapse, and the `F4` Intel UHD 60-FPS optimizer.
- **Commit 4 [`HEAD`]** — `docs(report): add comprehensive Game Development Report, architecture docs, and milestone commit log`
  - *Scope*: Complete engineering documentation (`GAME_DEVELOPMENT_REPORT.md`, `README.md`) and visual direction studies (`art/`).
