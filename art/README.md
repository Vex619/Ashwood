# Visual Studies & Atmospheric Direction (`SILENT WEIGHT`)

This directory archives visual direction studies, palette textures, and in-engine chiaroscuro lighting captures for **SILENT WEIGHT** (Godot 4.7.2).

## Included Studies
- `bunker_chiaroscuro_telemetry.png` — Early Act I (*The Silent Bunker*) chiaroscuro silhouette study with live `F3` acoustic & second-order spring telemetry overlay.
- `inside_boy_palette.png` — Desaturated crimson-and-slate color palette texture applied to the protagonist rig (`player_boy_character.tscn`) so the character reads cleanly against dark industrial concrete, murky swamp water, and wind-swept olive grass.

## Shader & Lighting Pipeline
- **Post-Processing (`src/shaders/inside_post_process.gdshader`)**: Single-pass canvas shader applying Playdead-inspired S-curve contrast, 78% desaturation, radial vignette, chromatic aberration at frame edges, and animated film grain.
- **Volumetric Light Shafts (`src/shaders/fake_volumetric_shaft.gdshader`)**: Fresnel-faded additive light cones with scrolling dust noise and depth-fade attenuation.
- **Reactive Swamp Water (`src/shaders/swamp_surface.gdshader`)**: Dual-source concentric wave displacement and normal perturbation driven by real-time player and *Mire Stalker* world coordinates.
