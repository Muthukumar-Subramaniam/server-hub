# 🛠️ Server-Hub  
This project allows to build and manage a virtual home lab, making it easy to deploy, break, and rebuild Linux VMs effortlessly. It automates VM provisioning, manages the complete lifecycle of your VMs, and provides a flexible environment for learning, testing, and experimenting with Linux-based technologies.  
Although many open-source alternatives exist, I built this project for the fun of creating something of my own and sharing it with anyone with similar interests.  

> ⚠️ **DISCLAIMER:** This project is intended for **testing**, **development**, and **experimentation** purposes only.  

## 🖥️ Automated Lab Environment for Provisioning and Managing Linux VMs

### 🧠 Central Infra Server VM's OS  
The central lab infrastructure server VM is designed to run on AlmaLinux 10 by default, providing all the essential services for managing the lab environment.  

### 📦 VM Guest OS Provisioning

The lab infrastructure server centrally manages all guest VM provisioning using automation scripts and configuration templates.

The toolkits provide automated VM provisioning for all three major Linux families, including ready-to-use configurations for:

| Distro Family    | Supported OSes                                | Provisioning Method           | Status                  |
|------------------|-----------------------------------------------|-------------------------------|--------------------------|
| Red Hat-based    | AlmaLinux                                      | Kickstart                     | ✅ Included by default   |
|                  | Rocky, Oracle Linux, RHEL, CentOS Stream       | Kickstart                     | 🔧 Customizable          |
| Debian-based     | Ubuntu LTS                                     | Cloud-init (`cloud-config`)   | 🔧 Customizable
| SUSE-based       | openSUSE Leap                                  | AutoYaST                      | 🔧 Customizable|

---

### 🧾 Minimum System Requirements of VMs

> These are the minimum recommended values. You can adjust them later based on your specific use case and workload.”

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
