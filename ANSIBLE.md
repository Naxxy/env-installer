Below is a **complete, self-contained `README.md`** you can copy, save, and reuse later to resume this setup with another LLM or your future self.

It intentionally:

- avoids chezmoi
- assumes **local-only Ansible execution**
- documents **why** decisions were made, not just how
- includes concrete file paths and examples
- encodes the **marker-file + host-facts fallback pattern**

---

# Local-Only Ansible Workstation Setup

**(macOS work laptop + Omarchy ThinkPad X240)**

## Purpose

This repository defines a **local-only Ansible setup** for configuring personal machines in a **safe, explicit, and repeatable** way.

It is designed for:

- running Ansible **only on the local machine**
- supporting **multiple platforms** (macOS + Arch/Omarchy)
- supporting **device-specific behavior** (e.g. ThinkPad X240 quirks)
- supporting **profile flags** like `work_laptop`
- avoiding step numbers and custom detection scripts
- making the setup easy to resume in a future LLM chat

This setup currently supports:

| Machine        | OS             | CPU               | Notes                          |
| -------------- | -------------- | ----------------- | ------------------------------ |
| ThinkPad X240  | Omarchy (Arch) | x86_64 (Intel i7) | Hyprland, touchscreen disabled |
| MacBook (work) | macOS          | ARM64 (M-series)  | Work-only apps enabled         |

---

## Core Design Principles

1. **Local-only execution**

   - Ansible is always run against `localhost`
   - No SSH inventory, no remote orchestration

2. **Classification over detection**

   - “What kind of machine is this?” is decided by:

     - Ansible facts (OS, architecture)
     - Explicit marker files (authoritative intent)

3. **Marker files > heuristics > defaults**

   - Marker files override everything
   - Host facts are used as a fallback
   - Defaults prevent surprises

4. **Roles = responsibility boundaries**

   - Platform roles (macOS / Arch)
   - Desktop roles (Hyprland)
   - Device roles (ThinkPad X240)
   - Profile roles (work laptop)

5. **No step numbering**

   - Ordering is handled by role order
   - Idempotency is handled by Ansible modules

---

## Repository Layout

```
ansible/
├── inventory/
│   └── hosts.yml
├── playbooks/
│   └── workstations.yml
├── roles/
│   ├── profile_flags/
│   ├── base/
│   ├── macos_homebrew/
│   ├── arch_pacman/
│   ├── desktop_hyprland/
│   ├── device_thinkpad_x240/
│   └── profile_work_laptop/
└── README.md
```

---

## Inventory (Local-Only)

### `inventory/hosts.yml`

```yaml
all:
  hosts:
    localhost:
      ansible_connection: local
```

- There is only one host: `localhost`
- All classification is done dynamically via facts and flags

---

## Playbook: Workstations

### `playbooks/workstations.yml`

```yaml
- name: Configure local workstation
  hosts: localhost
  become: true

  roles:
    - profile_flags # compute flags first
    - base
    - macos_homebrew
    - arch_pacman
    - desktop_hyprland
    - device_thinkpad_x240
    - profile_work_laptop
```

### Role ordering matters

- `profile_flags` must run first
- Platform roles run before dependent roles
- Device and profile roles are isolated and explicit

---

## Profile Flags (Marker File + Host Facts)

### Goal

Compute `work_laptop` using:

1. Explicit marker file (`/etc/ansible/work-laptop`)
2. Host facts fallback (macOS + ARM64 + hostname heuristic)
3. Default = false

---

### Marker File (Authoritative)

On the **MacBook work laptop only**:

```bash
sudo mkdir -p /etc/ansible
sudo touch /etc/ansible/work-laptop
```

Do **not** create this file on personal machines.

---

### `roles/profile_flags/tasks/main.yml`

```yaml
- name: Check for explicit work-laptop marker
  stat:
    path: /etc/ansible/work-laptop
  register: work_marker

- name: Infer work-laptop from host facts (fallback)
  set_fact:
    inferred_work_laptop: >-
      {{
        ansible_facts['system'] == 'Darwin'
        and ansible_facts['architecture'] in ['arm64', 'aarch64']
        and (
          'work' in (ansible_facts['hostname'] | lower)
          or 'corp' in (ansible_facts['hostname'] | lower)
        )
      }}
  when: not work_marker.stat.exists

- name: Set final work_laptop flag
  set_fact:
    work_laptop: >-
      {{
        work_marker.stat.exists
        or (inferred_work_laptop | default(false))
      }}
```

---

## Base Role (All Machines)

### `roles/base/tasks/main.yml`

```yaml
- name: Install basic packages (Arch)
  pacman:
    name:
      - git
      - curl
      - neovim
    state: present
  when:
    - ansible_facts['system'] == 'Linux'
    - ansible_facts['distribution'] == 'Archlinux'
```

---

## macOS Platform Role

### `roles/macos_homebrew/tasks/main.yml`

```yaml
- name: Install Homebrew if missing
  shell: |
    if ! command -v brew >/dev/null 2>&1; then
      /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    fi
  args:
    executable: /bin/bash
  changed_when: false
  when: ansible_facts['system'] == 'Darwin'

- name: Install brew packages
  homebrew:
    name:
      - git
      - neovim
      - jq
    state: present
  when: ansible_facts['system'] == 'Darwin'
```

---

## Arch / Omarchy Platform Role

### `roles/arch_pacman/tasks/main.yml`

```yaml
- name: Install pacman packages
  pacman:
    name:
      - git
      - neovim
      - jq
      - mpv
      - yt-dlp
    state: present
  when:
    - ansible_facts['system'] == 'Linux'
    - ansible_facts['distribution'] == 'Archlinux'
```

---

## Desktop Environment: Hyprland

### `roles/desktop_hyprland/tasks/main.yml`

```yaml
- name: Install Hyprland stack
  pacman:
    name:
      - hyprland
      - waybar
      - wl-clipboard
    state: present
  when:
    - ansible_facts['system'] == 'Linux'
    - ansible_facts['distribution'] == 'Archlinux'
```

---

## Device-Specific Role: ThinkPad X240

Purpose: disable touchscreen via udev.

### `roles/device_thinkpad_x240/tasks/main.yml`

```yaml
- name: Disable touchscreen via udev rule
  copy:
    dest: /etc/udev/rules.d/99-disable-touchscreen.rules
    content: |
      ACTION=="add", SUBSYSTEM=="input", ATTR{name}=="ELAN Touchscreen", ENV{LIBINPUT_IGNORE_DEVICE}="1"
    owner: root
    group: root
    mode: "0644"
  when:
    - ansible_facts['system'] == 'Linux'
    - ansible_facts['distribution'] == 'Archlinux'

- name: Reload udev rules
  command: udevadm control --reload-rules
  when:
    - ansible_facts['system'] == 'Linux'
    - ansible_facts['distribution'] == 'Archlinux'

- name: Trigger udev
  command: udevadm trigger
  when:
    - ansible_facts['system'] == 'Linux'
    - ansible_facts['distribution'] == 'Archlinux'
```

This role is included **explicitly** in the playbook to avoid accidental application elsewhere.

---

## Work Laptop Profile Role

### `roles/profile_work_laptop/tasks/main.yml`

```yaml
- name: Install work-only applications
  homebrew_cask:
    name:
      - slack
      - zoom
      - google-chrome
    state: present
  when:
    - ansible_facts['system'] == 'Darwin'
    - work_laptop | default(false)
```

---

## Running the Playbook

### On ThinkPad X240 (Omarchy)

```bash
ansible-playbook -i inventory/hosts.yml playbooks/workstations.yml --ask-become-pass
```

Expected behavior:

- Arch + Hyprland roles run
- Touchscreen is disabled
- macOS + work roles are skipped

---

### On MacBook (Work Laptop)

Ensure marker file exists:

```bash
sudo touch /etc/ansible/work-laptop
```

Then run:

```bash
ansible-playbook -i inventory/hosts.yml playbooks/workstations.yml
```

Expected behavior:

- Homebrew installs
- Work-only apps install
- Linux / Hyprland / ThinkPad roles skipped

---

## Mental Model Summary (for future you / LLM)

- **Inventory**: always `localhost`
- **Facts**: OS + architecture
- **Marker files**: explicit intent
- **Roles**: isolated responsibilities
- **Playbooks**: machine category
- **Order matters**, not numbering
- **Idempotent by default**

> “What kind of machine is this?”
> is answered once, early, and everything else follows.

---

## Future Extensions (Not Implemented Yet)

- Add more profile flags using the same pattern:

  - `/etc/ansible/travel-laptop`
  - `/etc/ansible/headless`

- Add a `dwm` desktop role
- Add a `servers.yml` playbook
- Integrate with chezmoi later (optional)

---

**End of README**
This file is intended to be dropped into a fresh chat and used as full context to continue development.
