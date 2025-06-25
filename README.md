# 🛠️ Server-Hub
> ⚠️ **Note:** This repository is live and accessible, but this README documentation is currently under preparation.

**A one-stop automation toolkit to set up a central server for managing your home lab** — whether on **VMware Workstation**, **QEMU/KVM**, or even a **bare-metal physical setup**.

> ⚠️ **DISCLAIMER:** This project is intended for **testing**, **development**, and **experimentation** purposes only.  


( Download Link : [AlmaLinux-10-latest-x86_64-dvd.iso](https://repo.almalinux.org/almalinux/10/isos/x86_64/AlmaLinux-10-latest-x86_64-dvd.iso) )  
```
sudo dnf install git -y; sudo mkdir -p /server-hub; sudo chown ${USER}:$(id -g) /server-hub; git clone https://github.com/Muthukumar-Subramaniam/server-hub.git /server-hub; cd /server-hub
```
## 🖥️ OS & Provisioning Support

### 🧠 Central infra Server OS

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
| Debian-based     | Ubuntu LTS                                     | Cloud-init (`cloud-config`)   | ✅ Included by default   |
| SUSE-based       | openSUSE Leap                                  | AutoYaST                      | ✅ Included by default   |

> 🧪 This toolkit is designed for lab environments that require provisioning and managing heterogeneous Linux distributions for testing, experimentation, and development.

## 🖥️ OS & Provisioning Support

### 🧠 Central Server OS

The central server runs on **AlmaLinux 10** by default.  
You can also customize it to use any **Red Hat-compatible distribution**, such as:

- **RHEL** (via developer subscription with minor tweaks)
- **Rocky Linux**
- **Oracle Linux**
- **CentOS Stream**

---

### 📦 VM Guest OS Provisioning

All VM provisioning is **centrally managed** by the server using automation scripts and configuration templates.

The toolkit supports automated provisioning for VMs across all **three major Linux families**, with **ready-to-use configurations** included for:

| Distro Family    | Supported OSes                                | Provisioning Method           | Status                  |
|------------------|-----------------------------------------------|-------------------------------|--------------------------|
| Red Hat-based    | AlmaLinux                                      | Kickstart                     | ✅ Included by default   |
|                  | Rocky, Oracle Linux, RHEL, CentOS Stream       | Kickstart                     | 🔧 Customizable          |
| Debian-based     | Ubuntu LTS                                     | Cloud-init (`cloud-config`)   | ✅ Included by default   |
| SUSE-based       | openSUSE Leap                                  | AutoYaST                      | ✅ Included by default   |

> 🧪 This toolkit is designed for lab environments that require provisioning and managing heterogeneous Linux distributions for testing, experimentation, and development.

---

### 🧾 Minimum System Requirements of VMs

> These are **minimum** recommended values. Feel free to **increase** based on your use case and workload.

#### 🔹 Infra-Server (Central Controller)
- 🧠 **Memory**: 2 GB RAM
- ⚙️ **CPU**: 2 vCPUs
- 💾 **Storage**: 30 GB

#### 🔸 VM Instances (Provisioned Guests)
- 🧠 **Memory**: 2 GB RAM
- ⚙️ **CPU**: 2 vCPUs
- 💾 **Storage**: 10 GB



Either you can setup lab environment in VMware Workstation or you could utilize QEMU/KVM depending upon your requirement

To Setup the Lab in VMware Workstation :

1) Setup your VMware Workstation with proper virtual network adapter settings
   * Please remove all existing virtual interfaces and just create one vmnet0 interface with NAT configuration and DCHP disabled 
   * Better choose /22 CIDR private network of your choice and make the first IP as NAT gateway
   * If in case you are running VMware workstation on Windows, Assign the second IP of the above network as the virtual interface IP.

2) Download the AlmaLinux-10 latest with above provided link and install your infra server VM.
   * During installation use 4GB RAM, later you could reduce the RAM size after installation.
   * Please make sure UEFI is used for the VM instead of BIOS in the advanced settings.

