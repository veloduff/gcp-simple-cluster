provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

# 1. Create a VPC and Subnet
resource "google_compute_network" "hpc_vpc" {
  name                    = "${var.cluster_name}-vpc"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "hpc_subnet" {
  name          = "${var.cluster_name}-subnet"
  ip_cidr_range = "10.10.0.0/24"
  region        = var.region
  network       = google_compute_network.hpc_vpc.id
}

# 2. Generate SSH Key Pair for passwordless SSH across cluster
resource "tls_private_key" "cluster_ssh_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# 3. Firewall Rules
# Allow all internal traffic within the VPC
resource "google_compute_firewall" "allow_internal" {
  name    = "${var.cluster_name}-allow-internal"
  network = google_compute_network.hpc_vpc.name

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

  source_ranges = ["10.10.0.0/24"]
}

# Allow external SSH to the cluster nodes (for administration/testing)
resource "google_compute_firewall" "allow_external_ssh" {
  name    = "${var.cluster_name}-allow-external-ssh"
  network = google_compute_network.hpc_vpc.name

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  # In production, restrict this to specific IP ranges or use IAP (35.235.240.0/20)
  source_ranges = ["0.0.0.0/0"]
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
  machine_type = var.machine_type
  region       = var.region

  disk {
    source_image = "${var.image_project}/${var.image_family}"
    auto_delete  = true
    boot         = true
    disk_type    = "hyperdisk-balanced"
    disk_size_gb = 50
  }

  network_interface {
    network    = google_compute_network.hpc_vpc.id
    subnetwork = google_compute_subnetwork.hpc_subnet.id
  }

  metadata = {
    startup-script      = file("${path.module}/startup.sh")
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

# 6. Managed Instance Group (MIG)
resource "google_compute_instance_group_manager" "hpc_mig" {
  name               = "${var.cluster_name}-mig"
  base_instance_name = "${var.cluster_name}-node"
  zone               = var.zone

  version {
    instance_template = google_compute_instance_template.hpc_template.id
  }

  target_size = var.cluster_size

  # Make sure update_policy handles updates cleanly
  update_policy {
    type                  = "PROACTIVE"
    minimal_action        = "REPLACE"
    max_surge_fixed       = 3
    max_unavailable_fixed = 0
  }
}
