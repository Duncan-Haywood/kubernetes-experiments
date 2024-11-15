#!/bin/bash

set -e
set -o pipefail

# Variables
CERTS_DIR="./certs"
MINIKUBE_CA="$HOME/.minikube/certs/ca.crt"
BOB_CERT="$CERTS_DIR/bob.crt"
BOB_KEY="$CERTS_DIR/bob.key"
API_SERVER=$(kubectl config view --raw -o jsonpath='{.clusters[?(@.name=="minikube")].cluster.server}')
NAMESPACE="lfs158"
CONTEXT_BOB="bob-context"

log_status() {
  echo -e "\033[1;32m$1\033[0m"
}

log_error() {
  echo -e "\033[1;31m$1\033[0m"
}

# Step 1: Verify Bob's Certificate Against Minikube CA
log_status "Step 1: Verifying bob.crt against Minikube CA..."
if openssl verify -CAfile "$MINIKUBE_CA" "$BOB_CERT"; then
  log_status "bob.crt is valid."
else
  log_error "bob.crt is not valid. Regenerate the certificate."
  exit 1
fi

# Step 2: Test API Server Access with Bob's Certificates
log_status "Step 2: Testing API server access with bob's certificates..."
curl --cacert "$MINIKUBE_CA" --cert "$BOB_CERT" --key "$BOB_KEY" "$API_SERVER/api/v1/namespaces/$NAMESPACE/pods" || {
  log_error "API server access failed with bob's certificates. Check logs."
}

# Step 3: Inspect API Server Logs for Unauthorized Errors
log_status "Step 3: Inspecting API server logs for Unauthorized errors..."
APISERVER_POD=$(kubectl -n kube-system get pod -l component=kube-apiserver -o name)
kubectl -n kube-system logs "$APISERVER_POD" | grep "401 Unauthorized" || {
  log_status "No Unauthorized errors found in API server logs."
}

# Step 4: Create a New User for Testing
log_status "Step 4: Creating a new test user and testing authentication..."
openssl genrsa -out ./certs/test.key 2048
openssl req -new -key ./certs/test.key -out ./certs/test.csr -subj "/CN=test-user/O=developers"
openssl x509 -req -in ./certs/test.csr -CA "$MINIKUBE_CA" -CAkey ~/.minikube/certs/ca-key.pem -CAcreateserial -out ./certs/test.crt -days 365

kubectl config set-credentials test-user --client-certificate=./certs/test.crt --client-key=./certs/test.key
kubectl config set-context test-context --cluster=minikube --namespace="$NAMESPACE" --user=test-user

kubectl config use-context test-context
if kubectl auth can-i list pods -n "$NAMESPACE"; then
  log_status "Success: Test user can list pods."
else
  log_error "Error: Test user cannot list pods. Investigate further."
fi