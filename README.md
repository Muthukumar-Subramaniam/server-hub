# server-hub
A one-stop automation toolkit to set up a central server for managing your home lab.  
After installation of latest AlmaLinux OS, from the Admin user you have created during the installation run the below.  
( Download Link : [AlmaLinux-10-latest-x86_64-dvd.iso](https://repo.almalinux.org/almalinux/10/isos/x86_64/AlmaLinux-10-latest-x86_64-dvd.iso) )  
```
sudo dnf install git -y; sudo mkdir -p /server-hub; sudo chown ${USER}:${USER} /server-hub; git clone https://github.com/Muthukumar-Subramaniam/server-hub.git /server-hub;cd /server-hub/build-almalinux-server/
```
