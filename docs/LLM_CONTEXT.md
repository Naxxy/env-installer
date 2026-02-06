# Env Installer – LLM Context & Design Requirements

Inspired by https://github.com/markosamuli/linux-machine/tree/master

## Purpose of This Document

This document is a **standalone, complete context file** intended to be provided verbatim to any new LLM chat.

Its goal is to ensure the LLM:

- Fully understands the **intent, constraints, preferences, and architectural direction** of this environment installer
- Produces **consistent, compatible, non-regressive** suggestions, code, and structure
- Does **not** re-introduce rejected patterns or unnecessary complexity

This installer is a **core, long-lived system**, not a throwaway script. Treat it accordingly.

---

## High-Level Goal

Build a **modular, declarative, fail-fast environment installer** using **Ansible** as the execution engine.

The system must support:

- Workstations
- Servers
- Containers

It must scale across:

- Multiple operating systems (initially Debian-family, Arch-family, macOS)
- Multiple device types (laptop, desktop, homelab server, VPS, container)

The installer should be:

- Predictable
- Explicit
- Convention-driven
- Easy to reason about
- Safe to re-run (idempotent)

---

## Execution Model (Explicit)

- This installer is **push-based**, not agent-based
- It is executed manually by a human or explicitly-invoked automation
- It is **not** continuously enforcing state
- Idempotency matters, but perpetual convergence is **not assumed**
- There is no background daemon, cron job, or `ansible-pull` loop

This is a deliberate design choice to preserve transparency and control.

---

## Core Design Principles (Non-Negotiable)

### 1) Intent vs Implementation Separation

- **Intent** is expressed declaratively via profiles and derived feature flags
- **Implementation** lives in playbooks and roles
- OS / distro / platform logic must *never* leak into intent declarations

Intent answers:

> “What should exist on this system?”

Implementation answers:

> “How do we achieve that on *this* platform?”

---

### 2) Feature-Flag-Driven Design

All installable capabilities are represented as **feature flags**.

Convention:

```yaml
install_<feature>: true|false
install_<feature>_reason: "profile" | "override:true" | "default:false"
```

Examples:

```yaml
install_netbird: true
install_mpv: true
install_slack: false

install_netbird_reason: "profile"
install_slack_reason: "default:false"
```

Feature flags:

- Are the *only* way to enable installs (they are **derived**, not hand-toggled per-host)
- Must be easy to audit and grep (`install_` prefix)
- Are produced by a deterministic “derive” step

---

### 3) Profiles Are the Primary User Interface

Users do **not** manually toggle dozens of flags per machine.

Instead, machines declare **profiles**, and profiles expand into feature flags.

Example:

```yaml
env_profiles:
  - base
  - media
  - dev_cli
```

Profiles:

- Are named sets of feature flags
- Are composable
- Live centrally (not duplicated per host)
- Can overlap freely

The system derives:

- `env_features_from_profiles` (expanded plan)
- `install_*` booleans (final plan)
- `install_*_reason` strings (why)

---

### 4) Fail-Fast on Unknown Profiles

If a host specifies a profile that does not exist in the catalog:

✅ **FAIL HARD**  
❌ Do NOT silently ignore  
❌ Do NOT warn and continue

The failure should list unknown profile names and valid profile names.

This prevents typos from silently producing an incomplete install plan.

---

### 5) Fail-Fast on Unsupported Platforms

If a feature flag is enabled but the current platform is not supported:

✅ **FAIL HARD**  
❌ Do NOT silently skip  
❌ Do NOT warn and continue

Desired error shape:

```
install_slack=true but Slack is unsupported for pkg_family=arch flavor=omarchy.
Either disable this feature or add platform support.
```

This prevents configuration drift and false confidence.

---

### 6) Modularity Over Monoliths

Avoid giant monolithic playbooks or huge conditional trees.

Prefer:

- One “main” orchestration playbook
- Explicit feature task files
- Roles for complex installs

---

### 7) Simplicity Over Cleverness

Strongly prefer:

- Boring Ansible conventions
- Readable YAML
- Explicit lists
- Repetition over abstraction when clarity wins

Avoid:

- Meta-playbooks that obscure flow
- Deep Jinja logic
- Custom DSLs

---

### 8) Convention Over Custom Frameworks

Use established Ansible patterns:

- `inventory/hosts.yml`, `inventory/host_vars/<host>.yml`
- `inventory/group_vars/all.yml`
- `playbooks/main.yml`
- `roles/<role>/tasks/main.yml`

This repo keeps shared variables in **`inventory/group_vars/all.yml`**.

---

## Structural Expectations (This Repo)

```text
env-installer/
├── README.md
├── ansible.cfg
├── docs/
│   ├── LLM_CONTEXT.md            # (this file)
│   └── env-installer-add-feature-guide.md
├── inventory/
│   ├── hosts.yml
│   ├── group_vars/
│   │   └── all.yml
│   └── host_vars/
│       ├── thinkpad-x240.yml
│       ├── macbook-2019.yml
│       └── work_macbook.yml
├── playbooks/
│   ├── main.yml
│   ├── _derive_features.yml
│   ├── _assert_supported.yml
│   ├── _install_features.yml
│   └── features/
│       ├── install_mpv.yml
│       ├── install_brave.yml
│       ├── install_netbird.yml
│       ├── install_jq.yml
│       ├── install_yt_dlp.yml
│       ├── install_magic_wormhole.yml
│       └── install_lazyvim.yml
└── roles/
    ├── install_packages/
    │   └── tasks/
    │       ├── main.yml
    │       ├── arch.yml
    │       ├── debian.yml
    │       └── macos.yml
    └── netbird/
        ├── defaults/main.yml
        ├── meta/main.yml
        └── tasks/
            ├── main.yml
            ├── assert.yml
            ├── configure.yml
            ├── arch.yml
            ├── debian.yml
            └── macos.yml
```

Notes:

- **Shared vars** live in `inventory/group_vars/all.yml` (known features, profile catalog, support matrix, package name mapping).
- **Host identity** is explicit per host in `inventory/host_vars/<host>.yml`:
  - `env_pkg_family`: `arch|debian|macos`
  - `env_flavor`: `arch|omarchy|ubuntu|debian|macos|...`
  - `env_profiles`: list of profiles for that host.

---

## Simple vs Complex Installs

### Simple Install

A **simple install**:

- Uses package manager installs
- Has minimal OS variance
- Does NOT require its own role

Implemented as:

- `playbooks/features/install_<feature>.yml` that calls `roles/install_packages`

Examples:

- `mpv`
- `jq`
- `yt-dlp`
- `magic-wormhole`

### Complex Install

A **complex install**:

- Has OS-specific repos / install mechanisms **and/or**
- Requires post-install configuration **and/or**
- Has platform-specific differences

Implemented as:

- A dedicated role under `roles/<feature>/...`
- A thin feature task file that calls the role

Example:

- `netbird`

### Hybrid Example (Non-package config)

Some features are not “packages” but still belong in the feature system.
Example: **LazyVim**.

Pattern:

- Install dependencies (packages) via `install_packages`
- Then perform explicit config actions (e.g. git clone into `~/.config/nvim`)
- Must be **safe** (avoid clobbering existing user config)

---

## Platform Handling Rules

- Platform identity is explicit per host via `env_pkg_family` and `env_flavor`
- Support matrix lives in `env_feature_support`
- If enabled but unsupported: **fail fast** (enforced in `_assert_supported.yml`)

---

## Plan Derivation Requirements

The derive step (`playbooks/_derive_features.yml`) must:

- Normalize inputs (`env_profiles`, `env_feature_overrides`)
- **Fail fast** on unknown profiles (typos)
- Expand profiles into `env_features_from_profiles`
- Derive **all** `install_*` flags for every entry in `env_known_features`
- Produce `install_*_reason` for each feature
- Include a debug plan summary containing:
  - `env_pkg_family`, `env_flavor`
  - `env_profiles`
  - `env_features_from_profiles`
  - `enabled_features`
  - `enabled_feature_reasons`

---

## Secrets Handling

- Secrets are **not** stored in this repository
- Inject secrets externally (vault, environment variables, extra-vars)
- Playbooks may reference secrets but must not generate/manage them

---

## Idempotency Expectations

- All tasks must be safely re-runnable
- Prefer package modules where practical
- If using `command`, avoid marking changes on every run unless the task truly changes state
- Failures should be surfaced early and clearly

---

## Summary (Mental Model)

- **Profiles** describe machines
- **Feature flags** describe intent
- **Derivation** converts profiles into final `install_*` booleans
- **Playbooks** orchestrate
- **Roles** implement complexity
- **Unsupported or unknown == failure**
- **Simple beats clever**
