param(
    [Parameter(Mandatory)][string]$NodeName,
    [Parameter(Mandatory)][string]$CertFile,
    [Parameter(Mandatory)][string]$RegistryHost,
    [Parameter(Mandatory)][string]$RegistryIP
)

$ErrorActionPreference = "Stop"

# 1. Copy CA cert
docker cp $CertFile "${NodeName}:/usr/local/share/ca-certificates/aki-local.crt"

# 2. Update trust store
docker exec $NodeName update-ca-certificates

# 3. Add DNS entry
docker exec $NodeName bash -c "grep -q $RegistryHost /etc/hosts || echo '$RegistryIP $RegistryHost' >> /etc/hosts"

# 4. Create containerd config directory
docker exec $NodeName mkdir -p "/etc/containerd/certs.d/$RegistryHost"

# 5. Write containerd hosts.toml using printf (no heredoc issues)
docker exec $NodeName bash -c "printf 'server = \""https://$RegistryHost\""\n\n[host.\""https://$RegistryHost\""]\n  ca = \""/usr/local/share/ca-certificates/aki-local.crt\""\n  skip_verify = false\n' > /etc/containerd/certs.d/$RegistryHost/hosts.toml"

# 6. Restart containerd
docker exec $NodeName systemctl restart containerd

Write-Host "Node $NodeName configured successfully."