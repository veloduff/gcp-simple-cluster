variable "project_id" {
  description = "The GCP project ID to deploy the cluster in."
  type        = string
}

variable "region" {
  description = "The GCP region for the network and resources."
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "The GCP zone for the Managed Instance Group."
  type        = string
  default     = "us-central1-b"
}

variable "create_network" {
  description = "Whether to create a new VPC network and subnet. If false, vpc_name and subnet_name must be provided."
  type        = bool
  default     = true
}

variable "vpc_name" {
  description = "The name of the VPC network (used if create_network is false)."
  type        = string
  default     = "default"
}

variable "subnet_name" {
  description = "The name of the Subnet (used if create_network is false)."
  type        = string
  default     = "default"
}

variable "cluster_name" {
  description = "Prefix name for all resources in the cluster."
  type        = string
  default     = "simple-hpc-cluster"
}

variable "compute_node_count" {
  description = "Number of compute/worker instances (nodes) in the cluster."
  type        = number
  default     = 2
}

variable "master_machine_type" {
  description = "Machine type for the master node (typically smaller)."
  type        = string
  default     = "n4-standard-4"
}

variable "compute_machine_type" {
  description = "Machine type for the compute nodes (typically larger)."
  type        = string
  default     = "c4-standard-8"
}

variable "image_project" {
  description = "The project hosting the VM image."
  type        = string
  default     = "rocky-linux-cloud"
}

variable "image_family" {
  description = "The image family to use for the VMs."
  type        = string
  default     = "rocky-linux-8-optimized-gcp"
}
