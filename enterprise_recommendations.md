# Enterprise Resilience & HPC Production Recommendations

This document outlines structural, security, and operational improvements to transition the current `simple-cluster` deployment from a benchmarking/sandbox environment into an enterprise-ready, resilient production platform.

---

## 1. High Availability & Infrastructure Resilience

### 1.1 Remote Terraform State with State Locking
Currently, your Terraform state file is stored locally and gitignored. For team-based enterprise workflows, the state should be centralized with concurrent run locking.
*   **Recommendation**: Configure a Google Cloud Storage (GCS) backend with Object Versioning enabled. GCS natively supports state locking via locking operations.
*   **Implementation**: Add this block to `terraform/main.tf`:
    ```hcl
    terraform {
      backend "gcs" {
        bucket = "your-enterprise-tfstate-bucket"
        prefix = "state/hpc-cluster"
      }
    }
    ```

### 1.2 MIG Auto-Healing & Health Checks
If a compute node encounters a kernel panic, memory crash, or the Slurm daemon freezes, the MIG currently keeps it alive in a broken state.
*   **Recommendation**: Attach a TCP or custom HTTP health check to the Managed Instance Group (MIG). If a node fails to report healthy (e.g., port 22 is unreachable or a local monitoring endpoint fails), the MIG automatically recreates it.
*   **Implementation**: Add `google_compute_health_check` and reference it in the `google_compute_instance_group_manager` resource.

### 1.3 Zonal Placement Policies
*   **For Low-Latency MPI Workloads**: HPC workloads requiring fast node-to-node communication (MPI) should use a **Compact Placement Policy**. This ensures all VMs are physically co-located in the same server rack/sub-network inside the zone, minimizing latency.
*   **For High-Throughput (Embarrassingly Parallel) Workloads**: Use a **Spread Placement Policy** or regional MIG to distribute VMs across multiple hardware failure domains or zones.

---

## 2. Enterprise Storage Solutions

Hosting NFS directly on the master node introduces a single point of failure (SPOF) and bottlenecks disk I/O performance at scale.

| Storage Tier | Performance Profile | Resilience | Best Use Case |
| :--- | :--- | :--- | :--- |
| **Filestore Basic** | Up to 1.2 GB/s throughput | Zonal (Single Zone) | Shared `/home/` directories, source builds. |
| **Filestore Enterprise** | Up to 1.2 GB/s throughput | Regional (Synchronous multi-zone replication) | High availability requirements, critical shared application data. |
| **Google Cloud Parallelstore** | Up to **TB/s** throughput (DAOS-backed) | High performance distributed striping | Scratch storage, high-speed staging, model checkpointing. |

*   **Recommendation**: Mount **Filestore Enterprise** for `/home/hpcuser` to ensure high availability. For high-speed benchmark runs (like SPECstorage or MPI scratch runs), provision a **Parallelstore** instance to prevent disk queue bottlenecks.

---

## 3. Enterprise Security & Identity

### 3.1 OS Login
Currently, the cluster generates custom SSH keys and pushes them to project metadata. This does not scale in enterprise settings and bypasses employee access lifecycle controls.
*   **Recommendation**: Enable **GCP OS Login**. OS Login ties SSH access directly to Google IAM credentials.
    *   Revoking a user's IAM access instantly blocks their ability to SSH into any cluster VM.
    *   It handles POSIX user IDs and permissions automatically.
*   **Implementation**: Set the metadata flag `enable-oslogin = TRUE` on the instance template, and assign the `roles/compute.osLogin` or `roles/compute.osAdminLogin` IAM roles to authorized engineers.

### 3.2 Private Service Connect (PSC) & VPC Service Controls (VPC-SC)
*   **VPC Service Controls**: Create a service perimeter around your project to prevent data exfiltration (e.g. copying benchmark output results to unauthorized external storage buckets).
*   **Private Google Access**: Ensure subnets have Private Google Access enabled. This allows private VMs (no public IP) to talk to GCP APIs (GCS, BigQuery, Artifact Registry) without going through the NAT gateway.

---

## 4. Observability & Monitoring

Enterprise workloads require central logging and metric collections.

### 4.1 Cloud Ops Agent Integration
Integrate the GCP Ops Agent into the VM startup script.
*   **Metrics**: Stream system metrics (CPU, memory utilization, disk I/O depth, TCP retransmissions) to Cloud Monitoring.
*   **Structured Logs**: Stream Slurm logs (`/var/log/slurm/`), MUNGE logs, and test results directly to Cloud Logging.
*   **Alerting**: Create alerting policies for node resource exhaustion, NAT gateway packet drops, or failed health check events.

---

## 5. Elastic Autoscaling (Slurm Integration)

Currently, all nodes (e.g., 16 VMs) run continuously, incurring billing charges even when no jobs are active.
*   **Recommendation**: Configure **Slurm Elastic Autoscaling**. Slurm has built-in power management scripts (`ResumeProgram` and `SuspendProgram`).
*   **How it works**:
    1.  Keep the Slurm controller (master node) running continuously.
    2.  Set the compute nodes in the MIG to `0` by default.
    3.  When a user submits a job via `sbatch`, Slurm calls the `ResumeProgram` script.
    4.  This script runs `gcloud compute instance-groups managed resize` to boot up the required number of nodes.
    5.  Once the job completes and the nodes stay idle for a specified threshold (e.g., 15 minutes), the `SuspendProgram` script scales the MIG back down to save costs.

---

## 6. Standardizing Orchestration: Google Cloud Cluster Toolkit

If you are expanding this project to support production HPC workflows, consider migrating your orchestration wrapper to the official **Google Cloud Cluster Toolkit (ghpc)**.
*   **What it is**: An open-source tool developed by Google to deploy and manage production-ready HPC clusters using unified YAML blueprints.
*   **Why use it**: It combines Terraform, Ansible, Slurm templates, packer images, and optimal GCP HPC architectures (with compact placement, VM tuning, and optimized storage configurations) into a single tool, maintained directly by Google's HPC engineering team.
