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

variable "cluster_name" {
  description = "Prefix name for all resources in the cluster."
  type        = string
  default     = "simple-hpc-cluster"
}

variable "cluster_size" {
  description = "Number of instances (nodes) in the cluster."
  type        = number
  default     = 3
}

variable "machine_type" {
  description = "Machine type for the cluster instances."
  type        = string
  default     = "n4d-standard-8"
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
