#!/bin/bash

set -e
set -o pipefail

# Variables
CERTS_DIR="./certs"
BOB_CERT="$CERTS_DIR/bob.crt"
BOB_KEY="$CERTS_DIR/bob.key"
MINIKUBE_CA="$HOME/.minikube/certs/ca.pem"
NAMESPACE="lfs158"
CONTEXT_BOB="bob-context"
CONTEXT_MINIKUBE="minikube"
API_SERVER=$(kubectl config view --raw -o jsonpath='{.clusters[?(@.name=="minikube")].cluster.server}')

log_status() {
  echo -e "\033[1;32m$1\033[0m"
}

log_error() {
  echo -e "\033[1;31m$1\033[0m"
}

# Step 1: Inspect API Server Flags
log_status "Step 1: Inspecting API server flags..."
kubectl -n kube-system describe pod -l component=kube-apiserver | grep "client-ca-file\|anonymous-auth" || {
  log_error "Could not verify API server flags. Proceeding with Minikube restart."
}

# Step 2: Restart Minikube with Correct API Server Configuration
log_status "Step 2: Restarting Minikube with correct API server configuration..."
minikube stop || log_error "Failed to stop Minikube."
minikube start \
  --extra-config=apiserver.client-ca-file=/var/lib/minikube/certs/ca.crt \
  --extra-config=apiserver.anonymous-auth=false \
  --extra-config=apiserver.v=10 || {
    log_error "Failed to start Minikube with the new configuration."
    exit 1
  }

# Step 3: Test Bob's Authentication
log_status "Step 3: Testing bob's authentication with kubectl..."
kubectl config use-context "$CONTEXT_BOB"
if kubectl auth can-i list pods -n "$NAMESPACE"; then
  log_status "Success: Bob can list pods in namespace $NAMESPACE."
else
  log_error "Error: Bob still cannot list pods. Proceeding with curl tests."
fi

# Step 4: Test API Server with Curl
log_status "Step 4: Testing API server with curl..."
curl --cacert "$MINIKUBE_CA" --cert "$BOB_CERT" --key "$BOB_KEY" "$API_SERVER/api/v1/namespaces/$NAMESPACE/pods" || {
  log_error "Curl test failed. Inspecting API server logs."
}

# Step 5: Inspect API Server Logs
log_status "Step 5: Inspecting API server logs for Unauthorized errors..."
APISERVER_POD=$(kubectl -n kube-system get pod -l component=kube-apiserver -o name)
kubectl -n kube-system logs "$APISERVER_POD" | grep "Unauthorized" || {
  log_status "No Unauthorized errors found in API server logs."
}

# Step 6: Validate API Server Certificate
log_status "Step 6: Validating API server certificate chain..."
openssl s_client -connect "${API_SERVER#https://}" -CAfile "$MINIKUBE_CA" -showcerts < /dev/null || {
  log_error "Failed to validate API server certificate chain."
}

log_status "Debugging and fixes completed! Re-run kubectl tests for verification."