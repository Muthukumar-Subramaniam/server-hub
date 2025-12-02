# Setup QEMU/KVM Based Virtual Home Lab on Linux Workstation

This guide walks you through setting up a fully functional VM provisioning virtual lab using QEMU/KVM and tools from the [server-hub](https://github.com/Muthukumar-Subramaniam/server-hub) repository.

---

## Step 1 – Clone the `server-hub` repository

```bash
sudo mkdir -p /server-hub
sudo chown ${USER}:$(id -g) /server-hub
git clone https://github.com/Muthukumar-Subramaniam/server-hub.git /server-hub
cd /server-hub/qemu-kvm-manage/
```

---

## Step 2 – Run the QEMU/KVM Setup Script

```bash
./setup-qemu-kvm.sh
```

---
## Step 3 - Download the Latest AlmaLinux ISO
This will take some time depending on your network speed.

```bash
./download-almalinux-latest.sh
```

---
## Step 4 – Automated Deployment of the Centralized Lab Infra Server VM

The following script will guide you through setting up the centralized lab infrastructure server. It will prompt for all required information and then perform an automated installation and configuration of the server VM.

During the process, the VM will reboot twice:

1. **First Reboot:** Occurs after the OS installation and initial configurations.  
2. **Second Reboot:** After the first boot, essential services are configured using a custom bootstrap script and an Ansible playbook. Once the server is fully up and you see the login prompt, you can safely exit the console by pressing `Ctrl + ]`.

To start the deployment, run:
```bash
./deploy-lab-infra-server.sh
```

---

## Step 5 – SSH Into the Deployed Infra Server VM 

If your server name is `lab-infra-server` and your domain is `lab.local` , you can connect by running:

```bash
ssh lab-infra-server.lab.local
```

---

# Your Lab Setup is Now **ready**!

---

## Available VM Management Tools on the Linux Workstation

Once setup is complete, your Linux workstation will have the following tools:

```bash
kvm-build-golden-qcow2-disk   # Create golden qcow2 base image
kvm-install-golden            # Deploy a VM using golden image
kvm-reimage-golden            # Reinstall a VM using golden image
kvm-install-pxe               # Deploy a VM using PXE boot
kvm-reimage-pxe               # Reinstall a VM using PXE boot
kvm-list                      # List all deployed VMs and their status
kvm-console                   # Connect to a VM via serial console
kvm-start                     # Start a VM
kvm-stop                      # Stop a VM (force power-off)
kvm-shutdown                  # Gracefully shutdown a VM
kvm-restart                   # Restart a VM
kvm-reboot                    # Gracefully reboot a VM
kvm-resize                    # Resize memory, CPU, or disk of a VM
kvm-add-disk                  # Add additional disk(s) to an existing VM
kvm-remove                    # Remove/delete a VM
kvm-dnsbinder                 # Bind and manage the lab infra DNS
kvm-lab-start                 # Start the lab infrastructure
kvm-lab-health                # Health check of vital lab infra services
```

---

## Custom Tools Behind the Scenes

The above tools invoke the following custom tools from the infra server:

- **dnsbinder** – Dynamic DNS management of your local domain
- **ksmanager** – iPXE & golden-image based OS provisioning of VMs using kickstarts
- **prepare-distro-for-ksmanager** - Download and prepare various Linux distributions supported by ksmanager

---

🎉 All Done! Your Home Lab on QEMU/KVM is Now Live!
---

You’ve successfully built a fully automated home lab environment on QEMU/KVM.

Welcome to your own fully-managed datacenter in a box! 🧑‍💻🖥️🧠

