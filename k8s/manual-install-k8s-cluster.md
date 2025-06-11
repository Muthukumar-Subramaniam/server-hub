# Manual, the hard way of installing kubeadm-based [Kubernetes](https://kubernetes.io/) cluster on Linux from scratch

----  
This documentation is designed for manually installing kubeadm-based [Kubernetes](https://kubernetes.io/) cluster on Linux from scratch for development and testing environment, with a single control plane node and multiple worker nodes, using [the most recent stable Kubernetes release](https://github.com/kubernetes/kubernetes/releases/latest).  

**Suitable Environment:** Development & Testing

**System Requirements:** Minimum 2 GB RAM & 2 vCPU

**Supported Platforms:** Baremetal, Virtual Machines, Cloud Instances

### Supported Linux distributions: 
* RedHat-based ( Fedora, RHEL, Rocky Linux, Almalinux, Oracle Linux ) 
* Debian-based  ( Debian, Ubuntu )
* SUSE-based  ( OpenSUSE, SLES )

### Prerequisites:
* Prepare the cluster nodes by installing any of the above mentioned supported Linux distributions, even with a minimal installation.
* Please make sure the cluster nodes are on the same subnet and there are no network comunication issues between the nodes.
* Please ensure that you have DNS set up that resolves all the involved hosts, or update the host files on all hosts with the necessary entries for each involved host.
* Ensure you have a common user in all the nodes which has passwordless sudo privileges.
 
### The main components of the installation.   
* Container orchestrator: [kubernetes](https://github.com/kubernetes/kubernetes)
* Container runtime: [containerd](https://github.com/containerd/containerd)  
* Low-level container runtime: [runc](https://github.com/opencontainers/runc) ( dependency for containerd )  
* CNI plugin: [calico](https://github.com/projectcalico/calico)

### Optional components that can be installed once the cluster is ready.  
* [csi-driver-nfs](https://github.com/kubernetes-csi/csi-driver-nfs)
* [csi-driver-smb](https://github.com/kubernetes-csi/csi-driver-smb)
* [MetalLB](https://github.com/metallb/metallb) LoadBalancer

## Installation steps 
----
###Step 1) Update your system packages. 
#### If distro is Debian-based 
```
sudo apt update && sudo apt upgrade -y
```
#### If distro is RedHat-based 
```
sudo dnf clean all && sudo dnf makecache && sudo dnf update -y
```
#### If distro is SUSE-based 
```
sudo zypper clean -a && sudo zypper rr && sudo zypper update -y
```
#### Reboot the system if the above system packages upgrade requires it 
```
sudo reboot
```



