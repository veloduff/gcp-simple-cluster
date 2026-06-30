# Simple GCP HPC-Like Cluster using Terraform & Ansible

This project provides a clean workflow to deploy and configure a Managed Instance Group (MIG) on GCP as an HPC-like cluster. 

The deployment follows a two-tier automation strategy:

| Tool | Category | Primary Focus | Best At... |
| :--- | :--- | :--- | :--- |
| **Terraform** | Infrastructure as Code (IaC) | Provisioning ("The Hardware") | Creating VPC networks, subnets, firewalls, GCE Instance Templates, MIGs, Service Accounts, and Cloud NAT. |
| **Ansible** | Configuration Management (CM) | Configuration ("The Software") | Setting up the OS, installing compilers, configuring users, setting up NFS exports/mounts, starting Slurm services, and orchestrating multi-node actions. |

---

## Shared Architecture

*   **SSH Key Pair**: A single cluster-wide SSH key pair is generated and distributed to all VM instances via metadata.
*   **Passwordless Setup**: On VM boot, [startup.sh](./startup.sh) retrieves the keys from metadata, saves them to `/home/hpcuser/.ssh/`, and configures `StrictHostKeyChecking no` for all hosts.
*   **Node Discovery**: A utility script `/usr/local/bin/discover-nodes` runs automatically via cron every minute. It queries the GCP Compute API to find all other nodes in the cluster, saving their names to `/home/hpcuser/hostfile` for easy parallel execution (e.g. using MPI).

---

## Workflow Step 1: Provision Infrastructure via Terraform

Use this method to deploy a dedicated VPC network, subnets, firewall rules, Cloud NAT (required for package installations on private instances), and cluster nodes.

### Terraform Basics (For Beginners)

If you are new to Terraform, here is a quick overview of how it works:

#### The 4 Core Commands
*   **`terraform init`**: Initializes the workspace by downloading the Google Cloud provider plugins required to talk to GCP APIs. Run this once when setting up.
*   **`terraform plan`**: Performs a dry run, showing you exactly what resources it wants to create, modify, or delete without making any real changes. Safe to run at any time.
*   **`terraform apply`**: Executes the changes in GCP, provisioning the actual cloud resources. It will ask for confirmation (`yes`) before running.
*   **`terraform destroy`**: Tears down and deletes every resource managed by this configuration. Run this when you are finished testing to avoid cloud charges.

#### Core Configuration Files
*   **`main.tf`**: The infrastructure blueprint describing the resources to build (VPC, VMs, firewalls).
*   **`variables.tf`**: Input definitions that allow customizing parameters like project ID, zones, and cluster sizes.
*   **`outputs.tf`**: Values printed at the end of a successful run (like instance names and SSH commands).
*   **`cluster.conf`**: Your local parameter settings file (copied from `cluster.conf.example` in the root directory).

#### The State File (`terraform.tfstate`)
Once deployed, Terraform creates a local state file to track your live resources. **Never edit this file manually.** If deleted or modified, Terraform loses track of your infrastructure.

---

### Deployment Steps

### 1. Configure variables
Create a `cluster.conf` file (based on [cluster.conf.example](./cluster.conf.example)) in the root directory:
```hcl
project_id = "your-gcp-project-id"
region     = "your-gcp-region"
zone       = "your-gcp-zone"

# Total compute nodes (excluding the master node)
compute_node_count = 2
master_machine_type = "n4-standard-4"
compute_machine_type = "c4-standard-8"

# VPC Toggles: Set to false to deploy inside an existing VPC
create_network = true
vpc_name       = "default"
subnet_name    = "default"
```

### 2. Verify settings and GCP Auth
From the root directory, check your configuration parameters and GCP authentication status:
```bash
./simple-cluster.sh check-config
```

### 3. Launch the Cluster
Run the unified launch command. This will initialize and apply Terraform to deploy the VMs, and then automatically configure the shared NFS folders, build tools, and the Slurm workload scheduler:
```bash
./simple-cluster.sh launch
```

---

## Post-Deployment Configurations (Ansible)

If you need to re-run or update the software configurations (NFS, compilers, or Slurm) at any time on the running cluster without rebuilding it, run the `configure` subcommand:

```bash
# Re-run all playbook configurations (interactive menu)
./simple-cluster.sh configure

# Non-interactive CLI flag example (configure compilers & NFS only)
./simple-cluster.sh configure --compilers --nfs
```

---

## Testing & Verifying the Cluster

Once configured:

1. **SSH into the Master Node**:
   Run the `gcloud compute ssh` command printed at the end of the deployment. E.g.:
   ```bash
   gcloud compute ssh simple-hpc-cluster-master --project=your-gcp-project --zone=your-gcp-zone
   ```

2. **Switch to the Cluster User**:
   ```bash
   sudo su - hpcuser
   ```

3. **Verify Node Discovery**:
   Check the autodiscovered nodes file:
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

6. **Verify Slurm State**:
   If Slurm was installed, check partition status and run a test job across all nodes:
   ```bash
   # View partition status and available nodes
   sinfo

   # Run a test job across all nodes in the cluster
   srun -N 3 hostname
   ```

---

## Cleanup

To destroy all created resources and avoid further charges, run the unified destroy command:

```bash
./simple-cluster.sh destroy
```
