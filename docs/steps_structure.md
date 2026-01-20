# Steps Directory Structure

This document describes the intended directory layout and execution model
for installer steps in **env-installer**.

The structure is designed to:

- Minimise branching logic inside individual shell scripts
- Express scope structurally (platform / distro / architecture / device)
- Preserve deterministic execution order via numeric prefixes
- Keep each step small, obvious, and auditable

---

## Core Principles

1. **Structure over conditionals**  
   Platform- or device-specific behaviour should be expressed by directory
   placement, not large `case` statements inside scripts.

2. **Numeric prefixes define execution order**  
   Filenames are prefixed with a numeric phase identifier (e.g. `010`, `030`, `090`).
   These prefixes control ordering only; they do *not* encode platform or scope.

3. **Directories define scope**  
   The directory path determines *where* a step applies:

   - `steps/` – generic, cross-platform steps
   - `steps/linux/` – Linux-only steps
   - `steps/macos/` – macOS-only steps
   - `steps/linux/arch/` – Arch Linux-specific steps
   - `steps/devices/<device-id>/` – device-specific customisation

4. **Same filename across scopes = same intent**  
   Using the same numeric prefix and filename in different directories
   communicates that the steps represent the same conceptual phase,
   implemented differently per scope.

5. **Guards are safety rails**  
   Lightweight guards (e.g. `require_platform macos`) may be used inside steps
   as defensive checks, but they should not replace structural scoping.

---

## Example Directory Tree

```
steps/
├── 010-env-info.sh
├── 020-core-tools.sh
├── 030-dev-baseline.sh
│
├── linux/
│   ├── 030-install-yt-dlp.sh
│   ├── 040-install-fd.sh
│   ├── 050-configure-sysctl.sh
│   │
│   ├── arch/
│   │   ├── 030-install-yt-dlp.sh
│   │   ├── 040-install-yay.sh
│   │   └── 090-enable-multilib.sh
│   │
│   ├── ubuntu/
│   │   ├── 040-install-snapd.sh
│   │   └── 050-configure-unattended-upgrades.sh
│   │
│   └── proxmox/
│       ├── 090-disable-enterprise-repo.sh
│       └── 095-tune-host-settings.sh
│
├── macos/
│   ├── 020-install-xcode-cli.sh
│   ├── 030-install-homebrew.sh
│   ├── 040-install-yt-dlp.sh
│   ├── 050-configure-macos-defaults.sh
│   │
│   └── arch/
│       ├── aarch64/
│       │   └── 060-install-rosetta.sh
│       └── x86_64/
│           └── 060-skip-rosetta.sh
│
└── devices/
    ├── thinkpad-x240/
    │   ├── 090-disable-touchscreen.sh
    │   └── 095-tune-trackpoint.sh
    │
    ├── mac-mini-m1/
    │   └── 090-enable-power-modes.sh
    │
    └── custom-desktop/
        └── 090-configure-gpu-drivers.sh
```

---

## Ordering Semantics

- Execution order is determined by:
  1. Directory discovery order (generic → platform → distro → arch → device)
  2. Numeric filename prefixes within each scope

- Recommended numbering scheme:
  - Use **three-digit prefixes**: `010`, `020`, `030`, …
  - Leave gaps between numbers to allow insertion of future steps

Examples:

- `030-install-yt-dlp.sh` appears in multiple scopes to represent the same
  conceptual phase across platforms
- `090-*` steps are typically late-stage system tuning or device-specific
  adjustments

---

## Device-Specific Steps

Device-specific steps live under:

```
steps/devices/<device-id>/
```

Guidelines:

- Device IDs should be stable, lowercase, and descriptive
  (e.g. `thinkpad-x240`, `mac-mini-m1`)
- Device steps should *never* modify behaviour for other machines
- These steps are intended to be opt-in and highly targeted

---

## Notes

- This structure is intentionally simple and shell-friendly
- It scales well without introducing heavy tooling
- It is compatible with incremental evolution (e.g. adding arch or distro
  layers later)

The goal is to keep every step understandable in isolation while allowing
complex environment setup to emerge from composition rather than conditionals.
