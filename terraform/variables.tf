variable "cluster_name" {
  description = "Name of the Kind cluster"
  type        = string
  default     = "living-lab"
}

variable "node_image" {
  description = "Kind node Docker image (determines Kubernetes version)"
  type        = string
  default     = "kindest/node:v1.27.1"
}

variable "kubeconfig_path" {
  description = "Path to write the kubeconfig file"
  type        = string
  default     = "~/.kube/living-lab-config"
}
