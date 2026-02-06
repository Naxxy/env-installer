# env-installer (Ansible)

A small, explicit “environment installer” that lets each host declare **intent** (profiles) and produces an **install plan** (feature flags), then installs only what’s enabled.

Design goals:

- **Explicit > implicit**: key decisions live in a small number of central files.
- **Fail fast**: unknown profiles and unsupported feature/platform combos stop early with clear errors.
- **Minimal “magic”**: loops are used only where they reduce copy/paste drift and are heavily commented.
- **Easy to extend**: adding a new install item is a small, repeatable set of edits.

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
- `env_flavor`: a more specific “flavor” string (e.g. `arch`, `omarchy`, `ubuntu`, `macos`)
- `env_profiles`: list of profile names

Example (`inventory/host_vars/thinkpad-x240.yml`):

```yaml
env_pkg_family: arch
env_flavor: arch

env_profiles:
  - base
  - vpn
  - media
  - dev_cli
```

Profiles are defined centrally in `inventory/group_vars/all.yml` as `env_profiles_catalog`.

---

### 2) Profiles expand to feature flags (derive step)

`playbooks/_derive_features.yml`:

- Validates all profile names are known (fails fast on typos).
- Expands profiles → `env_features_from_profiles`.
- Derives **every** feature in `env_known_features` into:
  - `install_<feature>` (boolean)
  - `install_<feature>_reason` (`profile`, `override:true|false`, or `default:false`)
- Prints a plan summary including `env_features_from_profiles`.

This is the **planning layer**: it decides *what* will be installed, not *how*.

---

### 3) Assert support matrix (fail fast)

`playbooks/_assert_supported.yml`:

- Ensures `env_pkg_family` and `env_flavor` are set in host_vars.
- For each enabled feature, checks `env_feature_support` allows it for this platform/flavor.

---

### 4) Install enabled features (explicit includes)

`playbooks/_install_features.yml` is intentionally explicit (no hidden loops).  
Each feature file lives at `playbooks/features/install_<feature>.yml`.

Feature implementations typically use:

- `roles/install_packages` for simple package installs, or
- a dedicated role for complex workflows (services, config, multiple steps), e.g. `roles/netbird`.

---

## Quick start

### Run (all hosts in inventory)

```bash
ansible-playbook playbooks/main.yml
```

### Run a single host

```bash
ansible-playbook playbooks/main.yml -l thinkpad-x240
```

---

## Current profiles and features

Defined in `inventory/group_vars/all.yml`.

### Profiles (`env_profiles_catalog`)

- `base` → `install_brave`
- `media` → `install_mpv`
- `vpn` → `install_netbird`
- `dev_cli` → `install_jq`, `install_yt_dlp`, `install_magic_wormhole`, `install_lazyvim`

### Known features (`env_known_features`)

- `install_mpv`
- `install_brave`
- `install_netbird`
- `install_jq`
- `install_yt_dlp`
- `install_magic_wormhole`
- `install_lazyvim`

---

## Adding a new installation item

See: `env-installer-add-feature-guide.md`

High level:

1. Add `install_<new>` to `env_known_features` (and optionally a profile).
2. Add `env_feature_support` entries for your platforms/flavors.
3. Add package name mappings in `env_package_names` if required.
4. Create `playbooks/features/install_<new>.yml` (or a role for complex installs).
5. Add an explicit include in `playbooks/_install_features.yml`:

```yaml
- name: Install <new> feature
  ansible.builtin.import_tasks: "features/install_<new>.yml"
  when: install_<new> | bool
```

---

## Notes on package installation

### `roles/install_packages` (v0)

Input:

```yaml
install_packages_list:
  - name: "jq"
    state: present
  - name: "brave-browser"
    state: present
    cask: true   # macOS only
```

Behavior:

- **Arch**: repo via `pacman`; AUR heuristic `*-bin` via `yay`; pre-check with `pacman -Q`.
- **Debian**: `apt` (idempotent).
- **macOS**: `brew` formulae + casks; installs only missing items.

---

## Troubleshooting

### “Unknown profile(s) found in env_profiles…”

A profile name in `inventory/host_vars/<host>.yml` doesn’t exist in `env_profiles_catalog`. Fix the typo or add the profile.

### “Feature 'install_x' is enabled but unsupported…”

Update `env_feature_support` to allow that feature for your `env_pkg_family` / `env_flavor`.

### Homebrew missing on macOS

The macOS installer fails fast if `brew` is missing.

### Arch AUR installs fail because `yay` is missing

If you request a package ending in `-bin`, the arch installer routes it through `yay`. Install `yay` first or change the package name.

---

## License

Internal / personal tooling (add a license if you plan to publish).
