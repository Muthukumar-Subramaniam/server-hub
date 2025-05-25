#!/bin/bash
cd /server-hub/k8s
kubectl apply -f cifs-credentials.yaml
kubectl apply -f cifs-pv-downloads.yaml
kubectl apply -f cifs-pvc-downloads.yaml
