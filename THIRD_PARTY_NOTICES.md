# Third-party notices

Agentarium's application code and vector pet artwork are MIT licensed; see LICENSE.

- **Godot Engine 4.7** — MIT and bundled third-party components. Copyright Godot Engine contributors and Juan Linietsky, Ariel Manzur. Full engine and dependency license notices: https://godotengine.org/license/ . Engine source: https://github.com/godotengine/godot/tree/4.7-stable .
- **Gua 1.0.10** — MIT. Copyright (c) 2026 link1345. Full license: `addons/gua/LICENSE`. Source: https://github.com/link1345/gua . The Windows GDExtension includes godot-cpp; see the Godot license above.
- **System fonts** are resolved from the user's operating system, not redistributed. Agentarium does not bundle Microsoft fonts.
- **CPython 3.12 runtime** — Python Software Foundation license and bundled notices, included at `runtime/python/LICENSE.txt`. Used only by the local read-only Codex synchronization helper. SQLite is public domain; libffi's MIT notice is included at `runtime/python/LICENSE-libffi.txt` and `docs/licenses/libffi.txt`.
- **Lumi generated artwork** — original character generated for Agentarium with the bundled `create-agentarium-pet` workflow. The sprite layout is compatible with Codex/ChatGPT pets; no built-in OpenAI character artwork is redistributed. Source provenance and visual QA are retained in the development artifacts.
- **ChatGPT app dependencies** — MCP TypeScript SDK (MIT), Zod (MIT), fflate (MIT), sharp (Apache-2.0, with libvips and native dependency notices in its installation). The source archive includes dependency declarations and lockfile; it does not redistribute node_modules.
- **Bundled pet-generation workflow** — adapted from the user's installed hatch-pet skill; Apache-2.0 license is included at `agentarium-codex-app/skills/create-agentarium-pet/LICENSE.txt`.

Dependencies were copied from the official archives with SHA-256 verification; see `scripts/setup.ps1` for release URLs and hashes. Gua's inspector is off by default and binds to loopback only when explicitly enabled with `-Gua` / `GUA_BRIDGE_PORT`.
