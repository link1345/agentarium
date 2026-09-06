# Palette generation and rendering

Generate colored fur/material regions in a single narrow hue family, neutral face patches, dark outlines, and no gradients crossing the neutral/color boundary. Attached canonical artwork controls exact hues in every row. Ask for small teal accents only if they should remain fixed while fur changes.

The bundled `scripts/palette_swap.py` deterministically exports a variant from the finished generated atlas. Run it using the Python executable returned by `load_workspace_dependencies`:

```text
<PYTHON> <SKILL_DIR>/scripts/palette_swap.py <pet>/spritesheet.webp --output <pet>/mint.webp --source-hue 0.72 --target #70DCC5
```

Hue values are normalized to [0, 1). Select source hue from the actual finished atlas. The shader/export contract uses shortest cyclic hue distance <= 0.11, saturation >= 0.12 and value >= 0.45. Replace hue with target hue plus source hue offset; retain original saturation, value, and alpha. White/gray patches and dark outlines stay unchanged. This does not add, remove, or rearrange frames. Verify exact alpha equality and preserved atlas dimensions after each exported variant.

Suggestions: lavender #B7A0ED, mint #70DCC5, peach #F3AE86, sky #8EB9F0. These are hue targets, not full-color tint multipliers. For one character per concurrent thread, map stable thread IDs to palette choices so colors do not change when ordering changes.

