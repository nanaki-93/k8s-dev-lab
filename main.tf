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
  }
}

provider "kubernetes" {
  config_path = var.kube_config_path
}
provider "helm" {
  kubernetes {
    config_path = var.kube_config_path
  }
}

provider "kubectl" {
  config_path = "~/.kube/config" # Or your cluster credentials
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
    helm_release.nginx
  ]
}
resource "helm_release" "nginx" {
  name             = "nginx"
  repository       = "https://kubernetes.github.io/ingress-nginx"
  chart            = "ingress-nginx"
  version          = "4.11.3" # Use the latest stable version
  namespace        = var.nginx_namespace
  create_namespace = true

  values = [
    file("${path.module}/helm-values/nginx.yaml")
  ]
  depends_on = [helm_release.metallb]
}

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
}

resource "time_sleep" "wait_for_cert_manager" {
  create_duration = "30s"

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





# 3. Store the Root CA in a Kubernetes Secret for Cert-Manager to use
resource "kubernetes_secret" "root_ca_secret" {
  metadata {
    name = "aki-root-ca"
    # Change this from "cert-manager" to your argo namespace
    namespace = "cert-manager"
  }

  data = {
    "tls.crt" = file("${path.module}/aki-local.crt")
    "tls.key" = file("${path.module}/aki-local.key")
  }

  type = "kubernetes.io/tls"
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
      "d-reg.aki.local" = file("${path.module}/aki-local.crt")
    }
  })

  force_conflicts   = true
  server_side_apply = true

  depends_on = [helm_release.argo_cd]
}


resource "kubernetes_secret" "root_ca_secret_argo" {
  metadata {
    name      = "aki-root-ca"
    namespace = var.argo_namespace # This is "argocd"
  }
  data = {
    "tls.crt" = file("${path.module}/aki-local.crt")
    "tls.key" = file("${path.module}/aki-local.key")
  }
  type = "kubernetes.io/tls"
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


resource "helm_release" "metallb" {
  name             = "metallb"
  repository       = "https://metallb.github.io/metallb"
  chart            = "metallb"
  namespace        = "metallb-system"
  create_namespace = true
  version          = "0.13.12"
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
