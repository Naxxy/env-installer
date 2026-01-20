## NetBird config follow-up notes

### Current state

* `install-netbird` step exists and focuses on **installation + daemon/service start**.
* We intentionally **do not run `netbird up`** in the install step (interactive / identity-binding).

### What the screenshots clarified

* **macOS brew install must use the NetBird tap**, not `brew install netbird`:

  * CLI: `brew tap netbirdio/tap && brew install netbirdio/tap/netbird`
  * Optional GUI: `brew install --cask netbirdio/tap/netbird-ui`
* macOS daemon commands shown in docs:

  * `sudo netbird service install`
  * `sudo netbird service start`
* Linux docs show:

  * `curl -fsSL https://pkgs.netbird.io/install.sh | sh`
  * then `netbird up`

### Design decision to make (deferred)

We need to decide whether env-installer should also handle **joining/auth** (NetBird “up”), and if yes, how.

There are two join flows:

1. **Human devices (laptops/desktops)**

   * Join method: **browser login**
   * Command: `netbird up`
   * Interactive and easy to revoke/reauth

2. **Infrastructure devices (Proxmox/VPS/NAS)**

   * Join method: **setup key / token**
   * Desired: “never disconnect”, headless-safe, automatable
   * Command shape: `netbird up --setup-key <TOKEN>` (exact flags to confirm later)

### Options we discussed

A) Keep env-installer **install-only**, and output a **post-install checklist** like:

* “NetBird installed but not connected — run `netbird up`”
* “Proxmox: join using setup key”

B) Add **separate optional configuration steps** (recommended if automating):

* `configure-netbird-up` (interactive, human devices)
* `configure-netbird-setup-key` (headless, infra devices; requires secret)

C) Hybrid:

* For Proxmox only, include headless join step (device-scoped)
* For laptops, only print reminder

### Constraints / safety requirements

* Do not run interactive auth automatically in default “run all steps”.
* If we add setup-key join:

  * Must **fail loudly** when the token is missing (so we don’t silently “think” it joined).
  * Token should be supplied via env var (e.g. `NETBIRD_SETUP_KEY`) or a secrets file.
  * Should not be logged in plaintext to LOGFILE.

### Next time: what to implement

* Confirm exact headless join command/flags for NetBird setup keys.
* Decide between A / B / C above.
* If B or C:

  * Implement `0060-configure-netbird-up.sh`
  * Implement `0061-configure-netbird-setup-key.sh` with:

    * guard: only proxmox / infra devices
    * requires `NETBIRD_SETUP_KEY`
    * redact token in logs
    * idempotency: detect “already connected” before running

### Useful checks we’ll likely use

* “is netbird connected?” check (to pick idempotency):

  * `netbird status` (exact output to confirm)
* service running:

  * `netbird service status` (if available)
  * or systemd checks on Linux if needed
