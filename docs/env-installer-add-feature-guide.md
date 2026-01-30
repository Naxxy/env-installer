# Env Installer — Adding a New Installation Item (Feature) Guide

This guide explains how to add a new *installation item* (a feature flag like `install_foo`) to the Ansible-based env installer skeleton you’ve built.

It focuses on **explicit, auditable changes**:
- One central list of known features
- One explicit include per feature in `_install_features.yml`
- One feature task file per feature (or a role, when appropriate)
- Support enforced by a single support-matrix assertion

---

## Quick mental model

The system has three layers:

1) **Plan/Derive**: convert **profiles** into final `install_*` flags  
   - `playbooks/_derive_features.yml`

2) **Validate**: fail fast if a selected feature is not supported on a host’s platform  
   - `playbooks/_assert_supported.yml`  
   - uses `inventory/group_vars/all.yml` support matrix

3) **Execute**: run the actual installs (explicit includes, no hidden loops)  
   - `playbooks/_install_features.yml`
   - `playbooks/features/install_<feature>.yml` (or a role)

---

## Files to include in LLM context (minimum set)

If you want an LLM to create a new install item correctly (with the right conventions and minimal “magic”), include these files in context:

### Core flow
- `playbooks/main.yml`
- `playbooks/_derive_features.yml`
- `playbooks/_assert_supported.yml`
- `playbooks/_install_features.yml`

### Central configuration and catalog
- `inventory/group_vars/all.yml`
- One or more representative `inventory/host_vars/<host>.yml` (at least one per pkg_family you use)

### Packaging abstraction (so the LLM installs packages the “house way”)
- `roles/install_packages/tasks/main.yml`
- `roles/install_packages/tasks/arch.yml`
- `roles/install_packages/tasks/debian.yml`
- `roles/install_packages/tasks/macos.yml`

### A few example feature implementations (to copy the style)
- `playbooks/features/install_jq.yml` *(simple package install)*
- `playbooks/features/install_magic_wormhole.yml` *(platform choice, still simple)*
- `playbooks/features/install_lazyvim.yml` *(package deps + filesystem + git clone)*
- `playbooks/features/install_netbird.yml` and `roles/netbird/**` *(complex “role-based” install)*

**Optional but useful**
- `ansible.cfg`
- `inventory/hosts.yml`

---

## What you add when creating a new install item

A “new install item” typically means creating **one new feature flag**:
- `install_<new>` (example: `install_ghostty`)

Optionally, you also:
- add it to one or more profiles (so you can enable groups of features at once)
- add package-name mappings (if platform-specific)
- add support matrix entries (usually required)

---

## Step-by-step: add a new feature (canonical checklist)

Assume we’re adding: `install_ghostty`

### 1) Add the new feature flag to the known feature list

**File:** `inventory/group_vars/all.yml`  
Add to:

```yml
env_known_features:
  - install_mpv
  - install_brave
  ...
  - install_ghostty   # NEW
```

**Why:**  
- This is the central, explicit list of “things the system can install.”
- Derivation and support checks only operate over `env_known_features`.

---

### 2) Add it to a profile (optional but common)

**File:** `inventory/group_vars/all.yml`

Example: add to `dev_cli` or create a new profile.

```yml
env_profiles_catalog:
  dev_cli:
    - install_jq
    - install_yt_dlp
    - install_magic_wormhole
    - install_lazyvim
    - install_ghostty   # NEW
```

If you want a new profile:

```yml
env_profiles_catalog:
  terminal:
    - install_ghostty
```

**Then**, enable the profile on hosts:

**File:** `inventory/host_vars/<host>.yml`

```yml
env_profiles:
  - base
  - media
  - dev_cli
  - terminal   # NEW (if you created it)
```

---

### 3) Add support matrix entry (required)

**File:** `inventory/group_vars/all.yml`

Add to:

```yml
env_feature_support:
  install_ghostty:
    arch:   { flavors: ["all"] }
    debian: { flavors: ["all"] }
    macos:  { flavors: ["all"] }
```

Or if it’s only supported on macOS:

```yml
env_feature_support:
  install_ghostty:
    macos: { flavors: ["macos"] }
```

**Why:**  
- `_assert_supported.yml` enforces this matrix at runtime.
- This prevents “silent unsupported installs” and makes platform expectations explicit.

---

### 4) Add package name mappings (recommended if packages differ by platform)

**File:** `inventory/group_vars/all.yml`

Add to `env_package_names`:

```yml
env_package_names:
  ghostty:
    arch: "ghostty"
    debian: "ghostty"
    macos: "ghostty"   # brew formula or cask name (depending on your choice)
```

**Why:**  
- Keeps package differences centralized and auditable.
- Feature task files can stay simple and not become giant `if/else` blocks.

---

### 5) Add an explicit include in `_install_features.yml`

**File:** `playbooks/_install_features.yml`

Add a block in the same style as the others:

```yml
- name: Install Ghostty feature
  ansible.builtin.import_tasks: "features/install_ghostty.yml"
  when: install_ghostty | bool
```

**Why:**  
- This is the explicit “registry” of implementation entry points.
- You can scan this file to see exactly what exists.

---

### 6) Create the feature install task file

**File (new):** `playbooks/features/install_ghostty.yml`

At minimum, follow the pattern used by the existing feature tasks:
- debug intent
- choose package name (if needed)
- call `install_packages` role

#### Example A: simplest (same package name on all platforms)

```yml
# playbooks/features/install_ghostty.yml

- name: Debug ghostty feature intent
  ansible.builtin.debug:
    msg:
      feature: install_ghostty
      enabled: "{{ install_ghostty }}"
      reason: "{{ install_ghostty_reason }}"
      pkg_family: "{{ env_pkg_family }}"
      flavor: "{{ env_flavor }}"

- name: Install ghostty
  ansible.builtin.include_role:
    name: install_packages
  vars:
    install_packages_list:
      - name: "ghostty"
        state: present
```

#### Example B: package name differs by platform (use env_package_names mapping)

```yml
# playbooks/features/install_ghostty.yml

- name: Debug ghostty feature intent
  ansible.builtin.debug:
    msg:
      feature: install_ghostty
      enabled: "{{ install_ghostty }}"
      reason: "{{ install_ghostty_reason }}"
      pkg_family: "{{ env_pkg_family }}"
      flavor: "{{ env_flavor }}"

- name: Install ghostty
  ansible.builtin.include_role:
    name: install_packages
  vars:
    install_packages_list:
      - name: >-
          {{
            env_package_names.ghostty.arch
            if env_pkg_family == 'arch'
            else
              (
                env_package_names.ghostty.debian
                if env_pkg_family == 'debian'
                else
                  env_package_names.ghostty.macos
              )
          }}
        state: present
```

---

## What “new additions” look like (concrete examples)

### The feature flag
- `install_ghostty` *(derived automatically for every host based on profiles/overrides)*

### The profile update
- Add `install_ghostty` to an existing profile like `dev_cli`, or create a `terminal` profile.

### The support entry
- Add `install_ghostty` → `{ arch/debian/macos: flavors: [...] }` in `env_feature_support`.

### The install task
- Create `playbooks/features/install_ghostty.yml` (simple)
- Or create `roles/ghostty/**` and have the feature task call it (complex)

---

## When to use a simple feature task vs a role

### Use a simple feature task file when…
- The install is mostly “install packages”
- The install is “packages + small local config”
- The install can be done with a few straightforward Ansible modules/tasks

**Examples in your repo:**  
- `install_jq.yml`, `install_mpv.yml`, `install_magic_wormhole.yml`

### Use a role when…
- There are **multiple steps** and you want to keep them organized
- You need **platform-specific sub-steps**
- You need **post-install configuration**
- You want **defaults** and a clear contract of variables
- The feature is “a system” (service enablement, enrollment, networking, daemon control)

**Example in your repo:**  
- `roles/netbird/**` called from `playbooks/features/install_netbird.yml`

---

## Minimal vs expanded changes

### Minimal “add new feature” (fastest path)

You must touch:
1. `inventory/group_vars/all.yml`  
   - add `install_new` to `env_known_features`  
   - add support matrix entry under `env_feature_support`
2. `playbooks/_install_features.yml`  
   - add explicit import task line
3. `playbooks/features/install_new.yml`  
   - create feature implementation

Optional:
- add to `env_profiles_catalog`
- add `env_package_names` mapping
- update host `env_profiles`

### Expanded “complex feature”
Same as above, plus:
- `roles/<feature>/defaults/main.yml`
- `roles/<feature>/tasks/main.yml`
- `roles/<feature>/tasks/<platform>.yml` (optional)
- `roles/<feature>/meta/main.yml` (optional)

---

## How the feature becomes usable

Once you’ve added the feature:

1) Enable it via profiles (recommended):
- add to a profile in `env_profiles_catalog`
- ensure host includes that profile

or 2) Enable it via overrides (ad hoc):
- set `env_feature_overrides: { install_new: true }` in host vars or extra-vars

Then run:

```bash
ansible-playbook playbooks/main.yml -l <hostname>
```

The output should show:
- `env_profiles`
- `env_features_from_profiles`
- `enabled_features`
- reasons per feature

And if you enabled something unsupported on the host’s platform, `_assert_supported.yml` will fail fast with a clear message.

---

## Recommended “template” for new feature task files

Use this structure every time:

1. Debug intent (`enabled`, `reason`, platform)
2. Select package(s) (prefer `env_package_names`)
3. Install via `install_packages`
4. Optional: config steps (files, services, etc.)
5. Avoid cleverness; keep it auditable

---

## Troubleshooting (common gotchas)

- **Unknown profile** → `_derive_features.yml` fails fast with list of valid profiles.
- **Feature enabled but unsupported** → `_assert_supported.yml` fails and prints support list.
- **Debian package name missing** → add mapping in `env_package_names`.
- **macOS needs cask** → pass `cask: true` to `install_packages_list` item.

---

## Summary: the “golden path” to add `install_newthing`

1) `inventory/group_vars/all.yml`
- add `install_newthing` to `env_known_features`
- add support matrix entry
- optionally add to a profile
- optionally add package name mapping

2) `playbooks/_install_features.yml`
- add explicit import block

3) `playbooks/features/install_newthing.yml`
- implement install (simple tasks file)
- OR call a role (for complex setups)

That’s it.
