---
name: create-agentarium-pet
description: Generate an original palette-swap-ready animated character for Agentarium and Codex pets, with a compatible v2 sprite atlas and full visual QA.
---

# Create an Agentarium pet

Read `references/native-alpha-workflow.md` completely. It is the current authoritative generation and QA workflow. Generate actual transparent RGBA backgrounds in the image generation tool itself; preserve that alpha during assembly. Never request chroma-key backgrounds or remove a colored background afterward. The older `hatching-workflow.md` and chroma scripts remain only for historical compatibility and are not the default workflow. Resolve `SKILL_DIR` to this skill directory, never to an installed absolute path. Do not install into a user's pet folder unless requested; package under the chosen project `assets/pets/<pet-id>/`.

Use this skill in ChatGPT or Codex. When the connected Agentarium MCP app exposes `get_pet_recipe`, call it first to obtain the character recipe and palette contract. Use the host's native image generation tool (and its installed imagegen skill when present); no API key is required for native generation. API fallback requires explicit user consent. All new animation rows must be generated from the canonical reference; do not fabricate animation by duplicating or transforming still frames. The only permitted derived animation is approved per-frame running-right to running-left mirroring.

Before executing Python on a host exposing `load_workspace_dependencies`, call it and use the exact returned Python executable. On other hosts, use the provided shell/Python execution environment with Pillow. If shell execution is unavailable, deliver the recipe and generated source strips for processing on a capable host; do not claim an assembled compatible atlas. Keep prompts, selected source provenance, and QA in `artifacts/pet-production/<pet-id>/` so the generation is reviewable. The bundled workflow's Codex examples are examples only: resolve all files against the chosen project and this skill, never require a particular home directory or operating system.

Choose a compact original mascot with clean color regions. Palette swapping needs a dominant colored fur/material family, neutral white/gray regions, and dark outlines. Prefer lavender fur with neutral white face and dark ink eyes. Generate just this canonical palette, not separately generated color variants. Record source hue, tolerated hue distance, and suggested replacement colors in `palette.json`. Agentarium changes colors at display time with a shader, preserving luminance, saturation, alpha, outlines, and whites; never tint the entire texture. Precolored ZIP exports are optional compatibility outputs only.

Final deliverables: `spritesheet.webp` (1536 by 2288, 8 columns by 11 rows, 192 by 208 cells), `pet.json` containing `spriteVersionNumber: 2` and relative `spritesheetPath`, `palette.json`, generation prompts/provenance, and all mandatory deterministic and independent visual QA artifacts. Standard 8 by 9 atlases are intermediate output, not a new v2 pet. Read `references/animation-rows.md` for exact counts.

If cardinal equal-slot extraction cuts an otherwise complete, separated source pose, use the bundled `extract_cardinal_anchors.py --method components`. This recovers full original pose groups, keeps their left-to-right order, and checks original canvas clipping; it does not relax the clipping gate or alter artwork. If groups touch or cannot be recovered, repair the source visual instead.

For an individually generated cardinal anchor repair, the same extractor accepts `--single-direction 000` (or 090, 180, 270). Recompose the four approved anchors before regenerating a complete look row. Never place an individual anchor repair directly into the final look atlas. If label-aware reviewers describe upright anatomy instead of a visible up/down gaze, treat that as insufficient evidence and use blind axis review to decide the cardinal gate.

When the approved running-right source has unevenly spaced complete poses, use `derive_running_left_from_running_right.py --method components` with explicit mirror approval. It mirrors each original full pose group in temporal order, avoiding equal-slot cuts through neighboring tails. Re-extract and review the entire leftward row afterward.

Report only verified outputs. Do not claim generated artwork or successful QA when generation is blocked. Keep a four-step visible progress checklist: preparation, base look, poses, assembly and QA.
