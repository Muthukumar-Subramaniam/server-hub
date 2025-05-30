# server-hub
A one-stop automation toolkit to set up a central server for managing your home lab.
Please follow the below, once you have installed AlmaLinux after properly setting the Network on your VMware Workstation or Virtual Box
From the Admin user you have created during the installation run the below.
```
sudo dnf install git -y; sudo mkdir -p /server-hub; sudo chown ${USER}:${USER} /server-hub; git clone https://github.com/Muthukumar-Subramaniam/server-hub.git /server-hub
```
