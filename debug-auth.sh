#!/bin/bash

set -e
set -o pipefail

# Variables
CERTS_DIR="$HOME/.minikube/certs"
CA_FILE="$CERTS_DIR/ca.crt"
BOB_CERT="./certs/bob.crt"
BOB_KEY="./certs/bob.key"
API_SERVER=$(kubectl config view --raw -o jsonpath='{.clusters[?(@.name=="minikube")].cluster.server}')
NAMESPACE="lfs158"
CONTEXT_BOB="bob-context"

log_status() {
  echo -e "\033[1;32m$1\033[0m"
}

log_error() {
  echo -e "\033[1;31m$1\033[0m"
}

# Step 1: Verify Minikube CA Certificate Location
log_status "Step 1: Verifying Minikube CA certificate location..."
if [ -f "$CA_FILE" ]; then
  log_status "Minikube CA certificate found at $CA_FILE."
else
  log_error "Minikube CA certificate is missing. Attempting to regenerate Minikube certificates..."
  minikube delete
  minikube start --extra-config=apiserver.client-ca-file=/var/lib/minikube/certs/ca.crt
fi

# Verify CA file again
if [ ! -f "$CA_FILE" ]; then
  log_error "Minikube CA certificate is still missing after regeneration. Exiting."
  exit 1
fi

# Step 2: Verify Bob's Certificate Against Minikube CA
log_status "Step 2: Verifying bob.crt against Minikube CA..."
if openssl verify -CAfile "$CA_FILE" "$BOB_CERT"; then
  log_status "bob.crt is valid."
else
  log_error "bob.crt is not valid. Regenerating bob's certificates..."
  openssl genrsa -out ./certs/bob.key 2048
  openssl req -new -key ./certs/bob.key -out ./certs/bob.csr -subj "/CN=bob/O=developers"
  openssl x509 -req -in ./certs/bob.csr -CA "$CA_FILE" -CAkey ~/.minikube/certs/ca-key.pem -CAcreateserial -out ./certs/bob.crt -days 365
  log_status "Bob's certificates regenerated."
fi

# Step 3: Test API Server Access with Bob's Certificates
log_status "Step 3: Testing API server access with bob's certificates..."
if curl --cacert "$CA_FILE" --cert "$BOB_CERT" --key "$BOB_KEY" "$API_SERVER/api/v1/namespaces/$NAMESPACE/pods"; then
  log_status "Bob's certificates work for API access."
else
  log_error "API server access failed with bob's certificates. Checking API server logs..."
fi

# Step 4: Inspect API Server Logs for Unauthorized Errors
log_status "Step 4: Inspecting API server logs for Unauthorized errors..."
APISERVER_POD=$(kubectl -n kube-system get pod -l component=kube-apiserver -o name)
kubectl -n kube-system logs "$APISERVER_POD" | grep "401 Unauthorized" || {
  log_status "No Unauthorized errors found in API server logs."
}

# Step 5: Re-run Bob's Authentication Test
log_status "Step 5: Testing Bob's kubectl access..."
kubectl config use-context "$CONTEXT_BOB"
if kubectl auth can-i list pods -n "$NAMESPACE"; then
  log_status "Success: Bob can list pods in namespace $NAMESPACE."
else
  log_error "Error: Bob still cannot list pods. Further debugging is required."
fi