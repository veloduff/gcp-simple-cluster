output "project_id" {
  description = "The GCP Project ID."
  value       = var.project_id
}

output "zone" {
  description = "The GCP zone containing the cluster."
  value       = var.zone
}

output "instance_group_manager_name" {
  description = "The name of the Managed Instance Group."
  value       = google_compute_instance_group_manager.hpc_mig.name
}

output "vpc_network_name" {
  description = "The name of the created VPC."
  value       = google_compute_network.hpc_vpc.name
}

output "ssh_connect_command" {
  description = "Command to SSH into the first instance in the cluster."
  value       = "gcloud compute ssh $(gcloud compute instances list --filter='name ~ \"${var.cluster_name}-node-.*\"' --format='value(name)' --limit=1) --zone=${var.zone}"
}

output "cluster_instances_command" {
  description = "Command to list all instances in the cluster with their internal IPs."
  value       = "gcloud compute instances list --filter='name ~ \"${var.cluster_name}-node-.*\"' --format='table(name, networkInterfaces[0].networkIP, status)'"
}
