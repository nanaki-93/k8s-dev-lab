
#!/bin/bash
set -e

NODE_NAME="$1"
CERT_FILE="$2"
REGISTRY_HOST="$3"
REGISTRY_IP="$4"

# 1. Copy CA cert
docker cp "$CERT_FILE" "${NODE_NAME}:/usr/local/share/ca-certificates/aki-local.crt"

# 2. Update trust store
docker exec "$NODE_NAME" update-ca-certificates

# 3. Add DNS entry
docker exec "$NODE_NAME" bash -c "grep -q ${REGISTRY_HOST} /etc/hosts || echo '${REGISTRY_IP} ${REGISTRY_HOST}' >> /etc/hosts"

# 4. Create containerd config directory
docker exec "$NODE_NAME" mkdir -p "/etc/containerd/certs.d/${REGISTRY_HOST}"

# 5. Write containerd hosts.toml using printf (no heredoc issues)
docker exec "$NODE_NAME" bash -c "printf 'server = \"https://${REGISTRY_HOST}\"\n\n[host.\"https://${REGISTRY_HOST}\"]\n  ca = \"/usr/local/share/ca-certificates/aki-local.crt\"\n  skip_verify = false\n' > /etc/containerd/certs.d/${REGISTRY_HOST}/hosts.toml"

# 6. Restart containerd
docker exec "$NODE_NAME" systemctl restart containerd

echo "Node ${NODE_NAME} configured successfully."