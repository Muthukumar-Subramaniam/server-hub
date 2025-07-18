# 🛠️ Server-Hub
---

**A one-stop automation toolkit to set up a central server for managing your home lab** — whether on **VMware Workstation**, **QEMU/KVM**, or even a **bare-metal physical setup**.

> ⚠️ **DISCLAIMER:** This project is intended for **testing**, **development**, and **experimentation** purposes only.  

## 🖥️ Automated VM Provisioning and Home Lab Management

### 🧠 Central Infra Server VM's OS

The central infra server runs on **AlmaLinux 10** by default.  
You can also customize it to use any **Red Hat-compatible distribution**, such as:

- **RHEL** (via developer subscription with minor tweaks)
- **Rocky Linux**
- **Oracle Linux**
- **CentOS Stream**

---

### 📦 VM Guest OS Provisioning

All VM provisioning is **centrally managed** by the central infra server using automation scripts and configuration templates.

The toolkit supports automated provisioning for VMs across all **three major Linux families**, with **ready-to-use configurations** included for:

| Distro Family    | Supported OSes                                | Provisioning Method           | Status                  |
|------------------|-----------------------------------------------|-------------------------------|--------------------------|
| Red Hat-based    | AlmaLinux                                      | Kickstart                     | ✅ Included by default   |
|                  | Rocky, Oracle Linux, RHEL, CentOS Stream       | Kickstart                     | 🔧 Customizable          |
| Debian-based     | Ubuntu LTS                                     | Cloud-init (`cloud-config`)   | 🔧 Customizable
| SUSE-based       | openSUSE Leap                                  | AutoYaST                      | 🔧 Customizable|

> 🧪 This toolkit is designed for lab environments that require provisioning and managing heterogeneous Linux distributions for testing, experimentation, and development.

---

### 🧾 Minimum System Requirements of VMs

> These are **minimum** recommended values. Feel free to **increase** based on your use case and workload.

#### 🔹 Central Infra Server VM
- 🧠 **Memory**: 2 GB RAM
- ⚙️ **CPU**: 2 vCPUs
- 💾 **Storage**: 30 GB

#### 🔸 Provisioned VMs
- 🧠 **Memory**: 2 GB RAM
- ⚙️ **CPU**: 2 vCPUs
- 💾 **Storage**: 20 GB

---
## [Click Here to Setup QEMU/KVM based Home-Lab on Linux-Workstation](setup-home-lab-on-linux-worksation-with-qemu-kvm.md)
---
## [Click Here to Setup VMware-Workstation based Home-Lab on Windows](setup-home-lab-on-vmware-workstation.md)
---
