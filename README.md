# 🚀 Server-Hub: Build Your Own QEMU/KVM Virtual Home Lab

Transform your Linux workstation into a powerful, automated virtual datacenter! This project allows you to build and manage a virtual home lab, making it easy to deploy, break, and rebuild Linux VMs effortlessly. It automates VM provisioning, manages the complete lifecycle of your VMs, and provides a flexible environment for learning, testing, and experimenting with Linux-based technologies.

Although many open-source alternatives exist, I built this project for the fun of creating something of my own and sharing it with anyone with similar interests.

> ⚠️ **DISCLAIMER:** This project is intended for **testing**, **development**, and **experimentation** purposes only.

---

## 🎯 What You'll Get

- 🚀 **Automated VM provisioning** via PXE boot & golden images
- 🌐 **Dynamic DNS management** for your local domain
- 🔧 **Full infrastructure-as-code** automation
- 💻 **Professional datacenter experience** on your workstation
- 🎮 **Complete VM lifecycle management** with enterprise-grade tools
- 🧪 **Experiment freely** – Spin up and destroy VMs in seconds

---

## 🖥️ Automated Lab Environment for Provisioning and Managing Linux VMs

### 🧠 Central Infra Server VM's OS
The central lab infrastructure server VM is designed to run on **AlmaLinux 10** by default, providing all the essential services for managing the lab environment.

### 📦 VM Guest OS Provisioning

The lab infrastructure server centrally manages all guest VM provisioning using automation scripts and configuration templates.

The toolkits provide automated VM provisioning for all three major Linux families, including ready-to-use configurations for:

| Distro Family    | Supported OSes                                | Provisioning Method           | Status                  |
|------------------|-----------------------------------------------|-------------------------------|--------------------------|
| Red Hat-based    | AlmaLinux                                      | Kickstart                     | ✅ Included by default   |
|                  | Rocky, Oracle Linux, RHEL, CentOS Stream       | Kickstart                     | 🔧 Customizable          |
| Debian-based     | Ubuntu LTS                                     | Cloud-init (`cloud-config`)   | 🔧 Customizable          |
| SUSE-based       | openSUSE Leap                                  | AutoYaST                      | 🔧 Customizable          |

---

## 🧾 Minimum System Requirements

> These are the minimum recommended values. You can adjust them later based on your specific use case and workload.

### 🔹 Central Infra Server VM
- 🧠 **Memory**: 2 GB RAM
- ⚙️ **CPU**: 2 vCPUs
- 💾 **Storage**: 30 GB

### 🔸 Provisioned VMs
- 🧠 **Memory**: 2 GB RAM
- ⚙️ **CPU**: 2 vCPUs
- 💾 **Storage**: 20 GB

---

## 📥 Quick Start: Get Up and Running in 5 Steps

### Step 1 – Clone the Repository

Let's start by grabbing the automation tools:

```bash
sudo mkdir -p /server-hub
sudo chown ${USER}:$(id -g) /server-hub
git clone https://github.com/Muthukumar-Subramaniam/server-hub.git /server-hub
cd /server-hub/qemu-kvm-manage/
```

---

### Step 2 – Install QEMU/KVM

Run the automated setup script to configure your virtualization environment:

```bash
./setup-qemu-kvm.sh
```

This will install and configure all necessary packages and dependencies.

---

### Step 3 – Download AlmaLinux ISO

Grab the latest AlmaLinux ISO for your lab infrastructure:

```bash
./download-almalinux-latest.sh
```

> ☕ **Pro tip:** This might take a few minutes depending on your network speed. Perfect time for a coffee break!

---

### Step 4 – Deploy Your Lab Infrastructure Server

Now comes the magic! This fully automated script will:
- ✨ Guide you through the setup with interactive prompts
- 🔄 Install and configure the centralized lab infrastructure server
- 🎛️ Set up DNS, DHCP, PXE boot, and web services
- 🤖 Run Ansible automation for consistent configuration

```bash
./deploy-lab-infra-server.sh
```

**What to expect:**
- **First Reboot:** After OS installation and initial configuration
- **Second Reboot:** After services are configured via Ansible playbook
- **Final Step:** Once you see the login prompt, press `Ctrl + ]` to exit the console

> 🎬 Sit back and watch the automation work its magic!

---

### Step 5 – Access Your Infrastructure Server

Time to explore! SSH into your newly deployed infrastructure server:

```bash
ssh lab-infra-server.lab.local
```

> 💡 Replace `lab-infra-server.lab.local` with your actual server name and domain if different.

---

# ✅ Your Lab is Ready! Time to Build Something Amazing! 🎉

---

## 🛠️ Your New Superpowers: VM Management Tools

Your workstation is now equipped with professional-grade VM management tools:

### 📦 VM Deployment & Management
```bash
kvm-build-golden-image        # 🎨 Create reusable golden base images
kvm-install-golden            # 🚀 Deploy VMs instantly from golden images
kvm-install-pxe               # 🌐 Deploy VMs via network PXE boot
kvm-reimage-golden            # 🔄 Reinstall VMs from golden images
kvm-reimage-pxe               # 🔄 Reinstall VMs via PXE boot
```

### 🎮 VM Operations
```bash
kvm-list                      # 📊 View all VMs and their status
kvm-console                   # 🖥️ Connect to VM serial console
kvm-start                     # ▶️ Power on VMs
kvm-stop                      # ⏹️ Force power-off VMs
kvm-shutdown                  # 🔽 Graceful VM shutdown
kvm-restart                   # 🔄 Hard restart VMs
kvm-reboot                    # 🔃 Graceful VM reboot
```

### 🔧 VM Configuration
```bash
kvm-resize                    # 📏 Resize memory, CPU, or disk
kvm-add-disk                  # 💾 Add additional storage disks
kvm-remove                    # 🗑️ Delete VMs completely
```

### 🌍 Infrastructure Management
```bash
kvm-dnsbinder                 # 🌐 Manage local DNS records
kvm-lab-start                 # 🏁 Start the entire lab infrastructure
kvm-lab-health                # 🏥 Check lab infrastructure health
```

---

## 🎭 The Secret Sauce: Backend Automation Tools

These powerful tools run on your infrastructure server, making everything work seamlessly:

- **🌐 dnsbinder** – Automatically manages DNS records for your local domain as you create/destroy VMs
- **⚡ ksmanager** – Handles iPXE & golden-image based OS provisioning using kickstart automation
- **📦 prepare-distro-for-ksmanager** – Downloads and prepares multiple Linux distributions (AlmaLinux, Rocky, Ubuntu, openSUSE, and more!)

---

## 🎊 Congratulations! Welcome to Your Virtual Datacenter!

You've just built a **professional-grade, fully automated home lab** that rivals enterprise infrastructure!

### 🌟 What Can You Do Now?

- 🧪 **Experiment freely** – Spin up and destroy VMs in seconds
- 📚 **Learn by doing** – Practice DevOps, automation, and infrastructure management
- 🏢 **Simulate production** – Test multi-tier applications in realistic environments
- 🚀 **Develop skills** – Master tools used in real enterprise datacenters
- 🔬 **Test and break things** – Build, destroy, rebuild without fear

**Your journey to infrastructure mastery starts here!** 🧑‍💻🖥️🧠

---

## 💬 Support & Contributing

- **Need help?** Found a bug? Have ideas? [Open an issue](https://github.com/Muthukumar-Subramaniam/server-hub/issues) on GitHub!
- **Want to contribute?** Pull requests are welcome! Feel free to improve the automation, add new distros, or enhance documentation.

---

## 📜 License

This project is open source. See the [LICENSE](LICENSE) file for details.

---

**Built with ❤️ for the home lab community**
