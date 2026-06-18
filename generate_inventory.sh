#!/bin/bash
# generate_inventory.sh - Queries GCP for active cluster instances and generates an Ansible inventory.ini

set -euo pipefail

# Configuration sourced from central config file
source "$(dirname "$0")/config.sh"

echo "Waiting for all ${CLUSTER_SIZE} nodes in '${CLUSTER_NAME}' to be RUNNING with internal IPs..."

MAX_ATTEMPTS=60
ATTEMPT=0
while true; do
  instances=$(gcloud compute instances list \
    --project="${PROJECT_ID}" \
    --filter="name ~ '^${CLUSTER_NAME}-node-.*'" \
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
      echo "Proceeding with the ${ready_count} active nodes..."
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
first=true

# Parse instances names for the inventory (only include nodes that are RUNNING)
while read -r name ip status; do
  if [ -z "$name" ] || [ "$status" != "RUNNING" ]; then
    continue
  fi
  if [ "$first" = true ]; then
    master_nodes="$name"
    first=false
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
ansible_ssh_common_args='-o ProxyCommand="gcloud compute start-iap-tunnel %h %p --listen-on-port=0 --project=${PROJECT_ID} --zone=${ZONE} --quiet" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'
EOF

echo "--------------------------------------------------"
echo "Ansible inventory successfully generated!"
echo "Location: ansible/inventory.ini"
echo "--------------------------------------------------"
cat ansible/inventory.ini
echo "--------------------------------------------------"
