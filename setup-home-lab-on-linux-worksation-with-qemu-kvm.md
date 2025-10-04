# Setup QEMU/KVM based Virtual Home Lab on Linux Workstation

This guide walks you through setting up a fully functional VM provisioning virtual lab using QEMU/KVM and tools from the [server-hub](https://github.com/Muthukumar-Subramaniam/server-hub) repository.

---

## Step 1 – Run the below to clone this `server-hub` repository

```bash
sudo mkdir -p /server-hub
sudo chown ${USER}:$(id -g) /server-hub
git clone https://github.com/Muthukumar-Subramaniam/server-hub.git /server-hub
cd /server-hub/qemu-kvm-manage/
```

---

## Step 2 – Run the below QEMU/KVM Setup Script

```bash
./setup-qemu-kvm.sh
```

---
## Setp 3 - Run the below script to download latest AlmaLinux ISO
( This will take sometime depending on your network speed )

```bash
./download-almalinux-latest.sh
```

---
## Step 4 – Automated Deployment of the Centralized Lab Infra Server VM

The following script will guide you through setting up the centralized lab infrastructure server. It will prompt for all the required information and then perform an automated installation and configuration of the server VM.

During the process, the VM will reboot twice:

1. **First Reboot:** Occurs after the OS installation and initial configurations.  
2. **Second Reboot:** After the first boot, essential services are configured using a custom bootstrap script and an Ansible playbook. Once the server is fully up and you see the login prompt, you can safely exit the console by pressing `Ctrl + ]`.

To start the deployment, run:
```bash
./build-server-vm.sh
```

---

## Step 5 – SSH Into the Deployed Infra Server VM if you want to explore the configurations

Use the auto-created SSH alias.

If your server name is `infra-server`, you can connect by simply running:

```bash
infra-server
```

If you get `command not found`, reload your shell environment and try again:

```bash
source ~/.bashrc
```
```
infra-server
```

---

# Your lab setup is now **ready**!

---

## Available VM Management Tools on the Linux Workstation

Once setup is complete, your Linux Workstation will have the following tools:

```bash
kvm-build-golden-qcow2-disk   # Create golden qcow2 base image
kvm-install-golden            # Deploy a VM using golden image
kvm-reimage-golden            # Reinstall a VM using golden image
kvm-install-pxe               # Deploy a VM using PXE
kvm-reimage-pxe               # Reinstall a VM using PXE
kvm-list                      # List all the deployed VMs and its status
kvm-console                   # Connect to a VM via serial console
kvm-start                     # Start a VM
kvm-stop                      # Stop a VM
kvm-restart                   # Restart a VM
kvm-resize                    # Resize Memory,CPU or Disk of a VM
kvm-add-disk                  # Add additional disk(s) to an existing VM
kvm-remove                    # Remove/delete a VM
kvm-dnsbinder                 # Bind and manage the lab infra DNS
```

---

## Custom Tools Behind the Scenes

The above tools invokes below custom tools from the infra server :

- **dnsbinder** – For dynamic DNS management of your local domain
- **ksmanager** – iPXE & Golden-Image based OS provisioning of VMs using Kickstarts
- **prepare-distro-for-ksmanager** - To download and prepare various linux distros supported by ksmanager

---

🎉 All Done! Your Home Lab on QEMU/KVM is Now Live!
---

You’ve successfully built a fully automated home lab environment on QEMU/KVM.

Welcome to your own fully-managed datacenter in a box! 🧑‍💻🖥️🧠

