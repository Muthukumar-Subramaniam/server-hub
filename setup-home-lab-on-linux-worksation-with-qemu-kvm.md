# Setup QEMU/KVM based Home-Lab on Linux-Workstation

This guide walks you through setting up a fully functional VM provisioning lab using QEMU/KVM and tools from the [server-hub](https://github.com/Muthukumar-Subramaniam/server-hub) repository.

---

## Step 1 – Clone `server-hub` and Prepare QEMU/KVM Management Scripts

```bash
sudo dnf install git -y
sudo mkdir -p /server-hub
sudo chown ${USER}:$(id -g) /server-hub
git clone https://github.com/Muthukumar-Subramaniam/server-hub.git /server-hub
cd /server-hub/qemu-kvm-manage/
```

---

## Step 2 – Run QEMU/KVM Setup Script

```bash
./setup-qemu-kvm.sh
```

---

## Step 3 – Build a New Infra Server VM

```bash
./build-server-vm.sh
```

---

## Step 4 – SSH Into the Deployed Infra Server VM

Use the auto-created SSH alias.

If your server name is `server`, you can connect by simply running:

```bash
server
```

If you get `command not found`, reload your shell environment and try again:

```bash
source ~/.bashrc
```
```
server
```

---

## Step 5 – Inside the Infra Server VM: Clone `server-hub` Again

```bash
sudo dnf install git -y
sudo mkdir -p /server-hub
sudo chown ${USER}:$(id -g) /server-hub
git clone https://github.com/Muthukumar-Subramaniam/server-hub.git /server-hub
cd /server-hub/build-almalinux-server/
```

---

## Step 6 – Run Setup Script

```bash
./setup.sh
```

---

## Step 7 – Reboot the Server VM

```bash
sudo reboot
```

---

## Step 8 – Finalize VM Configuration After Reboot

Log in again and run the ansible playbook to configure all the services with infra server :

```bash
cd /server-hub/build-almalinux-server/
./build-server.yaml
```

Your lab setup is now **ready**!

---

## Available VM Management Tools on the Linux Workstation

Once setup is complete, your Linux Workstation will have the following tools:

```bash
kvm-build-golden-qcow2-disk   # Create golden qcow2 base image
kvm-install-golden            # Deploy VM using golden image
kvm-reimage-golden            # Reinstall VM using golden image
kvm-install-pxe               # Deploy VM using PXE
kvm-list                      # List all managed VMs
kvm-console                   # Connect to VM via serial console
kvm-start                     # Start a VM
kvm-stop                      # Stop a VM
kvm-restart                   # Restart a VM
kvm-remove                    # Remove/delete a VM
```

---

## Custom Tools Behind the Scenes

The above tools invokes below custom tools from the infra server :

- **dnsbinder** – For dynamic DNS management of your local domain
- **ksmanager** – For Kickstart & PXE-based provisioning

---

## Done!

You now have a complete, script-driven, and automated lab environment with QEMU/KVM.
Provision, reimage, destroy, and manage VMs with ease. Happy hacking!
