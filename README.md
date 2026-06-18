# Simple GCP HPC-Like Cluster using MIG

This project provides two methods to deploy a Managed Instance Group (MIG) on GCP with pre-configured passwordless SSH and automated peer node discovery.

Choose the method that fits your needs:
1. **Command Line / `gcloud` (Recommended for existing VPC/Subnet)**: Simple and direct scripts.
2. **Terraform**: Best for provisioning a dedicated VPC, subnet, firewall rules, and cluster nodes all in one go.

---

## Shared Architecture

*   **SSH Key Pair**: A single cluster-wide SSH key pair is generated and distributed to all VM instances via metadata.
*   **Passwordless Setup**: On VM boot, [startup.sh](./startup.sh) retrieves the keys from metadata, saves them to `/home/hpcuser/.ssh/`, and configures `StrictHostKeyChecking no` for all hosts.
*   **Node Discovery**: A utility script `/usr/local/bin/discover-nodes` runs automatically via cron every minute. It queries the GCP Compute API to find all other nodes in the cluster, saving their names to `/home/hpcuser/hostfile` for easy parallel execution (e.g. using MPI).

---

## Method 1: Command Line / `gcloud` (Existing VPC)

Use this method to quickly deploy the cluster using an existing VPC and subnet.

### 1. Configure the Variables
All CLI and Ansible scripts read from a single configuration file. Open [config.sh](./config.sh) and configure your project ID, VPC, subnet, and region/zone preferences.

Alternatively, you can export them directly in your shell session:
```bash
export PROJECT_ID="your-gcp-project-id"
export VPC_NAME="your-vpc-name"
export SUBNET_NAME="your-subnet-name"
export ZONE="your-gcp-zone"
```

### 2. Ensure IAP SSH Firewall Rule Exists
Because instances are created without public external IPs (for security and policy compliance), your Mac connects to them using GCP Identity-Aware Proxy (IAP) SSH tunneling.
You must ensure your existing VPC allows ingress TCP traffic on port 22 from the GCP IAP ip range `35.235.240.0/20`. If this rule doesn't exist, create it:
```bash
gcloud compute firewall-rules create allow-ssh-from-iap \
    --network="your-vpc-name" \
    --allow=tcp:22 \
    --source-ranges=35.235.240.0/20 \
    --project="your-gcp-project-id"
```

### 3. Deploy the Cluster
Run the deployment script:
```bash
./deploy_cluster.sh
```
This script will:
*   Generate SSH keys locally under `.cluster-keys/` directory (`id_rsa_cluster` and `id_rsa_cluster.pub`).
*   Create a Compute Instance Template **without public IP addresses** (`--no-address`).
*   Deploy a Managed Instance Group (MIG) inside your existing VPC/Subnet.

---

## Method 2: Terraform (New VPC)

Use this method if you want Terraform to manage everything, including creating a new VPC network, subnets, and firewall rules.

### 1. Configure variables
Create a `terraform.tfvars` file (based on [terraform.tfvars.example](./terraform/terraform.tfvars.example)) with your settings:
```hcl
project_id = "your-gcp-project-id"
region     = "your-gcp-region"
zone       = "your-gcp-zone"
cluster_size = 3
```

### 2. Initialize and Deploy
```bash
cd terraform
terraform init
terraform plan
terraform apply
```

---

## Testing & Verifying the Cluster

Once deployed (using either method):

1. **SSH into a Cluster Node**:
   Run the `gcloud compute ssh` command printed at the end of the deployment script or Terraform outputs. E.g.:
   ```bash
   gcloud compute ssh simple-hpc-cluster-node-xxxx --zone=your-gcp-zone
   ```

2. **Switch to the Cluster User**:
   ```bash
   sudo su - hpcuser
   ```

3. **Verify Node Discovery**:
   Wait a minute for the cron job to run, then check the discovered nodes:
   ```bash
   cat ~/hostfile
   ```

4. **Verify Passwordless SSH**:
   SSH into another node listed in the hostfile without entering a password:
   ```bash
   ssh simple-hpc-cluster-node-yyyy
   ```

5. **Test Parallel Execution with pdsh (Recommended)**:
   Since `pdsh` is pre-configured to read from your `hostfile`, you can query all nodes in parallel with a single command:
   ```bash
   pdsh hostname
   ```
   Or run a custom command:
   ```bash
   pdsh "uptime && free -h"
   ```

6. **Alternative: Run a Parallel Loop Command**:
   If you prefer a standard bash loop:
   ```bash
   for node in $(cat ~/hostfile); do ssh $node "echo -n '$node says hello from '; hostname"; done
   ```

---

## Optional: Configuring NFS & Slurm via Ansible

After launching your basic cluster, you can optionally configure it with a shared **NFS folder** (mounted at `/home/hpcuser/shared` across all nodes) and the **Slurm Workload Manager** scheduler.

### 1. Run the Configuration Script
From the workspace root directory on your **Mac**, run the interactive configuration script:
```bash
./configure_cluster.sh
```
This will automatically call the dynamic inventory script and prompt you to enable/disable:
*   **Compilers**: `gcc`, `make`, `git`, and OpenMPI library setup.
*   **NFS**: A shared network filesystem directory at `/home/hpcuser/shared` mounted on all nodes.
*   **Slurm**: MUNGE authentication and the Slurm workload scheduler.

Alternatively, you can run configuration non-interactively using CLI flags:
```bash
# Configure everything
./configure_cluster.sh --all

# Configure only NFS and Compilers (skip Slurm)
./configure_cluster.sh --nfs --compilers
```
This runs the pre-configured [site.yml](./ansible/site.yml) playbook, which automatically:
*   Installs dependencies (compilers, git, make, OpenMPI) on all nodes.
*   Configures the master node as an NFS server, sharing `/home/hpcuser/shared` with all nodes in the subnet.
*   Mounts the NFS directory on all compute nodes.
*   Configures MUNGE authentication and starts it on all nodes.
*   Generates a dynamic `slurm.conf` listing all discovered compute nodes, and starts `slurmctld` (controller) on the master and `slurmd` (daemons) on compute nodes.

### 2. Verify Slurm
Once the playbook completes, you can check the state of the Slurm cluster:
```bash
# View partition status and available nodes
sinfo

# Run a test job across all nodes in the cluster
srun -N 3 hostname
```

---

## Cleanup

To destroy all created resources and avoid further charges:

### If deployed via CLI:
```bash
./destroy_cluster.sh
```

### If deployed via Terraform:
```bash
cd terraform
terraform destroy
```
