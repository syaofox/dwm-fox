> **Inherited from upstream.** This document was written for dwm-titus on
> Fedora and is retained for provenance and design rationale. It is **not**
> authoritative for dwm-fox, which targets Debian and Ubuntu. For what differs
> on this platform, and why, read [`MIGRATION.md`](MIGRATION.md) — that document
> takes precedence. For the Ubuntu Server session contract, read
> [`AGENTS.md`](AGENTS.md).

# Fedora 0.7.2 Roadmap

## Current scope

Address issues #347, #344, #346 and #345 in one ready-for-review PR, as requested
on 2026-09-24. Version 0.7.2 covers the initial Fedora image update workflow,
DNF defaults and mirror measurement, and offline fastfetch provisioning.
Merge, tag publication, release assets and live deployment are outside this PR.

## Implementation and qualification

1. Audit effective Fedora 44 DNF5 configuration and provision conservative,
   interactive defaults without replacing administrator overrides.
2. Include fastfetch and mirror-measurement runtime dependencies in both images.
3. Offer the initial update after repository access, measure trusted mirrors,
   authorize a visible transaction, preserve retry, and persist only success.
4. Validate ordering, mirror fallback and security, actual DNF prompts, clean
   Fedora build/staged installation, image invariants and desktop behavior.
5. Run repository gates and independent review, document exact image-validation
   limits, and publish a ready-for-review PR against main.

Prior desktop-update work is documented in [DESKTOP-UPDATES.md](docs/DESKTOP-UPDATES.md)
and PR #318. Preserve earlier qualification in
[P8-QUALIFICATION.md](docs/P8-QUALIFICATION.md).

Exit: all four issue behaviors are implemented; validation evidence distinguishes
focused/container/runtime checks from full offline image qualification. Do not
claim a released or hardware-qualified image from static checks alone.
