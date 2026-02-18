terraform {
  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "2.7.1"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "2.38.0"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = ">= 1.14.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }

    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
  }
}

# ════════════════════════════════════════════════════════════
# 1. KIND CLUSTER CREATION
# ════════════════════════════════════════════════════════════

resource "null_resource" "kind_cluster" {
  triggers = {
    cluster_name = var.cluster_name
    is_windows    = local.is_windows
  }

  provisioner "local-exec" {
    interpreter = local.is_windows ? ["PowerShell", "-Command"] : ["/bin/bash", "-c"]
    command     = "kind create cluster --name ${var.cluster_name} --config ${path.module}/kind-config.yaml --wait 60s"
  }

  provisioner "local-exec" {
    when        = destroy
    interpreter = dirname("/") == "\\" ? ["PowerShell", "-Command"] : ["/bin/bash", "-c"]
    command     = "kind delete cluster --name ${self.triggers.cluster_name}"
  }
}


# ════════════════════════════════════════════════════════════
# 2. GENERATE ROOT CA CERTIFICATE & KEY
# ════════════════════════════════════════════════════════════

resource "tls_private_key" "root_ca" {
  count     = var.generate_ca_cert ? 1 : 0
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "tls_self_signed_cert" "root_ca" {
  count           = var.generate_ca_cert ? 1 : 0
  private_key_pem = tls_private_key.root_ca[0].private_key_pem

  subject {
    common_name  = "aki-local-ca"
    organization = "Aki Lab"
  }

  validity_period_hours = 87600 # 10 years
  is_ca_certificate     = true

  allowed_uses = [
    "cert_signing",
    "crl_signing",
    "digital_signature",
  ]
}

# Write cert & key to local files (for docker cp and reference)
resource "local_file" "ca_cert" {
  count    = var.generate_ca_cert ? 1 : 0
  content  = tls_self_signed_cert.root_ca[0].cert_pem
  filename = "${path.module}/aki-local.crt"
}

resource "local_file" "ca_key" {
  count           = var.generate_ca_cert ? 1 : 0
  content         = tls_private_key.root_ca[0].private_key_pem
  filename        = "${path.module}/aki-local.key"
  file_permission = "0600"
}


# ════════════════════════════════════════════════════════════
# 3. CONFIGURE PROVIDERS (after cluster exists)
# ════════════════════════════════════════════════════════════


provider "kubernetes" {
  config_path = var.kube_config_path
}
provider "helm" {
  kubernetes {
    config_path = var.kube_config_path
  }
}

provider "kubectl" {
  config_path = var.kube_config_path # Or your cluster credentials
}


# ════════════════════════════════════════════════════════════
# 4. CONFIGURE KIND NODES (CA trust + containerd)
# ════════════════════════════════════════════════════════════

locals {

  is_windows = dirname("/") == "\\"

  ca_cert_pem = var.generate_ca_cert ? tls_self_signed_cert.root_ca[0].cert_pem : file("${path.module}/aki-local.crt")
  ca_key_pem  = var.generate_ca_cert ? tls_private_key.root_ca[0].private_key_pem : file("${path.module}/aki-local.key")
  ca_cert_file = "${path.module}/aki-local.crt"

  kind_node_names = [
    "${var.cluster_name}-control-plane",
    "${var.cluster_name}-worker",
    "${var.cluster_name}-worker2",
  ]
}

resource "null_resource" "kind_node_registry_config" {
  for_each = toset(local.kind_node_names)

  triggers = {
    cert_hash = sha256(local.ca_cert_pem)
  }

  provisioner "local-exec" {
    interpreter = local.is_windows ? ["PowerShell", "-Command"] : ["/bin/bash", "-c"]
    command = (
      local.is_windows
      ? "& '${path.module}/scripts/configure-node.ps1' -NodeName '${each.value}' -CertFile '${local.ca_cert_file}' -RegistryHost '${var.registry_host}' -RegistryIP '${var.registry_ip}'"
      : "bash '${path.module}/scripts/configure-node.sh' '${each.value}' '${local.ca_cert_file}' '${var.registry_host}' '${var.registry_ip}'"
    )
  }

  depends_on = [
    null_resource.kind_cluster,
    local_file.ca_cert,
  ]
}

# ════════════════════════════════════════════════════════════
# 5. INFRASTRUCTURE SERVICES
# ════════════════════════════════════════════════════════════
resource "helm_release" "metallb" {
  name             = "metallb"
  repository       = "https://metallb.github.io/metallb"
  chart            = "metallb"
  namespace        = "metallb-system"
  create_namespace = true
  version          = "0.13.12"

  depends_on = [null_resource.kind_cluster]

}

# Define the IP pool.
# For Kind, we usually use 172.18.0.100 to 172.18.0.150
resource "kubectl_manifest" "metallb_ip_pool" {
  yaml_body  = <<YAML
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: kind-pool
  namespace: metallb-system
spec:
  addresses:
    - 172.18.0.100-172.18.0.150
YAML
  depends_on = [helm_release.metallb]
}

resource "kubectl_manifest" "metallb_l2_advertisement" {
  yaml_body  = <<YAML
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: kind-advertisement
  namespace: metallb-system
spec:
  ipAddressPools:
    - kind-pool
YAML
  depends_on = [kubectl_manifest.metallb_ip_pool]
}

resource "helm_release" "nginx" {
  name             = "nginx"
  repository       = "https://kubernetes.github.io/ingress-nginx"
  chart            = "ingress-nginx"
  version          = "4.11.3" # Use the latest stable version
  namespace        = var.nginx_namespace
  create_namespace = true

  wait          = true
  wait_for_jobs = true
  timeout       = 300  # 5 minutes — gives MetalLB time to assign the IP

  values = [
    file("${path.module}/helm-values/nginx.yaml")
  ]
  depends_on = [helm_release.metallb]
}


resource "helm_release" "cert_manager" {
  name             = "cert-manager"
  repository       = "https://charts.jetstack.io"
  chart            = "cert-manager"
  namespace        = "cert-manager"
  create_namespace = true
  version          = "v1.13.0"

  wait    = true
  timeout = 300

  set {
    name  = "installCRDs"
    value = "true"
  }

  depends_on = [null_resource.kind_cluster]

}

resource "kubernetes_secret" "root_ca_secret" {
  metadata {
    name = "aki-root-ca"
    # Change this from "cert-manager" to your argo namespace
    namespace = "cert-manager"
  }

  data = {
    "tls.crt" = local.ca_cert_pem
    "tls.key" = local.ca_key_pem
  }

  type       = "kubernetes.io/tls"
  depends_on = [helm_release.cert_manager]

}
resource "kubectl_manifest" "selfsigned_issuer" {
  yaml_body = <<YAML
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: selfsigned-issuer
spec:
  selfSigned: {}
YAML

  depends_on = [helm_release.cert_manager]
}

resource "kubectl_manifest" "ca_issuer" {
  yaml_body = <<YAML
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: aki-ca-issuer
spec:
  ca:
    # Point this to the secret in the argocd namespace
    secretName: aki-root-ca
YAML

  depends_on = [
    helm_release.cert_manager,
    kubernetes_secret.root_ca_secret
  ]
}


# ════════════════════════════════════════════════════════════
# 6. APPLICATION SERVICES
# ════════════════════════════════════════════════════════════
resource "helm_release" "docker_registry" {
  name             = "docker-registry"
  repository       = "https://twuni.github.io/docker-registry.helm"
  chart            = "docker-registry"
  version          = "2.2.2"
  namespace        = "default"
  create_namespace = true

  values = [
    file("${path.module}/helm-values/docker-registry.yaml")
  ]

  depends_on = [kubernetes_secret.root_ca_secret,
  null_resource.kind_node_registry_config]
}

resource "kubernetes_namespace" "argo_namespace" {
  metadata {
    name = var.argo_namespace
  }
  depends_on = [null_resource.kind_cluster]

}
resource "kubernetes_secret" "root_ca_secret_argo" {
  metadata {
    name      = "aki-root-ca"
    namespace = var.argo_namespace # This is "argocd"
  }
  data = {
    "tls.crt" = local.ca_cert_pem
    "tls.key" = local.ca_key_pem
  }
  type = "kubernetes.io/tls"

  depends_on = [kubernetes_namespace.argo_namespace]
}

resource "helm_release" "argo_cd" {

  name             = "argo-cd" #Release name
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = "5.51.6" # A stable standalone-compatible version
  namespace        = var.argo_namespace
  create_namespace = true

  values = [
    file("${path.module}/helm-values/argo-cd.yaml")
  ]

  depends_on = [
    helm_release.nginx,
    kubernetes_secret.root_ca_secret_argo
  ]
}

# Add this resource to register your CA with Argo CD
resource "kubectl_manifest" "argocd_tls_certs" {
  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "ConfigMap"
    metadata = {
      name      = "argocd-tls-certs-cm"
      namespace = var.argo_namespace
      labels = {
        "app.kubernetes.io/part-of" = "argocd"
      }
    }
    data = {
      "d-reg.aki.local" = local.ca_cert_pem
    }
  })

  force_conflicts   = true
  server_side_apply = true

  depends_on = [helm_release.argo_cd]
}


