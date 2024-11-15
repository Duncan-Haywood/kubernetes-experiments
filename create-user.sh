#!/bin/bash

# Variables
USER="bob"
GROUP="developers"
NAMESPACE="lfs158"
ROLE="pod-reader"
CONTEXT="minikube"
ROLEBINDING_NAME="pod-read-access"

# Paths for generated files
CERTS_DIR="./certs"
USER_KEY="$CERTS_DIR/$USER.key"
USER_CSR="$CERTS_DIR/$USER.csr"
USER_CERT="$CERTS_DIR/$USER.crt"
CA_CERT=$(kubectl config view --raw -o jsonpath='{.clusters[?(@.name=="'$CONTEXT'")].cluster.certificate-authority}')
CA_KEY="/var/lib/minikube/certs/ca.key" # Adjust if needed for your cluster

# Create directories for certificates
mkdir -p $CERTS_DIR

echo "Generating key for user $USER..."
openssl genrsa -out $USER_KEY 2048

echo "Generating CSR for user $USER..."
openssl req -new -key $USER_KEY -out $USER_CSR -subj "/CN=$USER/O=$GROUP"

echo "Signing the CSR with the cluster's CA..."
openssl x509 -req -in $USER_CSR -CA $(kubectl config view --raw -o jsonpath='{.clusters[?(@.name=="'$CONTEXT'")].cluster.certificate-authority-data}' | base64 -d) \
  -CAkey $CA_KEY -CAcreateserial -out $USER_CERT -days 365

echo "Setting up user $USER in kubeconfig..."
kubectl config set-credentials $USER \
  --client-certificate=$USER_CERT \
  --client-key=$USER_KEY

echo "Creating context for user $USER..."
kubectl config set-context ${USER}-context \
  --cluster=$CONTEXT \
  --namespace=$NAMESPACE \
  --user=$USER

echo "Creating RoleBinding YAML file..."
cat <<EOF > rolebinding.yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: $ROLEBINDING_NAME
  namespace: $NAMESPACE
subjects:
- kind: User
  name: $USER
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: Role
  name: $ROLE
  apiGroup: rbac.authorization.k8s.io
EOF

echo "Applying RoleBinding..."
kubectl apply -f rolebinding.yaml

echo "Verifying RoleBinding..."
kubectl get rolebindings -n $NAMESPACE

echo "Script execution completed!"