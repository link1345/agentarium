# Source and modifications

The deterministic hatch-pet scripts and original workflow/reference documents in this skill were copied from the installed `hatch-pet` skill on 2026-09-06 and are redistributed under the accompanying Apache License 2.0 (`LICENSE.txt`). Original license text is preserved. The source bundle did not provide a separate NOTICE file.

Agentarium modifications, 2026-09-06:

- Added this host-neutral `SKILL.md`, palette workflow and deterministic `scripts/palette_swap.py`, with selective HSV color-family replacement and exact alpha preservation.
- Adapted workflow directory examples to this portable skill and documented ChatGPT MCP `get_pet_recipe` use.
- Modified `scripts/extract_cardinal_anchors.py` to add `--method components` for complete-pose extraction when equal slot boundaries cut intact source art, plus `--single-direction` for approved cardinal-reference repairs. These preserve source pixels and clipping gates; they do not generate art or patch final look cells.
- Modified `scripts/derive_running_left_from_running_right.py` with `--method components` to mirror complete original gait pose groups in temporal order when equal-slot mirroring would cut neighboring tails. Only the already-approved right-to-left mirror derivation is affected.
- Clarified the v2 neutral look cell at row 0, column 6 in the animation reference.

Generated Lumi character art is original native image-generation output, not artwork copied from hatch-pet. Its prompts, provenance and QA are separate under the project pet-production artifacts.

- 0.3: Replaced the default chroma workflow with native RGBA generation and alpha-preserving assembly; palette swaps are applied by the runtime shader. Legacy scripts remain for compatibility.
