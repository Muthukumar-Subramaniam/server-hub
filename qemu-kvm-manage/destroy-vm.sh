#!/bin/bash
read -p "Please enter the Hostname of the VM to be created : " qemu_kvm_hostname
sudo virsh destroy ${qemu_kvm_hostname} 2>/dev/null
sudo virsh undefine ${qemu_kvm_hostname} --nvram 2>/dev/null
sudo rm -f /virtual-machines/${qemu_kvm_hostname}/${qemu_kvm_hostname}.qcow2 /virtual-machines/${qemu_kvm_hostname}/${qemu_kvm_hostname}_VARS.fd /virtual-machines/${qemu_kvm_hostname}/${qemu_kvm_hostname}.xml
