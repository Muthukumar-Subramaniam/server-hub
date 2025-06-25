# 🛠️ Server-Hub
> ⚠️ **Note:** This repository is live and accessible, but this README documentation is currently under preparation.

**A one-stop automation toolkit to set up a central server for managing your home lab** — whether on **VMware Workstation**, **QEMU/KVM**, or even a **bare-metal physical setup**.

> ⚠️ **DISCLAIMER:** This project is intended for **testing**, **development**, and **experimentation** purposes only.  

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

Before proceeding with creating the infra-server VM, download the latest AlmaLinux 10 ISO:

🔗 [AlmaLinux-10-latest-x86_64-dvd.iso](https://repo.almalinux.org/almalinux/10/isos/x86_64/AlmaLinux-10-latest-x86_64-dvd.iso)

> 📁 Save this ISO file somewhere accessible — it will be mounted to the VM:
> - During initial OS installation
> - And **persistently**, for use in the lab’s **PXE provisioning setup**

Follow these steps to create a custom VM for your lab infra-server using VMware Workstation.

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

## Post-Creation Tweaks of Infra-Server VM (Edit VM Settings)

After the infra-server VM is created, follow these steps to tweak its settings before booting:

1. **Open the VM Settings:**

   - In **VMware Workstation**, locate your `infra-server` VM in the left pane  
   - **Right-click** on the VM → Select **Settings**  
     *(or select the VM and click **Edit virtual machine settings** from the right pane)*

2. **Disable Side Channel Mitigations (for Hyper-V enabled hosts):**

   - Go to the **Options** tab  
   - Select **Advanced**  
   - Under **Settings**, ✅ **Check**: `Disable side channel mitigations for Hyper-V enabled hosts`

   > ⚠️ This option improves performance when running VMware Workstation on a **Windows host with Hyper-V enabled**.  
   > Best suited for lab/test setups — not recommended for production workloads due to reduced CPU-level security mitigations.

3. **Set Firmware Type to UEFI (without Secure Boot):**

   - Still under **Options → Advanced**
   - Under **Firmware type**:
     - ✅ Select: **UEFI**
     - 🔲 Do **not** check: **Enable secure boot**

   > ℹ️ Secure Boot is not required for lab provisioning and may interfere with PXE boot or custom OS installs.

 4. **Save the Settings:**

   - Click **OK** to save and apply all changes

## Power On Infra-Server VM and Install AlmaLinux 10

After creating and configuring the infra-server VM, follow these steps to install AlmaLinux 10.

### 1. Power On and Boot Installer

- In **VMware Workstation**, select the `infra-server` VM
- Click **Power on this virtual machine**
- On the boot screen, select:  
  ➤ **Install AlmaLinux 10**

### 2. Language Support

- On the first screen, choose your preferred language:
  - ✅ **English (United States)** or **English (India)**
- Click **Continue**

> 🧭 This will set the **timezone** and **keyboard layout** by default. You can change them later if required.

### 3. Installation Destination

- Click **Installation Destination**
- Ensure the correct disk is selected
- ✅ Use **Automatic Partitioning**
- Click **Done**

### 4. Disable Kdump

- Click **Kdump**
- Uncheck **Enable kdump**
- Click **Done**

> 💡 Disabling kdump frees up memory — useful for resource-constrained lab environments.

### 5. Set Root Password & Create Admin User

#### 🔐 Root Password:
- Click **Root Password**
- Enter a **strong password**
- Use the **same password** as your admin user
- Click **Done**

#### 👤 Admin User:
- Click **User Creation**
- Set:
  - **Username**: Use your name in **UNIX style** (e.g., `muthuks`)
  - **Full Name**: Optional (e.g., `Muthukumar Subramaniam`)
  - ✅ Check **Make this user administrator**
  - Use the **same password** as root
- Click **Done**

### 6. Configure Network & Hostname

- Click **Network & Hostname**
- Enable the network adapter (toggle ON)

#### 🛠️ IPv4 Settings:
- Click **Configure** → Go to **IPv4 Settings**
- Set method to `Manual` and enter:

  | Setting      | Value               |
  |--------------|---------------------|
  | Address      | `10.10.20.2`        |
  | Netmask      | `255.255.252.0`     |
  | Gateway      | `10.10.20.1`        |
  | DNS Servers  | `8.8.8.8, 8.8.4.4`  |

- Click **Save**

#### 🖥️ Hostname:
- Set the **Hostname** to match your VM name  
  → e.g., `infra-server`
- Click **Done**

### 7. Set Time & Date

- Click **Time & Date**
- Verify the **timezone** is correctly set based on your location
  - (e.g., `Asia/Kolkata` or `America/New_York`)
- Adjust manually if needed using the map or dropdown
- Click **Done**

### ✅ Final Review

- After completing all above steps, ensure:
  - No warnings are shown in the summary screen
  - All fields are properly configured

### ▶️ Begin Installation

- Click **Begin Installation**
- Wait for the installation process to complete

### 🔄 Reboot

- Once installation is finished, click **Reboot System**

> 💿 The AlmaLinux ISO will remain mounted — it's required later for **PXE provisioning** support in your lab environment.

## Post-Installation – Configure Infra-Server with Ansible

> 💡 **Recommended Tool (Windows Only):**  
> Use the **free edition of [MobaXterm](https://mobaxterm.mobatek.net/download.html)** for SSH access.  
> It provides a terminal + file browser in one and simplifies connecting to the infra-server.

---

### ✅ Prerequisites

Make sure the following are ready:

- Your infra-server is powered on and reachable (e.g., `10.10.20.2`)
- You know the admin **UNIX username** (e.g., `muthuks`)
- The system has internet access

---

### 🚀 Steps to Bootstrap the Server

1. **Open MobaXterm and Create a New SSH Session**:
   - Click **Session → SSH**
   - In **Remote Host**, enter the infra-server IP (e.g., `10.10.20.2`)
   - ✅ Check **Specify Username**, and enter your admin username (e.g., `muthuks`)
   - Leave port as `22` and click **OK**

2. **Log In**:
   - When prompted, enter the password you set during installation
   - A terminal session will open to the infra-server

3. **Run the below to clone the repo under /server-hub**:
   ```bash
   sudo dnf install git -y; \
   sudo mkdir -p /server-hub; \
   sudo chown ${USER}:$(id -g) /server-hub; \
   git clone https://github.com/Muthukumar-Subramaniam/server-hub.git /server-hub; \
   cd /server-hub/build-almalinux-server

 4. **Now run the initial setup script setup.sh**:
    ```bash
    chmod +x setup.sh; \
    ./setup.sh
    ```
    ### 🔧 What `setup.sh` does?
    The `setup.sh` script prepares the infra-server environment before running the main Ansible playbook. It performs the following:

     - Installs Ansible and required Python packages (if not already installed)
     - Grants passwordless sudo access to the current user
     - Sets basic environment variables used later by playbooks
     - Updates `ansible.cfg` with the current user as default
     - Sets up local DNS using `dnsbinder.sh` and reserves DHCP lease records
     - Renames network interfaces to traditional `ethX` naming
     - Disables SELinux for compatibility
     - Prompts for a reboot once setup is complete
     > ⚠️ This script **does not configure the infra-server fully** — after reboot, run the `build-server.yaml` Ansible playbook to complete the setup.  

5. **Reboot the system once the above script is completed successfully**:
   ```bash
   sudo reboot
   ```

6. **After reboot, log in to the server again and run the final playbook to complete the infra-server setup:**

   ```bash
   cd /server-hub/build-almalinux-server;\
   chmod +x build-server.yaml;\
   ./build-server.yaml
   ```

## 🛠️ Managing Your Lab Infrastructure

After completing the setup, you now have access to two key tools that simplify and automate lab management:

### 🔹 `dnsbinder`
- Manages local DNS zones for your lab domain
- Lets you add, update, and remove DNS records easily
- Automatically integrated into PXE and DHCP workflows

### 🔹 `ksmanager`
- Automates VM provisioning using kickstart or cloud-init
- Supports multiple OS templates (e.g., AlmaLinux, Ubuntu, openSUSE)
- Handles static IP assignment and PXE boot flows

> ⚠️ These tools must be run with `sudo` from the **same admin user** used to set up the server. Do **not** run them as root.

---

All your VM deployments and DNS configurations can be managed with these utilities — making your lab environment flexible, reproducible, and easy to control.

## 🚀 Deploying VMs Using PXE and `ksmanager`

Once your infra-server is up and configured, you can deploy additional VMs using PXE boot and the `ksmanager` utility.

### 🧩 VM Creation Workflow (PXE-Enabled Guests)

Follow the **same steps as you did for creating the infra-server VM**, with the following differences:

- ❌ **Do not attach a CD/DVD (ISO)**  
  Remove the CD/DVD device from the hardware list while customizing the VM.
  
- 🧠 **The VM will boot via PXE**, and automated OS installation will be handled by the infra-server.

### ⚙️ Provisioning with `ksmanager`

1. **Generate the VM’s MAC address**:
   - Create the VM and note the **NIC's MAC address** (you can find it under VM settings → Network Adapter).
  
2. **Run `ksmanager` as the admin user** on the infra-server:
   ```bash
   sudo ksmanager <hostname-of-the-vm>
3. Power ON the VM
   * The VM will boot over PXE.
   * OS installation and all the configurations will happen automatically.
   
