resource "kind_cluster" "living_lab" {
  name            = "living-lab"
  node_image      = "kindest/node:v1.27.1"
  wait_for_ready  = true
  kubeconfig_path = pathexpand("~/.kube/living-lab-config")

  kind_config {
    kind        = "Cluster"
    api_version = "kind.x-k8s.io/v1alpha4"

    # Control plane node with ingress port mappings
    node {
      role = "control-plane"

      kubeadm_config_patches = [
        <<-EOT
        kind: InitConfiguration
        nodeRegistration:
          kubeletExtraArgs:
            node-labels: "ingress-ready=true"
        EOT
      ]

      # Map host ports 80/443 into the control-plane container
      # so NGINX Ingress (hostPort mode) is reachable from localhost
      extra_port_mappings {
        container_port = 80
        host_port      = 80
      }

      extra_port_mappings {
        container_port = 443
        host_port      = 443
      }
    }

    # Worker node 1
    node {
      role = "worker"
    }

    # Worker node 2
    node {
      role = "worker"
    }
  }
}
