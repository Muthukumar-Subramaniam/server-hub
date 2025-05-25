#!/bin/bash
cd /server-hub/k8s
kubectl delete -f cifs-pvc-downloads.yaml
kubectl delete -f cifs-pv-downloads.yaml
kubectl delete -f cifs-credentials.yaml
