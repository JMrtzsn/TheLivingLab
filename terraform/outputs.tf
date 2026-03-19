output "endpoint" {
  description = "Kubernetes API server endpoint"
  value       = kind_cluster.living_lab.endpoint
}

output "kubeconfig_path" {
  description = "Path to the kubeconfig file"
  value       = pathexpand("~/.kube/living-lab-config")
}

output "kubeconfig" {
  description = "Raw kubeconfig content"
  value       = kind_cluster.living_lab.kubeconfig
  sensitive   = true
}
