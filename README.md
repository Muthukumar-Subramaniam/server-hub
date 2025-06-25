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

# Lab Setup for VMware Workstation :
---
## 💿 Install VMware Workstation Pro 17.5.x on Windows

VMware Workstation Pro is now available for free personal use. Here's how to get it:

### 🔐 1. Register at Broadcom

- Go to: [https://support.broadcom.com](https://support.broadcom.com)
- Click **Register** (top right)
- Create an account and verify your email

### ⬇️ 2. Download Workstation Pro

- Visit:  
  👉 [Download VMware Workstation Pro (Free)](https://support.broadcom.com/group/ecx/productdownloads?subfamily=VMware%20Workstation%20Pro&freeDownloads=true)

- Log in with your Broadcom account
- Download the Windows installer:  
  `VMware-Workstation-Full-17.5.x.exe`

### 🛠️ 3. Install

- Run the installer and complete the setup using default options

## 🌐 VMware Workstation Virtual Network Setup (Clean Lab Mode)

To maintain a deterministic and automation-friendly lab environment, the setup uses **a single custom virtual network** managed entirely by the central infra-server.

### 🔄 Reset Virtual Network Configuration

1. Open the **Virtual Network Editor** (admin/root privileges required):
   - **Windows**: Launch VMware Workstation as Administrator → `Edit` → `Virtual Network Editor`

2. **Remove all existing VM networks** (`vmnet1`, `vmnet8`, etc.)

### ➕ Create `vmnet0` – Clean NAT Network

1. Click **Add Network** → Select **`vmnet0`**

2. Configure the following:

| Setting                            | Value                        |
|------------------------------------|------------------------------|
| **Network Type**                   | ✅ NAT                       |
| **Connect a Host Virtual Adapter** | ✅ Enabled                   |
| **Use local DHCP**                 | ❌ Disabled                  |
| **Subnet IP**                      | e.g., `10.10.20.0`           |
| **Subnet Mask**                    | `255.255.252.0` (`/22`)      |

3. Click the **“NAT Settings”** button  
   - Set the **Gateway IP** to the **first IP in the subnet**, e.g., `10.10.20.1`

4. ✅ Once everything is configured and verified, click **Apply** and then **OK** to save the network setup.

> 🧠 This creates a `/22` virtual lab network, managed entirely by your infra-server, with the first few IPs reserved for infrastructure components.
> 💡 You can use **any private /22 subnet**, such as `10.0.0.0/22`, `172.16.40.0/22`, or `192.168.50.0/22`.  
> Just ensure it does **not conflict with your LAN or VPN networks**.

### 🧠 IP Address Management & PXE Boot Strategy

- **Static IPs** are assigned to all VMs by the infra-server during provisioning.
- The **infra-server runs a DHCP server** used **only for PXE booting**, not for runtime address assignment.
- After boot/install, each VM configures its static IP permanently.
- No dynamic or runtime DHCP usage in normal operations.

### 🪟 Windows Host IP Configuration (VMnet0 Only)

For communication between the **Windows host** and the lab VMs:

1. Go to **Control Panel → Network and Internet → Network Connections**
2. Find the adapter: **`VMware Network Adapter VMnet0`**
3. Right-click → **Properties**
4. Select `Internet Protocol Version 4 (TCP/IPv4)` → Click **Properties**
5. Configure:

   - **IP Address**: `10.10.20.3`  
   - **Subnet Mask**: `255.255.252.0`  
   - **Default Gateway**: *(leave blank)*  
   - **Preferred DNS Server**: *( leave blank - will update later with infra server VM's IP )*

> ✅ Once the infra-server is up, it will provide DNS and other services within the lab.

### 📌 IP Layout Summary

| IP Address       | Role               |
|------------------|--------------------|
| `10.10.20.1`     | VMware NAT gateway |
| `10.10.20.2`     | Infra-server       |
| `10.10.20.3`     | Windows host       |

> 🧪 This configuration gives you full control over VM lifecycle management, PXE booting, DNS, and networking in a clean lab setup — fully automated, predictable, and production-style.

## Create the Infra-Server VM

Follow these steps to create a custom VM for your lab infra-server using VMware Workstation.

---

1. Open **VMware Workstation**

2. Click **Create a New Virtual Machine**

3. Select **Custom (advanced)** → Click **Next**

4. For **Hardware Compatibility**, choose:  
   👉 **Workstation 17.5 or later** → Click **Next**

5. At the installation media screen:  
   - Select: **I will install the operating system later**  
   → Click **Next**

6. Select guest OS type:  
   - **Operating System**: `Linux`  
   - **Version**: `Red Hat Enterprise Linux 9 (64-bit)`  
   → Click **Next**

7. Enter VM identity:  
   - **Virtual Machine Name**: `infra-server` *(or any name of your choice)*  
   - **Location**: *(Leave the default path unchanged)*  
   → Click **Next**

8. Configure processors:  
   - **Number of processors**: `2`  
   - **Number of cores per processor**: `1`  
   → Click **Next**

9. Configure memory:  
   - **Memory for this virtual machine**: `4096 MB` (4 GB)  
   > 💡 You can reduce this to **2 GB** after OS installation is complete.  
   → Click **Next**

10. Select Network Type:  
    - Choose: **NAT (Network Address Translation)**  
    → Click **Next**

11. Select I/O Controller Type:  
    - Choose: **LSI Logic**  
    → Click **Next**

12. Select Virtual Disk Type:  
    - Choose: **NVMe**  
    → Click **Next**

13. Select a Disk:  
    - Choose: **Create a new virtual disk**  
    → Click **Next**

14. Specify Disk Capacity:  
    - **Maximum disk size**: `30 GB`  
    - ✅ Check: **Allocate all disk space now**  
    - ✅ Check: **Store virtual disk as a single file**  
    → Click **Next**

15. Specify Disk File:  
    - **Leave the default disk file name as it is**  
    > 📁 The disk file will be stored in the VM directory selected earlier  
    → Click **Next**

16. Customize Hardware (before clicking Finish):  
    - Click **Customize Hardware**
    - ❌ **Remove**: `USB Controller`
    - ❌ **Remove**: `Sound Card`
    - 🖥️ Click on **Display**  
      - 🔲 **Uncheck**: "Accelerate 3D graphics"
    - 🌐 Click on **Network Adapter**  
      - ✅ Select: **Custom: Specific virtual network**  
      - Choose: **VMnet0 (NAT)**
    - 💿 Click on **CD/DVD (SATA)**  
      - Select: **Use ISO image file**  
      - Browse and select your **AlmaLinux 10 ISO**

  → Click **Close**, then click **Finish** to create the VM  
🕒 **Note**: Since disk space is pre-provisioned, VMware will take a few moments to create the VM. Please wait until the process completes.



