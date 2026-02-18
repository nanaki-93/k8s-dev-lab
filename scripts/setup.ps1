
$ErrorActionPreference = "Stop"

Write-Host "=== Stage 1: Creating Kind cluster and generating certificates ===" -ForegroundColor Cyan
terraform apply -auto-approve `
  "-target=null_resource.kind_cluster" `
  "-target=tls_private_key.root_ca" `
  "-target=tls_self_signed_cert.root_ca" `
  "-target=local_file.ca_cert" `
  "-target=local_file.ca_key"

if ($LASTEXITCODE -ne 0) {
    Write-Host "Stage 1 failed!" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "=== Stage 2: Deploying all services ===" -ForegroundColor Cyan
terraform apply -auto-approve

if ($LASTEXITCODE -ne 0) {
    Write-Host "Stage 2 failed!" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "=== Setup complete! ===" -ForegroundColor Green