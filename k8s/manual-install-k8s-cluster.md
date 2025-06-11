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
sudo swapoff -a && sudo sed -i '/swap/s/^/#/' /etc/fstab
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
### Step 3) Load required kernel modules
----
```
sudo modprobe -vv overlay && sudo modprobe -vv br_netfilter
```
```
cat << EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF
```
### Step 4) Load required kernel parameters
----
```
cat << EOF | sudo tee /etc/sysctl.d/k8s.conf
net.ipv4.ip_forward = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
EOF
```
```
sudo sysctl --system
```
### Step 5) Download and setup the latest version of runc binary
----
```
runc_vers=$(curl -s -L https://api.github.com/repos/opencontainers/runc/releases/latest | jq -r '.tag_name' 2>>/dev/null | tr -d '[:space:]') && echo "latest runc version : ${runc_vers}"
```
```
sudo wget -O /usr/bin/runc https://github.com/opencontainers/runc/releases/download/"${runc_vers}"/runc.amd64 && sudo chmod +x /usr/bin/runc
```
```
runc --version
```
### Step 6) Download containerd binary and setup containerd service
```
containerd_vers=$(curl -s -L https://api.github.com/repos/containerd/containerd/releases/latest | jq -r '.tag_name' 2>>/dev/null | tr -d '[:space:]') && echo "latest containerd version : ${containerd_vers}"
```
```
mkdir -p containerd && wget -P containerd/ https://github.com/containerd/containerd/releases/download/"${containerd_vers}"/containerd-"${containerd_vers:1}"-linux-amd64.tar.gz
```
```
tar Cxzvf containerd/ containerd/containerd-"${containerd_vers:1}"-linux-amd64.tar.gz
```
```
chmod -R +x containerd/bin && sudo chown -R root:root containerd/bin
```
```
sudo rsync -avPh containerd/bin/ /usr/bin/ && sudo rm -rf containerd
```
```
containerd --version
```
```
sudo mkdir -p /etc/containerd && ( containerd config default | sudo tee /etc/containerd/config.toml )
```
```
sudo sed -i '/containerd\.runtimes\.runc\.options/ a\            SystemdCgroup = true' /etc/containerd/config.toml && ( containerd config dump | grep -B 10 SystemdCgroup )
```
```
sudo wget -P /etc/systemd/system/ https://raw.githubusercontent.com/containerd/containerd/main/containerd.service
```
```
sudo sed -i "s|usr/local/bin|usr/bin|g" /etc/systemd/system/containerd.service
```
```
sudo systemctl daemon-reload && sudo systemctl enable --now containerd.service && sudo systemctl status containerd.service --no-pager
```

### Step 7) Configure kubernetes repo and install kubeadm, kubectl and kubelet packages
----
[Click here if RedHat-based systems](install-k8s-pkgs-redhat.md)  
[Click here if Debian-based systems](install-k8s-pkgs-debian.md)  
[Click here if SUSE-based systems](install-k8s-pkgs-suse.md)  

### Step 8) Below Steps are to be executed on control plane node only
----
```
sudo systemctl enable --now kubelet.service && sudo systemctl status kubelet.service --no-pager
```
```
sudo kubeadm config images pull
```
```
sudo kubeadm init --pod-network-cidr=10.8.0.0/22
```
```
k8s_user="${USER}"
mkdir -p "${HOME}"/.kube
sudo cp -i /etc/kubernetes/admin.conf "${HOME}"/.kube/config
sudo chown $(id -u "${k8s_user}"):$(id -g "${k8s_user}") "${HOME}"/.kube/config
```
Now wait for control plane node to be in ready state
```
kubectl get nodes --watch -o wide
```
Once control plane node is ready check whether all system pods are running expect core-dns in pending state, it is because we are yet to install a CNI for our cluster
```
kubetctl get pods -A --watch
```
Now install calico CNI
```
calico_versio=$(curl -s -L https://api.github.com/repos/projectcalico/calico/releases/latest | jq -r '.tag_name' 2>>/dev/null | tr -d '[:space:]') && echo "latest calico version : ${calico_versio}"
```
```
wget https://raw.githubusercontent.com/projectcalico/calico/"${calico_version}"/manifests/calico.yaml
```
```
kubectl apply -f calico.yaml
```
Now wait for all the pods to be running including core-dns
```
kubetctl get pods -A --watch
```
Update your bashrc file for kubectl command arguement tab completion
```
echo 'source <(kubectl completion bash)' >> "${HOME}"/.bashrc
source "${HOME}"/.bashrc
```
To create token to join worker nodes, run the below
```
kubeadm token create --print-join-command
```
### Step 9) Now run the above join command in worker nodes to join them to the k8s cluster
If the join command succeeds, your kubelet service will start in worker node
```
sudo systemctl status kubelet.service --no-pager
```
### Step 10) Now go to control plane node to check nodes and pod details, you could find pods running in worker nodes as well, it might take a little time for all the pods to be in running state.
```
kubectl get pods -A -o wide --watch
```
```
kubectl get nodes -o wide
```
### Step 11) If firewalld is running in case of RedHat-based or SUSE-based systems, either disable it or run the below commands to allow required networks
```
sudo firewall-cmd --permanent --zone=trusted --add-source=< pod network cidr >
```
```
sudo firewall-cmd --permanent --zone=trusted --add-source=< cluster mgmt network cidr >
```
```
sudo firewall-cmd --reload
```
```
```
## Now the cluster is ready for deployments if all nodes are in ready state.
### We might need below add-on deployments as well for networking and storage needs




