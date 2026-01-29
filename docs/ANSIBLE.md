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
- There is no background daemon, cron job, or ansible-pull loop

This is a deliberate design choice to preserve transparency and control.

---

## Core Design Principles (Non-Negotiable)

### 1. Intent vs Implementation Separation

- **Intent** is expressed declaratively via flags and profiles
- **Implementation** lives in playbooks and roles
- OS / distro / platform logic must *never* leak into intent declarations

Intent answers:

> “What should exist on this system?”

Implementation answers:

> “How do we achieve that on *this* platform?”

---

### 2. Feature-Flag-Driven Design

- All installable capabilities are represented as **feature flags**
- Convention:

  ```yaml
  install_<feature>: true|false
  ```

Examples:

```yaml
install_docker: true
install_netbird: true
install_slack: false
```

Feature flags:

- Are the *only* way to enable installs
- Are machine- and profile-derived
- Must be easy to audit and grep

---

### 3. Profiles Are the Primary User Interface

Users do **not** manually toggle dozens of flags per machine.

Instead, machines declare **profiles**, and profiles expand into feature flags.

Example:

```yaml
env_profiles:
  - base
  - dev
  - laptop
```

Profiles:

- Are named sets of feature flags
- Are composable
- Live centrally (not duplicated per host)
- Can overlap freely

The system includes a deterministic step that derives `install_*` flags from profiles.

---

### 4. Fail-Fast on Unsupported Platforms

If a feature flag is enabled but the current platform is not supported:

✅ **FAIL HARD**  
❌ Do NOT silently skip  
❌ Do NOT warn and continue

Example failure message (desired):

```
install_slack=true but Slack is not implemented for Arch Linux.
Either disable this feature or add platform support.
```

This prevents configuration drift and false confidence.

---

### 5. Modularity Over Monoliths

Avoid giant monolithic playbooks or huge conditional trees.

Prefer:

- One “main” orchestration playbook
- Explicit feature task files
- Roles for complex installs

---

### 6. Simplicity Over Cleverness

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

### 7. Convention Over Custom Frameworks

Use established Ansible patterns:

- `inventory/hosts.yml`, `inventory/host_vars/<host>.yml`
- `playbooks/main.yml`
- `roles/<role>/tasks/main.yml`

This repo keeps shared variables in `group_vars/all.yml` at the repo root.

---

## Structural Expectations (This Repo)

```text
env-installer/
├── README.md
├── ansible.cfg
├── docs/
│   └── ANSIBLE.md
├── inventory/
│   ├── hosts.yml
│   └── host_vars/
│       ├── thinkpad-x240.yml
│       └── macbook-2019.yml
├── group_vars/
│   └── all.yml
├── playbooks/
│   ├── main.yml
│   ├── _derive_features.yml
│   ├── _assert_supported.yml
│   ├── _install_features.yml
│   └── features/
│       ├── install_mpv.yml
│       ├── install_brave.yml
│       └── install_netbird.yml
└── roles/
    ├── install_packages/
    └── netbird/
```

---

## Simple vs Complex Installs

### Simple Install

A **simple install**:

- Uses package manager installs
- Has minimal OS variance
- Does NOT require its own role

Implemented as:

- A feature tasks file that calls `roles/install_packages`

Examples:

- `mpv`
- `ripgrep`
- `jq`

### Complex Install

A **complex install**:

- Has OS-specific repos / install mechanisms
- Requires post-install configuration
- Has platform-specific differences

Implemented as:

- A dedicated role

Examples:

- Docker
- NetBird
- Slack

---

## Platform Handling Rules

- Platform identity is explicit per host:
  - `env_pkg_family`: `arch|debian|macos`
  - `env_flavor`: `arch|omarchy|debian|ubuntu|kubuntu|macos|...`

- Support matrix lives in `env_feature_support` (shared vars)
- If enabled but unsupported: **fail fast**

---

## Secrets Handling

- Secrets are **not** stored in this repository
- Inject secrets externally (vault, environment variables, extra-vars)
- Playbooks may reference secrets but must not generate/manage them

---

## Idempotency Expectations

- All tasks must be safely re-runnable
- Prefer package modules where practical
- If using `command`, avoid marking changes on every run
- Failures should be surfaced early and clearly

---

## Summary (Mental Model)

- **Profiles** describe machines
- **Feature flags** describe intent
- **Playbooks** orchestrate
- **Roles** implement complexity
- **Unsupported == failure**
- **Simple beats clever**

This document defines the *source of truth*.
