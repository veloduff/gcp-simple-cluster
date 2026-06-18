#!/bin/bash
# deploy_cluster.sh - Provisions an HPC-like cluster using gcloud CLI and an existing VPC/Subnet

set -euo pipefail

# --- Configuration ---
# Sourced from central config file
source "$(dirname "$0")/config.sh"

echo "============================================="
echo " Deploying Simple HPC Cluster via CLI"
echo "============================================="
echo "Project:      $PROJECT_ID"
echo "VPC:          $VPC_NAME"
echo "Subnet:       $SUBNET_NAME"
echo "Zone:         $ZONE"
echo "Cluster Size: $CLUSTER_SIZE nodes"
echo "Machine Type: $MACHINE_TYPE"
echo "============================================="

# 1. Generate SSH key pair locally
mkdir -p .cluster-keys
if [ ! -f .cluster-keys/id_rsa_cluster ]; then
  echo "Generating cluster SSH key pair..."
  ssh-keygen -t rsa -b 4096 -f .cluster-keys/id_rsa_cluster -N "" -q
else
  echo "Using existing cluster SSH key pair."
fi

# 2. Create Instance Template
# We embed the keys and the startup.sh script into the template metadata.
echo "Creating instance template: ${CLUSTER_NAME}-template..."
gcloud compute instance-templates create "${CLUSTER_NAME}-template" \
    --project="${PROJECT_ID}" \
    --machine-type="${MACHINE_TYPE}" \
    --network="${VPC_NAME}" \
    --subnet="projects/${PROJECT_ID}/regions/${REGION}/subnetworks/${SUBNET_NAME}" \
    --image-family="${IMAGE_FAMILY}" \
    --image-project="${IMAGE_PROJECT}" \
    --boot-disk-type=hyperdisk-balanced \
    --boot-disk-size=50GB \
    --no-address \
    --shielded-secure-boot \
    --shielded-vtpm \
    --shielded-integrity-monitoring \
    --metadata-from-file="startup-script=startup.sh,cluster-public-key=.cluster-keys/id_rsa_cluster.pub,cluster-private-key=.cluster-keys/id_rsa_cluster" \
    --scopes=https://www.googleapis.com/auth/cloud-platform \
    --quiet

# 3. Create Zonal Managed Instance Group
echo "Creating Managed Instance Group: ${CLUSTER_NAME}-mig..."
gcloud compute instance-groups managed create "${CLUSTER_NAME}-mig" \
    --project="${PROJECT_ID}" \
    --base-instance-name="${CLUSTER_NAME}-node" \
    --size="${CLUSTER_SIZE}" \
    --template="${CLUSTER_NAME}-template" \
    --zone="${ZONE}" \
    --quiet

# Generate local Ansible inventory (this will wait for instances to boot and assign IPs)
./generate_inventory.sh

echo "============================================="
echo " Verifying Node Configuration Status"
echo "============================================="
first_node=$(gcloud compute instances list --project="${PROJECT_ID}" --filter="name ~ '^${CLUSTER_NAME}-node-.*'" --format="value(name)" --limit=1)

# Wait for hpcuser to be created (which signals startup script completion)
hpcuser_ready=false
for i in {1..24}; do  # Wait up to 4 minutes (24 * 10s)
  if gcloud compute ssh "${first_node}" \
      --project="${PROJECT_ID}" \
      --zone="${ZONE}" \
      --tunnel-through-iap \
      --command="id -u hpcuser" \
      --quiet >/dev/null 2>&1; then
    hpcuser_ready=true
    break
  fi
  echo "Waiting for startup script to finish configuring ${first_node} (Attempt $i/24)..."
  sleep 10
done

if [ "$hpcuser_ready" = false ]; then
  echo "ERROR: VM configuration verification timed out."
  echo "Fetching startup script logs from ${first_node} to diagnose..."
  echo "--------------------------------------------------"
  gcloud compute ssh "${first_node}" \
      --project="${PROJECT_ID}" \
      --zone="${ZONE}" \
      --tunnel-through-iap \
      --command="sudo journalctl -u google-startup-scripts.service --no-pager -n 40" \
      --quiet || true
  echo "--------------------------------------------------"
  echo "ERROR: Cluster nodes failed to configure correctly. Check logs above."
  exit 1
fi
echo "Verification complete: hpcuser successfully configured on all nodes!"

echo "============================================="
echo " Cluster successfully deployed!"
echo "============================================="
echo "To configure NFS, Slurm, and software from your Mac, run:"
echo "  cd ansible && ansible-playbook site.yml"
echo ""
echo "To SSH to your master node directly:"
echo "  gcloud compute ssh $first_node --project=${PROJECT_ID} --zone=${ZONE}"
echo ""
echo "To destroy the cluster, run ./destroy_cluster.sh"
echo "============================================="
