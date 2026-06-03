# ⚠️ This Project Has Been Archived

**server-hub** is no longer maintained. It has been superseded by [**tux2lab**](https://github.com/Muthukumar-Subramaniam/tux2lab) — a ground-up rewrite with significant improvements across every aspect of the project.

---

## 🔄 Why the Move to tux2lab?

server-hub (70 releases, v2.1.6) delivered automated VM provisioning with PXE boot, golden images, multi-distro support, DNS management, and full VM lifecycle control. But its internal architecture accumulated limitations that warranted a clean slate rather than incremental fixes:

• **Naming** — "server-hub" was generic and easily confused with other projects. "tux2lab" is distinctive and captures the purpose: Linux (Tux) to Lab.

• **CLI** — server-hub used separate commands (`qlabvmctl`, `qlabstart`, `qlabhealth`, `qlabdnsbinder`) with no unified entry point. tux2lab consolidates everything under a single `tux2lab` command with consistent subcommand structure (`tux2lab <verb> [noun] [options]`).

• **Directory layout** — server-hub scattered state across `/server-hub`, `/kvm-hub`, and `/iso-files`. tux2lab cleanly separates code (`/tux2lab`) from data (`/tux2lab-data`).

• **Host mode** — server-hub only supported VM mode. tux2lab adds Host mode for running the lab infrastructure directly on the KVM host — useful for systems with limited RAM.

• **Lab lifecycle** — server-hub had no `deploy`, `destroy`, or `rebuild` commands. tux2lab provides complete lifecycle management with `tux2lab deploy`, `tux2lab destroy`, and `tux2lab rebuild`, plus `tux2lab start`, `tux2lab stop`, `tux2lab enable`, and `tux2lab disable` for controlling the lab as a whole.

• **VM snapshots** — server-hub had no snapshot capability. tux2lab provides full snapshot management — create, list, info, delete, and revert with interactive shutdown handling and auto-start after revert.

• **VM validation** — server-hub had no post-install verification. tux2lab adds `tux2lab vm validate` which runs real functional tests over SSH — HTTPS CA cert, DNS lookup, sudo, package repos, NTP, and IPv4/IPv6 connectivity.

• **Concurrency** — server-hub had no protection against parallel operations. tux2lab uses atomic directory-based locks with stale PID detection across all critical paths (MAC generation, DNS updates, golden-image builds, VM installs).

• **Tab completion** — server-hub had basic completion. tux2lab provides context-aware per-subcommand completion with positional argument tracking, option deduplication, value-flag suppression, and VM name completion after `-H`.

• **DNS management (dnsbinder)** — server-hub's `qlabdnsbinder` was a monolithic script. tux2lab's `dnsbinder` is a fully rewritten DNS management tool with atomic zone-file updates, CNAME/PTR support, bulk operations, zone integrity validation, and safe concurrent access.

• **Guest VM provisioning** — server-hub had limited distro selection logic. tux2lab provides an interactive distro picker with version filtering, golden-image awareness, per-distro disk space validation, checksum verification, and support for both PXE boot and golden-image cloning workflows.

• **Supported distributions** — RHEL-based 8, 9, 10 (AlmaLinux, Rocky, Fedora), Ubuntu LTS 22.04, 24.04, 26.04, and openSUSE Leap 15.5, 15.6, 16.0.

• **Download reliability** — server-hub used wget without retry logic. tux2lab uses curl with automatic retry, resume support, checksum verification, and per-distro disk space validation before downloads begin.

• **Deploy experience** — server-hub required manual console exit and two reboots. tux2lab deploys end-to-end unattended — waits for SSH, monitors bootstrap, configures host DNS resolution on the KVM host, and runs a health check automatically.

• **Deterministic configuration** — server-hub prompted for hostname and domain interactively. tux2lab fixes the hostname to `tux2lab-engine` with domain `<user>.internal` — zero ambiguity, reproducible deploys.

• **Lab cleanup** — server-hub had no proper destroy or cleanup logic. Removing the lab meant manually stopping services, deleting VMs, unmounting filesystems, and cleaning fstab/environment variables. tux2lab provides a comprehensive `tux2lab destroy` that handles everything — VMs, storage pools, mounts, services, firewall rules, DNS, fstab entries, environment variables — with idempotent execution and clear `[DONE]`/`[SKIP]`/`[FAIL]` output on every run.

• **Stability** — 443 commits across 18 pre-releases (v0.1.0 through v0.15.0) followed by three release candidates (v1.0.0-rc1, v1.0.0-rc2, v1.0.0-rc3) — extensive testing and bug fixing covering exit code handling, variable scoping, race conditions, signal traps, error paths, and edge cases that server-hub carried silently.

### 🔧 Technical Highlights

• 100% Bash — zero runtime dependencies beyond coreutils, curl, and standard system tools

• Dual-stack networking (IPv4 `10.28.28.0/22` + IPv6 ULA `fd28:2808:2020:3000::/64`) out of the box

• Centralized distro version configuration — add new OS versions in one file

• Lab services: BIND, Kea DHCPv4/v6, radvd, nginx, chrony, NFS, TFTP/iPXE

• Automated migration path from server-hub via `cleanup-old-server-hub.sh`

---

## 👉 What Should I Use Instead?

**[tux2lab](https://github.com/Muthukumar-Subramaniam/tux2lab)** — Build Your Own KVM Virtual Home Lab

---

## Can I Still Use server-hub?

The code remains available in read-only mode for reference, but no further updates, bug fixes, or support will be provided. You are strongly encouraged to migrate to **tux2lab**.

---

*Thank you to everyone who used and contributed to server-hub over its 70 releases.*
