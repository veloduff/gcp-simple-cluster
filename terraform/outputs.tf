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
  value       = local.vpc_name
}

output "master_node_name" {
  description = "The name of the standalone Master node."
  value       = google_compute_instance.hpc_master.name
}

output "ssh_connect_command" {
  description = "Command to SSH into the master node."
  value       = "gcloud compute ssh ${google_compute_instance.hpc_master.name} --project=${var.project_id} --zone=${var.zone}"
}

output "cluster_instances_command" {
  description = "Command to list all instances in the cluster with their internal IPs."
  value       = "gcloud compute instances list --filter=\"name ~ '^${var.cluster_name}-(master|node-.*)'\" --format='table(name, networkInterfaces[0].networkIP, status)'"
}

output "cluster_name" {
  description = "Prefix name for all resources in the cluster."
  value       = var.cluster_name
}

output "cluster_size" {
  description = "Total number of nodes (master + compute nodes)."
  value       = var.compute_node_count + 1
}
