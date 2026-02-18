variable "kube_config_path" {
  type        = string                        # The type of the variable, in this case a string
  default     = "~/.kube/config"              # Default value for the variable
  description = "Path to the kubeconfig file" # Description of what this variable represents
}


variable "argo_namespace" {
  type        = string
  default     = "argocd"
  description = "Namespace for Argo CD deployment"
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.argo_namespace))
    error_message = "The namespace must consist of lower case alphanumeric characters or '-'."
  }
}

variable "nginx_namespace" {
  type        = string
  default     = "nginx"
  description = "Namespace for NGINX deployment"
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.nginx_namespace))
    error_message = "The namespace must consist of lower case alphanumeric characters or '-'."
  }
}

variable "kind_node_names" {
  type        = list(string)
  description = "Names of the Kind Docker containers (nodes)"
  default     = ["aki-cluster-control-plane", "aki-cluster-worker", "aki-cluster-worker2"]
}

variable "cluster_name" {
  type        = string
  default     = "aki-cluster"
  description = "Name of the Kind cluster"
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.cluster_name))
    error_message = "Cluster name must be lowercase alphanumeric or hyphens."
  }
}

variable "generate_ca_cert" {
  type        = bool
  default     = true
  description = "If true, generates a new Root CA cert/key. If false, uses existing aki-local.crt and aki-local.key files."
}

variable "registry_host" {
  type        = string
  default     = "d-reg.aki.local"
  description = "Hostname of the private Docker registry"
}

variable "registry_ip" {
  type        = string
  default     = "172.18.0.100"
  description = "IP address of the private Docker registry (MetalLB LB IP)"
}