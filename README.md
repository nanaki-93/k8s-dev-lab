<p align="center">
  <img alt="License: MIT" src="https://img.shields.io/badge/License-MIT-yellow.svg">
  <img alt="Terraform" src="https://img.shields.io/badge/Terraform-844FBA?logo=terraform&logoColor=white">
  <img alt="Kubernetes" src="https://img.shields.io/badge/Kubernetes-326CE5?logo=kubernetes&logoColor=white">
  <img alt="Kind" src="https://img.shields.io/badge/kind-local%20cluster-blue">
  <img alt="Helm" src="https://img.shields.io/badge/Helm-0F1689?logo=helm&logoColor=white">
  <img alt="Argo CD" src="https://img.shields.io/badge/Argo%20CD-EF7B4D?logo=argo&logoColor=white">
</p>

# k8s-dev-lab

Local Kubernetes development lab provisioned with Terraform, Kind, Helm, MetalLB, NGINX Ingress, cert-manager, a private Docker registry, and Argo CD.

## What This Builds

- A three-node Kind cluster named `aki-cluster`.
- MetalLB address allocation for local `LoadBalancer` services.
- NGINX Ingress exposed on local ports `80` and `443`.
- A local root CA and cert-manager `ClusterIssuer` for lab TLS.
- A private Docker registry available as `d-reg.aki.local`.
- Argo CD available as `argocd.aki.local`.
- Example Argo CD application manifests under `applications/` and `argo-apps/`.

## Prerequisites

Install these tools before running the lab:

- Docker
- Kind
- Terraform
- kubectl
- Helm
- Bash, or PowerShell on Windows

## Quick Start

1. Create the Argo CD admin password file:

   ```sh
   printf '%s\n' 'change-me' > argocd-pwd.key
   ```

2. Review the local network values before applying Terraform. Keep these aligned:

   - MetalLB address pool in `main.tf`
   - `registry_ip` in `terraform.tfvars`
   - host aliases in `helm-values/argo-cd.yaml`

3. Configure local hostnames. Use the MetalLB IP assigned to the NGINX Ingress `LoadBalancer` service, or the IP configured for your lab:

   ```txt
   <ingress-ip> d-reg.aki.local argocd.aki.local grpc.argocd.aki.local
   ```

4. Initialize Terraform:

   ```sh
   terraform init
   ```

5. Provision the lab:

   ```sh
   ./scripts/setup.sh
   ```

   On Windows:

   ```powershell
   .\scripts\setup.ps1
   ```

## Configuration

Core variables are defined in `variables.tf` and can be overridden in `terraform.tfvars`:

- `cluster_name` controls the Kind cluster name.
- `kube_config_path` points Terraform providers to your kubeconfig.
- `argo_namespace` sets the Argo CD namespace.
- `nginx_namespace` sets the NGINX Ingress namespace.
- `generate_ca_cert` controls whether Terraform generates `aki-local.crt` and `aki-local.key`.
- `registry_host` and `registry_ip` configure the local registry address.

If `generate_ca_cert` is `false`, provide `aki-local.crt` and `aki-local.key` before applying Terraform.

## Useful Commands

Check cluster status:

```sh
kubectl get nodes
kubectl get pods -A
```

Check ingress resources:

```sh
kubectl get ingress -A
```

Destroy the lab:

```sh
terraform destroy
```

## Repository Layout

```txt
.
├── applications/      # Argo CD Application resources
├── argo-apps/         # Example Kubernetes app manifests
├── helm-values/       # Helm chart values
├── scripts/           # Setup and Kind node configuration scripts
├── kind-config.yaml   # Kind cluster topology and port mappings
├── main.tf            # Terraform resources
└── variables.tf       # Terraform inputs
```

## License

This project is licensed under the MIT License. See `LICENSE` for details.
