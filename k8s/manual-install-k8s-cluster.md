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
### Step 1 ) Turn of swap in all the nodes
----
```
sudo swapoff -a
```
```
sudo sed -i '/swap/s/^/#/' /etc/fstab
```

### Step 2 ) Update your system packages in all the nodes .  
----
#### If distro is RedHat-based 
```
sudo dnf clean all && sudo dnf update --refresh -y
```
```
sudo dnf install -y curl wget rsync jq
```
#### If distro is Debian-based 
```
sudo apt clean all && sudo apt update && sudo apt upgrade -y
```
```
sudo apt install -y curl wget rsync jq
```
#### If distro is SUSE-based 
```
sudo zypper clean -a && sudo zypper rr && sudo zypper update -y
```
```
sudo zypper install -y curl wget rsync jq
```
#### Reboot the system if the above system packages upgrade requires it 
```
sudo reboot
```
### Step 3) Set variables for the component versions in all the nodes
#### Set the variables of latest versions by querying api end points of respective github repos
```
k8s_vers=$(curl -s -L https://api.github.com/repos/kubernetes/kubernetes/releases/latest | jq -r '.tag_name' 2>>/dev/null | tr -d '[:space:]')
containerd_vers=$(curl -s -L https://api.github.com/repos/containerd/containerd/releases/latest | jq -r '.tag_name' 2>>/dev/null | tr -d '[:space:]')
runc_vers=$(curl -s -L https://api.github.com/repos/opencontainers/runc/releases/latest | jq -r '.tag_name' 2>>/dev/null | tr -d '[:space:]')
calico_versio=$(curl -s -L https://api.github.com/repos/projectcalico/calico/releases/latest | jq -r '.tag_name' 2>>/dev/null | tr -d '[:space:]')
```
#### Just check whether above variables are set with version details
```
echo "kubernetes version : ${k8s_vers}"
echo "containerd version : ${containerd_vers}"
echo "runc version : ${runc_vers}"
echo "calico CNI version : ${calico_versio}"
```







