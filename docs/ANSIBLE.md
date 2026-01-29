# Env Installer – LLM Context & Design Requirements

Inspired by https://github.com/markosamuli/linux-machine/tree/master

## Purpose of This Document

This document is a **standalone, complete context file** intended to be provided verbatim to any new LLM chat.

Its goal is to ensure the LLM:

* Fully understands the **intent, constraints, preferences, and architectural direction** of this environment installer
* Produces **consistent, compatible, non-regressive** suggestions, code, and structure
* Does **not** re-introduce rejected patterns or unnecessary complexity

This installer is a **core, long-lived system**, not a throwaway script. Treat it accordingly.

---

## High-Level Goal

Build a **modular, declarative, fail-fast environment installer** using **Ansible** as the execution engine.

The system must support:

* Workstations
* Servers
* Containers

It must scale across:

* Multiple operating systems (initially Arch / Arch-like, Ubuntu/Debian-like, macOS)
* Multiple device types (laptop, desktop, homelab server, VPS, container)

The installer should be:

* Predictable
* Explicit
* Convention-driven
* Easy to reason about
* Safe to re-run (idempotent)

---

## Execution Model (Explicit)

* This installer is **push-based**, not agent-based
* It is executed manually by a human or explicitly-invoked automation
* It is **not** continuously enforcing state
* Idempotency matters, but perpetual convergence is **not assumed**
* There is no background daemon, cron job, or ansible-pull loop

This is a deliberate design choice to preserve transparency and control.

---

## Core Design Principles (Non-Negotiable)

### 1. **Intent vs Implementation Separation**

* **Intent** is expressed declaratively via flags and profiles
* **Implementation** lives in playbooks and roles
* OS / distro / platform logic must *never* leak into intent declarations

Intent answers:

> “What should exist on this system?”

Implementation answers:

> “How do we achieve that on *this* platform?”

---

### 2. **Feature-Flag-Driven Design**

* All installable capabilities are represented as **feature flags**
* Convention:

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

* Are the *only* way to enable installs
* Are machine- and profile-derived
* Must be easy to audit and grep

---

### 3. **Profiles Are the Primary User Interface**

Users do **not** manually toggle dozens of flags per machine.

Instead, machines declare **profiles**, and profiles expand into feature flags.

Example:

```yaml
profiles:
  - base
  - dev
  - laptop
```

Profiles:

* Are named sets of feature flags
* Are composable
* Live centrally (not duplicated per host)
* Can overlap freely

The system must include a deterministic step that derives `install_*` flags from profiles.

---

### 4. **Fail-Fast on Unsupported Platforms**

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

### 5. **Modularity Over Monoliths**

* No giant `workstation.yml`
* No massive conditional trees

Instead:

* One playbook per feature or concern
* Clear, predictable structure
* Minimal cross-feature coupling

---

### 6. **Simplicity Over Cleverness**

Strongly prefer:

* Boring Ansible conventions
* Readable YAML
* Explicit lists
* Repetition over abstraction when clarity wins

Avoid:

* Meta-playbooks
* Dynamic includes that obscure flow
* Deep Jinja logic
* Custom DSLs

---

### 7. **Convention Over Custom Frameworks**

Use established Ansible patterns:

* `inventory/group_vars`
* `inventory/host_vars`
* `site.yml`
* `roles/<name>/tasks/main.yml`
* OS-specific vars via `vars/<OS>.yml`

Avoid reinventing tooling Ansible already provides.

---

## Structural Expectations

### Repository Shape (Canonical)

```text
env-installer/
├── README.md
├── Makefile
├── ansible.cfg
├── scripts/
│   └── bootstrap.sh          # minimal: ensure ansible exists, then run site.yml
├── inventory/
│   ├── hosts.yml
│   ├── group_vars/
│   │   └── all/
│   │       ├── profiles.yml  # profile → feature flag mapping
│   │       ├── features.yml  # feature → supported platforms metadata
│   │       └── defaults.yml  # global defaults
│   └── host_vars/
│       └── <hostname>.yml    # profiles only
├── playbooks/
│   ├── site.yml
│   ├── _derive_features.yml
│   ├── _assert_supported.yml
│   ├── base.yml
│   ├── dev.yml
│   ├── media.yml
│   ├── docker.yml
│   └── netbird.yml
├── roles/
│   ├── docker/
│   ├── netbird/
│   └── <complex_feature>/
└── requirements.yml
```

---

## Simple vs Complex Installs

### Simple Install

A **simple install**:

* Uses standard Ansible modules (`package`, `apt`, `pacman`, `homebrew`)
* Has minimal OS variance
* Does NOT require its own role

Implemented as:

* Tasks inside a playbook

Examples:

* `ripgrep`
* `jq`
* `htop`

---

### Complex Install

A **complex install**:

* Has OS-specific repositories or install mechanisms
* Requires post-install configuration
* Has platform-specific differences

Implemented as:

* A dedicated role

Role responsibilities:

* Own all OS/platform logic
* Provide clear failure if unsupported
* Expose only stable inputs

Examples:

* Docker
* NetBird
* Slack
* Virtualization tooling

---

## Platform Handling Rules

* Platform detection should rely on:

  * `ansible_distribution`
  * `ansible_os_family`
  * `ansible_distribution_release`
  * Explicit custom facts *only when necessary*

* OS-specific values belong in:

  ```text
  roles/<feature>/vars/<OS>.yml
  ```

* Tasks must reference generic variables, not inline OS conditionals

---

## Containers (Clarification)

* Container support is intended for:

  * development containers
  * lightweight runtime environments
* Not all features or profiles must be valid in containers
* Containers may intentionally use reduced or minimal profiles
* Unsupported features in containers must fail fast unless explicitly excluded by profile

---

## Feature Lifecycle Conventions

Features may be in one of the following states:

* **supported** – fully implemented and expected to work
* **unsupported** – not implemented for this platform
* **intentionally unimplemented** – planned but explicitly incomplete

Intentionally unimplemented features must still **fail fast** when enabled,
with a clear error explaining the status.

---

## Secrets Handling

* Secrets are **not** stored in this repository
* Secrets are injected externally (environment variables, vaults, manual setup)
* Playbooks may reference secrets but must not manage or generate them

---

## Rolling Release Considerations

* Rolling-release platforms (e.g. Arch / Omarchy) are first-class citizens
* Version pinning is preferred at the feature or tool level, not system-wide
* Breakage should surface as failures, not silent workarounds

---

## Bootstrap Philosophy

* Bootstrap logic must be **minimal**
* Its only responsibilities:

  * Ensure Ansible exists
  * Execute the main playbook

Avoid:

* Re-implementing Ansible logic in bash
* Complex dependency resolution in shell scripts

---

## Idempotency Expectations

* All tasks must be safely re-runnable
* No destructive actions unless explicitly requested
* Prefer package manager state over command checks

---

## Explicit Non-Goals

This project is **not**:

* A full fleet management system
* A replacement for Nix
* A secrets manager
* A Kubernetes-centric installer

It is a **human-controlled, explicit, repeatable environment installer**.

---

## How an LLM Should Behave When Helping With This Project

When generating suggestions or code:

✅ Respect this structure
✅ Preserve feature flags + profiles
✅ Prefer explicit, readable YAML
✅ Fail fast on unsupported platforms
✅ Use Ansible conventions

❌ Do not collapse everything into one playbook
❌ Do not introduce silent skipping
❌ Do not suggest over-engineered abstractions
❌ Do not invent new frameworks or layers

If uncertain, ask:

> “Does this increase clarity and predictability?”

If not, don’t do it.

---

## Summary (Mental Model)

* **Profiles** describe machines
* **Feature flags** describe intent
* **Playbooks** orchestrate
* **Roles** implement complexity
* **Unsupported == failure**
* **Simple beats clever**

This document defines the *source of truth
