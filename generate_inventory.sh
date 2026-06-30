#!/bin/bash
# generate_inventory.sh - Queries GCP for active cluster instances and generates an Ansible inventory.ini

set -euo pipefail

# Configuration sourced dynamically from active Terraform outputs
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/terraform"

# Pre-flight GCP Authentication check
if ! gcloud auth application-default print-access-token >/dev/null 2>&1; then
  echo "" >&2
  echo "❌ ERROR: Your Google Cloud Application Default Credentials (ADC) have expired." >&2
  echo "👉 Please run: gcloud auth application-default login" >&2
  echo "" >&2
  exit 1
fi

if ! terraform state list >/dev/null 2>&1; then
  echo "ERROR: Terraform state not found. Please run 'terraform apply' first inside the 'terraform/' directory." >&2
  exit 1
fi

PROJECT_ID=$(terraform output -raw project_id)
ZONE=$(terraform output -raw zone)
CLUSTER_NAME=$(terraform output -raw cluster_name)
CLUSTER_SIZE=$(terraform output -raw cluster_size)

cd "$SCRIPT_DIR"

echo "Waiting for all ${CLUSTER_SIZE} nodes in '${CLUSTER_NAME}' to be RUNNING with internal IPs..."

MAX_ATTEMPTS=60
ATTEMPT=0
while true; do
  instances=$(gcloud compute instances list \
    --project="${PROJECT_ID}" \
    --filter="name ~ '^${CLUSTER_NAME}-(master|node-.*)'" \
    --format="value(name, networkInterfaces[0].networkIP, status)" || true)

  count=0
  ready_count=0
  
  if [ -n "$instances" ]; then
    while read -r name ip status; do
      if [ -n "$name" ] && [ -n "$status" ]; then
        count=$((count+1))
        # Check if the third field (status) is RUNNING, and second field (internal IP) is set
        if [ -n "$ip" ] && [ "$status" = "RUNNING" ]; then
          ready_count=$((ready_count+1))
        fi
      fi
    done <<< "$instances"
  fi

  echo "Progress: ${ready_count}/${CLUSTER_SIZE} nodes are RUNNING with internal IPs..."

  if [ "$ready_count" -eq "$CLUSTER_SIZE" ] && [ "$count" -eq "$CLUSTER_SIZE" ]; then
    echo "All nodes are ready!"
    break
  fi

  ATTEMPT=$((ATTEMPT+1))
  if [ "$ATTEMPT" -ge "$MAX_ATTEMPTS" ]; then
    if [ "$ready_count" -gt 0 ]; then
      echo "WARNING: Timeout waiting for all nodes to become ready."
      echo "Only ${ready_count} out of ${CLUSTER_SIZE} nodes are running."
      echo "Proceeding with the active nodes..."
      break
    else
      echo "ERROR: Timeout waiting for nodes to become ready. No active nodes found."
      echo "$instances"
      exit 1
    fi
  fi

  sleep 5
done

master_nodes=""
compute_nodes=""

# Parse instances names for the inventory (only include nodes that are RUNNING)
while read -r name ip status; do
  if [ -z "$name" ] || [ "$status" != "RUNNING" ]; then
    continue
  fi
  if [[ "$name" =~ -master$ ]]; then
    master_nodes="$name"
  else
    compute_nodes="${compute_nodes:+${compute_nodes}
}${name}"
  fi
done <<< "$instances"

mkdir -p ansible

cat << EOF > ansible/inventory.ini
[master]
$master_nodes

[compute]
$compute_nodes

[all_nodes:children]
master
compute

[all_nodes:vars]
ansible_user=hpcuser
ansible_ssh_private_key_file=../.cluster-keys/id_rsa_cluster
ansible_python_interpreter=/usr/bin/python3.9
ansible_ssh_common_args='-o ProxyCommand="gcloud compute start-iap-tunnel %h %p --listen-on-stdin --project=${PROJECT_ID} --zone=${ZONE} --quiet" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'
EOF

echo "--------------------------------------------------"
echo "Ansible inventory successfully generated!"
echo "Location: ansible/inventory.ini"
echo "--------------------------------------------------"
cat ansible/inventory.ini
echo "--------------------------------------------------"
