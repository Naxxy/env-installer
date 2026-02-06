# env-installer (Ansible)

A small, explicit “environment installer” that lets each host declare **intent** (profiles) and produces an **install plan** (feature flags), then installs only what’s enabled.

Design goals:

- **Explicit > implicit**: key decisions live in a small number of central files.
- **Fail fast**: unknown profiles and unsupported feature/platform combos stop early with clear errors.
- **Minimal “magic”**: loops are used only where they reduce copy/paste drift and are heavily commented.
- **Easy to extend**: adding a new install item is a small, repeatable set of edits.
- **Safe by default**: destructive or system‑level changes are guarded by preflight checks.

---

## Repository structure (relevant parts)

```
ansible.cfg
inventory/
  hosts.yml
  group_vars/
    all.yml
  host_vars/
    thinkpad-x240.yml
    macbook-2019.yml
    work_macbook.yml
playbooks/
  main.yml
  _derive_features.yml
  _assert_supported.yml
  _preflight_omarchy_snapshot.yml
  _install_features.yml
  features/
    install_brave.yml
    install_jq.yml
    install_lazyvim.yml
    install_magic_wormhole.yml
    install_mpv.yml
    install_netbird.yml
    install_yt_dlp.yml
roles/
  install_packages/
    tasks/
      main.yml
      arch.yml
      debian.yml
      macos.yml
  netbird/
    defaults/main.yml
    meta/main.yml
    tasks/
      main.yml
      assert.yml
      arch.yml
      debian.yml
      macos.yml
      configure.yml
```

---

## How it works

### 1) Host declares intent (profiles)

Each host sets:

- `env_pkg_family`: `arch | debian | macos`
- `env_flavor`: a more specific flavor (`arch`, `omarchy`, `ubuntu`, `macos`, etc.)
- `env_profiles`: list of profile names

Example:

```yaml
env_pkg_family: arch
env_flavor: omarchy

env_profiles:
  - base
  - media
  - dev_cli
```

Profiles are defined centrally in `inventory/group_vars/all.yml`.

---

### 2) Profiles expand to feature flags (derive step)

`playbooks/_derive_features.yml`:

- Validates profile names (fail‑fast on typos)
- Expands profiles → features
- Produces `install_*` booleans
- Records reasons (`profile`, `override`, `default:false`)

This is the **planning layer**.

---

### 3) Assert support matrix (fail fast)

`playbooks/_assert_supported.yml`:

- Ensures pkg family & flavor are defined
- Ensures enabled features are supported

---

### 4) Omarchy snapshot preflight (safety layer)

`playbooks/_preflight_omarchy_snapshot.yml`:

If `env_flavor == "omarchy"`:

- Verifies `omarchy-snapshot` tooling exists
- Creates a **bootable system snapshot** before installs
- Fails fast if snapshot tooling is required but unavailable
- Is safe in `--check` mode

Command used:

```bash
sudo omarchy-snapshot create
```

This ensures the system can be rolled back from the Limine boot menu if an install causes instability.

Snapshot behavior is controlled via:

```yaml
env_omarchy_snapshot_before_install: true
env_omarchy_snapshot_required: true
```

---

### 5) Install enabled features

`playbooks/_install_features.yml` explicitly includes feature installers.

No hidden loops — full transparency.

---

## Quick start

Run all hosts:

```bash
ansible-playbook playbooks/main.yml
```

Run one host:

```bash
ansible-playbook playbooks/main.yml -l thinkpad-x240
```

---

## Current profiles and features

Defined in `inventory/group_vars/all.yml`.

### Profiles

- `base` → brave
- `media` → mpv
- `vpn` → netbird
- `dev_cli` → jq, yt-dlp, wormhole, lazyvim

### Known features

- install_mpv
- install_brave
- install_netbird
- install_jq
- install_yt_dlp
- install_magic_wormhole
- install_lazyvim

---

## Notes on package installation

### install_packages role

Input:

```yaml
install_packages_list:
  - name: jq
    state: present
```

Behavior:

- Arch → pacman / yay
- Debian → apt
- macOS → brew

---

## Safety guarantees

On Omarchy systems:

- A bootable snapshot is taken before installs
- Failure to snapshot blocks execution (by default)
- Prevents unrecoverable system breakage

---

## License

Internal / personal tooling.
