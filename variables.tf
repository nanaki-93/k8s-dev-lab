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

variable "k8s_dashboard_namespace" {
  type        = string
  default     = "k8s-dashboard"
  description = "Namespace for Kubernetes Dashboard deployment"
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.k8s_dashboard_namespace))
    error_message = "The namespace must consist of lower case alphanumeric characters or '-'."
  }
}

variable "scdf_namespace" {
  type        = string
  default     = "scdf"
  description = "Namespace for Spring Cloud Data Flow"
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.scdf_namespace))
    error_message = "The namespace must consist of lower case alphanumeric characters or '-'."
  }
}
