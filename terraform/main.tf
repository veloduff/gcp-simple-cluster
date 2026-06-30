provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

# Locals to resolve which network/subnet IDs to use
locals {
  vpc_id       = var.create_network ? google_compute_network.hpc_vpc[0].id : data.google_compute_network.existing_vpc[0].id
  vpc_name     = var.create_network ? google_compute_network.hpc_vpc[0].name : var.vpc_name
  subnet_id    = var.create_network ? google_compute_subnetwork.hpc_subnet[0].id : data.google_compute_subnetwork.existing_subnet[0].id
  source_range = var.create_network ? "10.10.0.0/24" : data.google_compute_subnetwork.existing_subnet[0].ip_cidr_range
}

# Data sources for looking up existing network when create_network is false
data "google_compute_network" "existing_vpc" {
  count = var.create_network ? 0 : 1
  name  = var.vpc_name
}

data "google_compute_subnetwork" "existing_subnet" {
  count  = var.create_network ? 0 : 1
  name   = var.subnet_name
  region = var.region
}

# 1. Create a VPC and Subnet (Conditional)
resource "google_compute_network" "hpc_vpc" {
  count                   = var.create_network ? 1 : 0
  name                    = "${var.cluster_name}-vpc"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "hpc_subnet" {
  count         = var.create_network ? 1 : 0
  name          = "${var.cluster_name}-subnet"
  ip_cidr_range = "10.10.0.0/24"
  region        = var.region
  network       = google_compute_network.hpc_vpc[0].id
}

# 2. Generate SSH Key Pair for passwordless SSH across cluster
resource "tls_private_key" "cluster_ssh_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# Write the generated keys to local files so Ansible can read them
resource "local_file" "cluster_private_key" {
  content         = tls_private_key.cluster_ssh_key.private_key_pem
  filename        = "${path.module}/../.cluster-keys/id_rsa_cluster"
  file_permission = "0600"
}

resource "local_file" "cluster_public_key" {
  content         = tls_private_key.cluster_ssh_key.public_key_openssh
  filename        = "${path.module}/../.cluster-keys/id_rsa_cluster.pub"
  file_permission = "0644"
}

# 3. Firewall Rules
# Allow all internal traffic within the VPC
resource "google_compute_firewall" "allow_internal" {
  name    = "${var.cluster_name}-allow-internal"
  network = local.vpc_name

  allow {
    protocol = "icmp"
  }
  allow {
    protocol = "tcp"
    ports    = ["0-65535"]
  }
  allow {
    protocol = "udp"
    ports    = ["0-65535"]
  }

  source_ranges = [local.source_range]
}

# Allow external SSH to the cluster nodes (via IAP proxy)
resource "google_compute_firewall" "allow_external_ssh" {
  name    = "${var.cluster_name}-allow-external-ssh"
  network = local.vpc_name

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  # Restrict SSH access to only allow connections from GCP Identity-Aware Proxy (IAP) range
  source_ranges = ["35.235.240.0/20"]
}

# 4. Service Account for VM instances with Compute Viewer permission
# This allows nodes to query GCP API to discover other nodes in the cluster
resource "google_service_account" "cluster_sa" {
  account_id   = "${var.cluster_name}-sa"
  display_name = "Service Account for Simple HPC Cluster VMs"
}

resource "google_project_iam_member" "compute_viewer" {
  project = var.project_id
  role    = "roles/compute.viewer"
  member  = "serviceAccount:${google_service_account.cluster_sa.email}"
}

# 5. Instance Template
resource "google_compute_instance_template" "hpc_template" {
  name_prefix  = "${var.cluster_name}-template-"
  machine_type = var.compute_machine_type
  region       = var.region

  disk {
    source_image = "${var.image_project}/${var.image_family}"
    auto_delete  = true
    boot         = true
    disk_type    = "hyperdisk-balanced"
    disk_size_gb = 50
  }

  network_interface {
    network    = local.vpc_id
    subnetwork = local.subnet_id
  }

  metadata = {
    startup-script      = file("${path.module}/../startup.sh")
    cluster-public-key  = tls_private_key.cluster_ssh_key.public_key_openssh
    cluster-private-key = tls_private_key.cluster_ssh_key.private_key_pem
  }

  service_account {
    email  = google_service_account.cluster_sa.email
    scopes = ["https://www.googleapis.com/auth/cloud-platform"]
  }

  shielded_instance_config {
    enable_secure_boot          = true
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }

  lifecycle {
    create_before_destroy = true
  }
}

# 6. Standalone Master Node
resource "google_compute_instance" "hpc_master" {
  name         = "${var.cluster_name}-master"
  machine_type = var.master_machine_type
  zone         = var.zone

  boot_disk {
    initialize_params {
      image = "${var.image_project}/${var.image_family}"
      type  = "hyperdisk-balanced"
      size  = 50
    }
  }

  network_interface {
    network    = local.vpc_id
    subnetwork = local.subnet_id
    # No access_config block = private IP only (no public IP)
  }

  metadata = {
    startup-script      = file("${path.module}/../startup.sh")
    cluster-public-key  = tls_private_key.cluster_ssh_key.public_key_openssh
    cluster-private-key = tls_private_key.cluster_ssh_key.private_key_pem
  }

  service_account {
    email  = google_service_account.cluster_sa.email
    scopes = ["https://www.googleapis.com/auth/cloud-platform"]
  }

  shielded_instance_config {
    enable_secure_boot          = true
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }
}

# 7. Managed Instance Group (MIG) for Compute Nodes
resource "google_compute_instance_group_manager" "hpc_mig" {
  name               = "${var.cluster_name}-mig"
  base_instance_name = "${var.cluster_name}-node"
  zone               = var.zone

  version {
    instance_template = google_compute_instance_template.hpc_template.id
  }

  target_size = var.compute_node_count

  # Make sure update_policy handles updates cleanly
  update_policy {
    type                  = "PROACTIVE"
    minimal_action        = "REPLACE"
    max_surge_fixed       = 3
    max_unavailable_fixed = 0
  }
}

# 8. Cloud NAT & Router (Conditional - Only created if create_network is true)
# This allows private VMs to safely access the internet for package installations.
resource "google_compute_router" "hpc_router" {
  count   = var.create_network ? 1 : 0
  name    = "cr-${var.cluster_name}-vpc-${var.region}"
  network = google_compute_network.hpc_vpc[0].id
  region  = var.region
}

resource "google_compute_router_nat" "hpc_nat" {
  count                              = var.create_network ? 1 : 0
  name                               = "nat-${var.cluster_name}-vpc-${var.region}"
  router                             = google_compute_router.hpc_router[0].name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
}
