# server-hub
A one-stop automation toolkit to set up a central server for managing your home lab.  
After installation of latest AlmaLinux OS, from the Admin user you have created during the installation run the below.  
( Download Link : [AlmaLinux-10-latest-x86_64-dvd.iso](https://repo.almalinux.org/almalinux/10/isos/x86_64/AlmaLinux-10-latest-x86_64-dvd.iso) )  
```
sudo dnf install git -y; sudo mkdir -p /server-hub; sudo chown ${USER}:$(id -g) /server-hub; git clone https://github.com/Muthukumar-Subramaniam/server-hub.git /server-hub; cd /server-hub
```
Either you can setup lab environment in VMware Workstation or you could utilize QEMU/KVM depending upon your requirement

To Setup the Lab in VMware Workstation :

1) Setup your VMware Workstation with proper virtual network adapter settings
   * Please remove all existing virtual interfaces and just create one vmnet0 interface with NAT configuration and DCHP disabled 
   * Better choose /22 CIDR private network of your choice and make the first IP as NAT gateway
   * If in case you are running VMware workstation on Windows, Assign the second IP of the above network as the virtual interface IP.

2) Download the AlmaLinux-10 latest with above provided link and install your infra server VM.
   * During installation use 4GB RAM, later you could reduce the RAM size after installation.
   * Please make sure UEFI is used for the VM instead of BIOS in the advanced settings.

