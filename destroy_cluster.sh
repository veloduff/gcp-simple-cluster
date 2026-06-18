#!/bin/bash
# destroy_cluster.sh - Tears down the MIG and Instance Template created by deploy_cluster.sh

set -euo pipefail

# --- Configuration ---
source "$(dirname "$0")/config.sh"

echo "============================================="
echo " Destroying Simple HPC Cluster"
echo "============================================="
echo "Project:      $PROJECT_ID"
echo "Cluster Name: $CLUSTER_NAME"
echo "============================================="

# 1. Delete Managed Instance Group
if gcloud compute instance-groups managed describe "${CLUSTER_NAME}-mig" --project="${PROJECT_ID}" --zone="${ZONE}" >/dev/null 2>&1; then
  echo "Deleting Managed Instance Group: ${CLUSTER_NAME}-mig..."
  gcloud compute instance-groups managed delete "${CLUSTER_NAME}-mig" \
      --project="${PROJECT_ID}" \
      --zone="${ZONE}" \
      --quiet
else
  echo "Managed Instance Group '${CLUSTER_NAME}-mig' not found."
fi

# 2. Delete Instance Template
if gcloud compute instance-templates describe "${CLUSTER_NAME}-template" --project="${PROJECT_ID}" >/dev/null 2>&1; then
  echo "Deleting Instance Template: ${CLUSTER_NAME}-template..."
  gcloud compute instance-templates delete "${CLUSTER_NAME}-template" \
      --project="${PROJECT_ID}" \
      --quiet
else
  echo "Instance Template '${CLUSTER_NAME}-template' not found."
fi

# 3. Clean up local key files
echo "Cleaning up local cluster SSH keys..."
rm -rf .cluster-keys

echo "============================================="
echo " Cluster cleanup completed!"
echo "============================================="
