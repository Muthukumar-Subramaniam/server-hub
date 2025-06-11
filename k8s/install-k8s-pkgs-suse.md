#### Set a variable for latest version of k8s by fetching the version info from github api
```
k8s_vers=$(curl -s -L https://api.github.com/repos/kubernetes/kubernetes/releases/latest | jq -r '.tag_name' 2>>/dev/null | tr -d '[:space:]') && echo "latest kubernetes version : ${k8s_vers}"
```
#### Set a variable for the major version number of k8s to configure repo
```
k8s_vers_major=$(echo "${k8s_vers}" | cut -d "." -f 1)
k8s_vers_minor=$(echo "${k8s_vers}" | cut -d "." -f 2)
k8s_vers_major_minor="${k8s_vers_major}.${k8s_vers_minor}"
```
#### Configure kubernetes repo
```
cat <<EOF | sudo tee /etc/zypp/repos.d/k8s.repo
[k8s-${var_k8s_version_major_minor}]
name=k8s-${var_k8s_version_major_minor}
baseurl=https://pkgs.k8s.io/core:/stable:/${var_k8s_version_major_minor}/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/${var_k8s_version_major_minor}/rpm/repodata/repomd.xml.key
EOF
```
#### Install kubeadm, kubelet and kubectl packages
```
sudo zypper --gpg-auto-import-keys refresh && sudo zypper install -y kubelet kubeadm kubectl && sudo zypper addlock kubelet kubeadm kubectl
```

