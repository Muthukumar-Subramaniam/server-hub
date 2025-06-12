```
metallb_vers=$(curl -s -L https://api.github.com/repos/metallb/metallb/releases/latest | jq -r '.tag_name' 2>>/dev/null | tr -d '[:space:]') && echo "latest metallb version : ${metallb_vers}"
```
