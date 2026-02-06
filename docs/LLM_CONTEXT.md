# Env Installer – LLM Context & Design Requirements

Inspired by https://github.com/markosamuli/linux-machine/tree/master

---

## Purpose of This Document

This document is a **standalone, complete context file** intended to be provided verbatim to any new LLM chat.

Its goal is to ensure the LLM:

- Fully understands the **intent, constraints, preferences, and architectural direction** of this environment installer
- Produces **consistent, compatible, non‑regressive** suggestions, code, and structure
- Does **not** re‑introduce rejected patterns or unnecessary complexity

This installer is a **core, long‑lived system**, not a throwaway script.

---

# 🔒 Omarchy Safety Requirement (Non‑Negotiable)

When `env_flavor == "omarchy"` the installer MUST:

1. Create a **bootable system snapshot** before running any installs
2. Fail fast if snapshot tooling is unavailable (unless explicitly overridden)
3. Never proceed with installs without snapshot protection enabled

This is implemented via:

```
playbooks/_preflight_omarchy_snapshot.yml
```

Snapshot command:

```
sudo omarchy-snapshot create
```

Reference:

Omarchy System Snapshots — Limine bootable rollback snapshots.

Why this exists:

- Omarchy is a curated Arch derivative
- Blind package upgrades or installs may break the boot environment
- Snapshots provide guaranteed rollback from bootloader

This safety step is treated as **preflight infrastructure**, not a feature.

---

## High-Level Goal

Build a **modular, declarative, fail‑fast environment installer** using Ansible.

Supports:

- Workstations
- Servers
- Containers

Across:

- Debian family
- Arch family
- macOS
- Omarchy (specialized Arch flavor)

---

## Execution Model

- Push‑based execution
- Human or automation triggered
- No background convergence
- Idempotent but not continuously enforced

---

# Core Design Principles

## 1) Intent vs Implementation Separation

Intent:

> What should exist?

Implementation:

> How do we achieve it here?

Profiles + feature flags express intent.

Playbooks + roles implement behavior.

---

## 2) Feature‑Flag‑Driven Design

All installable items use:

```
install_<feature>: true|false
install_<feature>_reason: profile|override|default:false
```

Flags are derived, never hand‑toggled.

---

## 3) Profiles = Primary Interface

Hosts declare profiles:

```
env_profiles:
  - base
  - media
  - dev_cli
```

Profiles expand → features → install flags.

---

## 4) Fail‑Fast on Unknown Profiles

Typos cause hard failure.

Never silently ignored.

---

## 5) Fail‑Fast on Unsupported Platforms

If a feature is enabled but unsupported:

Installer halts immediately.

No silent skips.

---

## 6) Omarchy Platform Handling Rules

Omarchy is NOT treated as generic Arch.

Key rules:

- Omarchy installs must not rely on Arch assumptions
- Snapshot preflight is mandatory
- Risky operations require rollback protection
- Omarchy safety checks run before installs

Future separation includes:

- Dedicated package installer path
- No blind `pacman -Syu`
- Flavor‑specific safeguards

---

## 7) Modularity Over Monoliths

Prefer:

- Explicit includes
- Thin feature files
- Roles for complexity

Avoid giant conditional playbooks.

---

## 8) Simplicity Over Cleverness

Prefer readable YAML over abstraction.

Transparency beats DRY when auditing installs.

---

## Structural Expectations

```
playbooks/
  main.yml
  _derive_features.yml
  _assert_supported.yml
  _preflight_omarchy_snapshot.yml
  _install_features.yml
```

Snapshot preflight always runs before installs on Omarchy hosts.

---

## Plan Derivation Requirements

The derive step must:

- Normalize inputs
- Validate profiles
- Expand features
- Produce install flags
- Record reasons
- Output plan summary

---

## Secrets Handling

Secrets are injected externally:

- Vault
- Environment
- Extra‑vars

Never stored in repo.

---

## Idempotency Expectations

- Safe re‑runs required
- Package modules preferred
- Command usage minimized
- Failures surfaced early

---

# Summary Mental Model

Profiles → Intent

Feature Flags → Plan

Preflight → Safety

Playbooks → Orchestration

Roles → Implementation

Omarchy → Snapshot Protected

Unsupported / Unsafe → Fail Fast
