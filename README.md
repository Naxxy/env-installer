# env-installer

Cross-platform, **fail-fast**, **feature-flag-driven** environment installer powered by **Ansible**.

## Goals

- Run on:
  - Debian-family (Debian / Ubuntu / Lubuntu / Proxmox)
  - Arch-family (Arch / Omarchy)
  - macOS
- Provide an **idempotent**, scriptable way to configure a system.
- Support:
  - **Full install**: all enabled features
  - **Partial install**: enable only selected features via profiles / overrides
- Be:
  - Predictable
  - Explicit
  - Convention-driven
  - Safe to re-run

## Mental model

- **Profiles** describe machines (primary UI)
- **Feature flags** describe intent (`install_*`)
- **Playbooks** orchestrate
- **Roles** implement complexity
- **Unsupported == failure** (no silent skipping)

## Key concepts

### Profiles (primary UI)

Hosts declare profiles:

```yaml
env_profiles:
  - base
  - vpn
```

Profiles expand into feature flags using `env_profiles_catalog` (in `group_vars/all.yml`).

### Feature flags (intent)

Feature flags are the only way installs happen:

```yaml
install_<feature>: true|false
```

Examples: `install_mpv`, `install_brave`, `install_netbird`.

Feature flags are derived from:

1. `env_feature_defaults` (global defaults)
2. `env_profiles` → `env_profiles_catalog` (profile enables)
3. `env_feature_overrides` (optional per-host/manual overrides)

### Fail-fast support matrix

If a feature is enabled but not implemented for the current platform/flavor, the run **fails**.

Support is encoded in `env_feature_support` in `group_vars/all.yml`.

Example desired failure:

```
Feature 'install_slack' is enabled but unsupported for pkg_family='arch' flavor='omarchy'.
Either disable this feature or add platform support.
```

### Platform identity is explicit

Each host must declare:

- `env_pkg_family`: `arch|debian|macos`
- `env_flavor`: e.g. `arch|omarchy|debian|ubuntu|kubuntu|macos`

This is intentional (less magic, more correctness).

## Repo layout

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

## How to run

From repo root:

```sh
ansible-playbook -i inventory/hosts.yml playbooks/main.yml
```

Run only one host:

```sh
ansible-playbook -i inventory/hosts.yml playbooks/main.yml --limit thinkpad-x240
```

## What’s included (skeleton)

This repo is intentionally minimal but demonstrates the whole pattern:

- **Simple install**: `install_mpv`
  - Implemented as a feature tasks file that calls `roles/install_packages`.
- **Simple-but-variable install**: `install_brave`
  - Uses `env_package_names` mapping so it’s always clear when package choice differs (e.g. `brave` vs `brave-bin`).
- **Complex install**: `install_netbird`
  - Implemented as a dedicated role (`roles/netbird`) with per-platform tasks and basic configuration.

## Notes

- Secrets are not stored in this repo. Inject them via vault / environment / extra-vars.
- Bootstrap should stay minimal: ensure Ansible exists, then run `playbooks/main.yml`.
