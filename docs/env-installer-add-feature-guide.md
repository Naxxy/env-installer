# Env Installer — Adding a New Installation Item (Feature) Guide

This guide explains how to add a new *installation item* (feature flag) to the env‑installer system.

It reflects the **current architecture**, including Omarchy safety and platform separation rules.

---

# Mental Model

The installer has four execution layers:

1) Derive → Profiles → Feature flags  
2) Assert → Platform support matrix  
3) Preflight → Safety checks (Omarchy snapshots, etc.)  
4) Install → Feature implementations

---

# 🔒 Omarchy Safety Context (Important)

When adding features, you must understand:

If the host is:

```
env_flavor: omarchy
```

Then:

- A snapshot is taken before installs
- Your feature will run **after snapshot protection**
- Any destructive system change must assume rollback safety exists
- Do NOT bypass or re‑implement snapshot logic inside features

Snapshot logic lives here:

```
playbooks/_preflight_omarchy_snapshot.yml
```

Never duplicate it.

---

# Files You Must Touch (Minimum)

When adding a feature `install_foo`:

```
inventory/group_vars/all.yml
playbooks/_install_features.yml
playbooks/features/install_foo.yml
```

Optional (if complex):

```
roles/foo/**
```

---

# Step‑By‑Step

## 1) Add Feature Flag

File:

```
inventory/group_vars/all.yml
```

Add to:

```yaml
env_known_features:
  - install_foo
```

---

## 2) Add to Profile (Optional)

Example:

```yaml
env_profiles_catalog:
  dev_cli:
    - install_foo
```

---

## 3) Add Support Matrix Entry

Example:

```yaml
env_feature_support:
  install_foo:
    arch:   { flavors: ["arch"] }
    omarchy:{ flavors: ["omarchy"] }
    debian: { flavors: ["all"] }
    macos:  { flavors: ["all"] }
```

Fail‑fast enforcement happens automatically.

---

## 4) Add Package Name Mapping (If Needed)

```yaml
env_package_names:
  foo:
    arch: "foo"
    debian: "foo"
    macos: "foo"
```

---

## 5) Register Install Task

File:

```
playbooks/_install_features.yml
```

Add:

```yaml
- name: Install foo feature
  ansible.builtin.import_tasks: "features/install_foo.yml"
  when: install_foo | bool
```

---

## 6) Create Feature Implementation

File:

```
playbooks/features/install_foo.yml
```

Template:

```yaml
- name: Debug foo feature intent
  ansible.builtin.debug:
    msg:
      feature: install_foo
      enabled: "{{ install_foo }}"
      reason: "{{ install_foo_reason }}"
      pkg_family: "{{ env_pkg_family }}"
      flavor: "{{ env_flavor }}"

- name: Install foo
  ansible.builtin.include_role:
    name: install_packages
  vars:
    install_packages_list:
      - name: "foo"
        state: present
```

---

# Simple vs Complex Features

## Simple

Package installs only.

Examples:

- jq
- mpv
- yt‑dlp

Implemented via feature task file only.

---

## Complex

Multi‑step installs, services, config.

Use a role:

```
roles/foo/tasks/main.yml
```

Feature file becomes a thin wrapper.

---

# Omarchy‑Specific Guidance

If your feature affects:

- Bootloader
- Kernel
- Filesystems
- Graphics stack
- Init systems

Then:

- Assume snapshot rollback exists
- Do not disable snapshot preflight
- Do not run destructive upgrades blindly
- Prefer explicit package installs over system upgrades

---

# Testing a New Feature

Run:

```bash
ansible-playbook playbooks/main.yml --check
```

Then:

```bash
ansible-playbook playbooks/main.yml
```

On Omarchy hosts you should see snapshot creation first.

---

# Golden Path Summary

Add feature flag → Support matrix → Install task → (Optional role)

Snapshot safety and platform assertions run automatically.