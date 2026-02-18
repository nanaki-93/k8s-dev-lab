#!/bin/bash
set -e

echo "=== Stage 1: Creating Kind cluster and generating certificates ==="
terraform apply -auto-approve \
  -target=null_resource.kind_cluster \
  -target=tls_private_key.root_ca \
  -target=tls_self_signed_cert.root_ca \
  -target=local_file.ca_cert \
  -target=local_file.ca_key

echo ""
echo "=== Stage 2: Deploying all services ==="
terraform apply -auto-approve

echo ""
echo "=== Setup complete! ==="