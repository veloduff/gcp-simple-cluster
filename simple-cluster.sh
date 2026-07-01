#!/bin/bash
# simple-cluster.sh - Unified entrypoint to manage the HPC cluster workflow

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="$SCRIPT_DIR/terraform"

# Help message
show_usage() {
  echo "Usage: $0 <command> [options]"
  echo ""
  echo "Available Commands:"
  echo "  check-config  - Verify GCP auth and display active configuration parameters"
  echo "  launch        - Provision GCP infrastructure and configure cluster software"
  echo "                  Options: -v, --verbose  (Shows raw Terraform plan and prompts for confirmation)"
  echo "  configure     - Re-run configuration playbook (Ansible) on the active cluster"
  echo "  destroy       - Tear down and delete all cluster resources in GCP"
  echo "                  Options: -v, --verbose  (Shows raw Terraform plan and prompts for confirmation)"
  echo "  help          - Show this help message"
}

# Helper to check if a command exists
check_cmd() {
  local cmd="$1"
  local help_msg="$2"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "ERROR: Required command '$cmd' is not installed." >&2
    echo "       $help_msg" >&2
    exit 1
  fi
}

verify_terraform() {
  check_cmd "terraform" "Please install Terraform: https://developer.hashicorp.com/terraform/downloads"
}

verify_gcloud() {
  check_cmd "gcloud" "Please install the Google Cloud SDK: https://cloud.google.com/sdk/docs/install"
}

verify_ansible() {
  check_cmd "ansible-playbook" "Please install Ansible on your Mac: pip install ansible  or  brew install ansible"
}

# 1. Verify GCP Authentication Status
verify_auth() {
  echo "Verifying Google Cloud credentials..."
  
  if ! gcloud auth application-default print-access-token >/dev/null 2>&1; then
    echo "ERROR: Your Google Cloud Application Default Credentials (ADC) have expired." >&2
    echo "Please run: gcloud auth application-default login --no-launch-browser" >&2
    exit 1
  fi

  if ! gcloud auth print-access-token >/dev/null 2>&1; then
    echo "WARNING: Your gcloud CLI session is expired." >&2
    echo "Please run: gcloud auth login --no-launch-browser" >&2
    exit 1
  fi
  
  echo "GCP authentication verified."
}

# Helper to run Terraform apply or destroy quietly (with option for verbose logs)
run_terraform() {
  local action="$1"
  local verbose=false

  # Check if --verbose or -v is in the arguments passed to the subcommand
  for arg in "$@"; do
    if [ "$arg" = "--verbose" ] || [ "$arg" = "-v" ]; then
      verbose=true
    fi
  done

  cd "$TERRAFORM_DIR"

  if [ "$verbose" = "true" ]; then
    echo "Running Terraform $action (verbose output active)..."
    terraform "$action"
  else
    echo "Running Terraform $action in quiet mode (logging full output to terraform/terraform_${action}.log)..."
    echo "This may take a minute or two..."
    
    # Run with auto-approve and pipe stdout/stderr to local log file
    if terraform "$action" -auto-approve > "terraform_${action}.log" 2>&1; then
      echo "Terraform $action completed successfully."
    else
      echo "ERROR: Terraform $action failed! Review log file for details:" >&2
      echo "   cat terraform/terraform_${action}.log" >&2
      exit 1
    fi
  fi
  
  cd "$SCRIPT_DIR"
}

# Sync top-level cluster.conf to terraform/terraform.tfvars
sync_tfvars() {
  if [ -f "$SCRIPT_DIR/cluster.conf" ]; then
    cp "$SCRIPT_DIR/cluster.conf" "$TERRAFORM_DIR/terraform.tfvars"
  else
    echo "ERROR: cluster.conf not found in the root directory." >&2
    echo "Please copy cluster.conf.example to cluster.conf and configure it:" >&2
    echo "   cp cluster.conf.example cluster.conf" >&2
    exit 1
  fi
}

# 2. Display Configured Variables
show_config() {
  sync_tfvars
  
  echo "Querying active configuration parameters..."
  cd "$TERRAFORM_DIR"
  
  # Initialize if not already done to query console
  if [ ! -d ".terraform" ]; then
    echo "Initializing Terraform..."
    terraform init -backend=false >/dev/null 2>&1 || true
  fi

  # Initialize default values
  PROJECT_ID="undefined"
  REGION="undefined"
  ZONE="undefined"
  CLUSTER_NAME="undefined"
  COMPUTE_NODES="undefined"
  MASTER_TYPE="undefined"
  COMPUTE_TYPE="undefined"
  CREATE_VPC="true"
  VPC_NAME="default"

  # Query all values in a single terraform console invocation
  MAP_EXPR="{project_id = var.project_id, region = var.region, zone = var.zone, cluster_name = var.cluster_name, compute_node_count = var.compute_node_count, master_machine_type = var.master_machine_type, compute_machine_type = var.compute_machine_type, create_network = var.create_network, vpc_name = var.vpc_name}"
  MAP_DATA=$(echo "$MAP_EXPR" | terraform console 2>/dev/null || echo "")

  if [ -n "$MAP_DATA" ]; then
    while read -r line; do
      if [[ "$line" =~ \"([^\"]+)\"\ +=\ +\"?([^\"]+)\"? ]]; then
        key="${BASH_REMATCH[1]}"
        val="${BASH_REMATCH[2]}"
        val=$(echo "$val" | tr -d '",')
        case "$key" in
          project_id) PROJECT_ID="$val" ;;
          region) REGION="$val" ;;
          zone) ZONE="$val" ;;
          cluster_name) CLUSTER_NAME="$val" ;;
          compute_node_count) COMPUTE_NODES="$val" ;;
          master_machine_type) MASTER_TYPE="$val" ;;
          compute_machine_type) COMPUTE_TYPE="$val" ;;
          create_network) CREATE_VPC="$val" ;;
          vpc_name) VPC_NAME="$val" ;;
        esac
      fi
    done <<< "$MAP_DATA"
  fi

  cd "$SCRIPT_DIR"

  echo "============================================="
  echo " Active HPC Cluster Configuration Summary"
  echo "============================================="
  echo "GCP Project:          $PROJECT_ID"
  echo "Cluster Name Prefix:  $CLUSTER_NAME"
  echo "Region / Zone:        $REGION / $ZONE"
  echo "Master Node Size:     $MASTER_TYPE"
  echo "Compute Nodes Count:  $COMPUTE_NODES instances"
  echo "Compute Nodes Size:   $COMPUTE_TYPE"
  if [ "$CREATE_VPC" = "true" ]; then
    echo "VPC Strategy:         Create a NEW VPC network (${CLUSTER_NAME}-vpc)"
  else
    echo "VPC Strategy:         Deploy into EXISTING VPC network ($VPC_NAME)"
  fi
  echo "============================================="
}

# Parse command line argument
if [ $# -lt 1 ]; then
  show_usage
  exit 1
fi

COMMAND="$1"
shift

case "$COMMAND" in
  check-config)
    verify_terraform
    show_config
    ;;
  
  launch)
    verify_terraform
    verify_gcloud
    verify_ansible
    verify_auth
    show_config
    echo ""
    echo "Starting Deployment Process..."
    echo "---------------------------------------------"
    
    cd "$TERRAFORM_DIR"
    echo "Initializing Terraform..."
    terraform init
    cd "$SCRIPT_DIR"
    
    # Run terraform apply quietly (passing any arguments like -v or --verbose)
    run_terraform apply "$@"
    
    echo ""
    echo "Configuring software via Ansible..."
    echo "---------------------------------------------"
    # Launches configuration script interactively
    ./configure_cluster.sh

    echo ""
    echo "------------------------------------------------------------"
    echo "Cluster deployment and configuration complete!"
    echo "To log into the master node, run:"
    echo "  gcloud compute ssh ${CLUSTER_NAME}-master --project=${PROJECT_ID} --zone=${ZONE}"
    echo "------------------------------------------------------------"
    ;;

  configure)
    verify_gcloud
    verify_ansible
    verify_auth
    echo "Re-running configuration playbook..."
    echo "---------------------------------------------"
    ./configure_cluster.sh "$@"
    ;;

  destroy)
    verify_terraform
    verify_gcloud
    verify_auth
    sync_tfvars
    echo "Starting Cluster Teardown..."
    echo "---------------------------------------------"
    
    # Run terraform destroy quietly (passing arguments like -v or --verbose)
    run_terraform destroy "$@"
    ;;
    
  help|--help|-h)
    show_usage
    ;;
    
  *)
    echo "Unknown command: $COMMAND" >&2
    show_usage
    exit 1
    ;;
esac
