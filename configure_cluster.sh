#!/bin/bash
# configure_cluster.sh - Wrapper to run Ansible playbook with optional components from your Mac

set -euo pipefail

# Ensure we are in the script's directory
cd "$(dirname "$0")"

# Help message
show_usage() {
  echo "Usage: $0 [options]"
  echo "Options:"
  echo "  -c, --compilers   Install compilers, git, make, OpenMPI"
  echo "  -n, --nfs         Configure shared NFS directory (/home/hpcuser/shared)"
  echo "  -s, --slurm       Install and configure Slurm scheduler and MUNGE"
  echo "  -a, --all         Install all of the above"
  echo "  -h, --help        Show this help message"
  echo ""
  echo "If no options are provided, an interactive prompt will ask you what to configure."
}

# Generate/Refresh local inventory from active GCP instances
./generate_inventory.sh

# Parse command-line flags
RUN_COMPILERS=false
RUN_NFS=false
RUN_SLURM=false
RUN_ALL=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    -c|--compilers)
      RUN_COMPILERS=true
      shift
      ;;
    -n|--nfs)
      RUN_NFS=true
      shift
      ;;
    -s|--slurm)
      RUN_SLURM=true
      shift
      ;;
    -a|--all)
      RUN_ALL=true
      shift
      ;;
    -h|--help)
      show_usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      show_usage
      exit 1
      ;;
  esac
done

# If no flags are set, run interactive prompt
if [ "$RUN_COMPILERS" = false ] && [ "$RUN_NFS" = false ] && [ "$RUN_SLURM" = false ] && [ "$RUN_ALL" = false ]; then
  echo "No configuration options specified. Entering interactive mode..."
  echo "------------------------------------------------------------"
  
  read -p "1. Install compilers & OpenMPI? (y/N): " choice_compilers
  if [[ "$choice_compilers" =~ ^[Yy]$ ]]; then
    RUN_COMPILERS=true
  fi

  read -p "2. Configure shared NFS folder across nodes? (y/N): " choice_nfs
  if [[ "$choice_nfs" =~ ^[Yy]$ ]]; then
    RUN_NFS=true
  fi

  read -p "3. Install & configure Slurm scheduler? (y/N): " choice_slurm
  if [[ "$choice_slurm" =~ ^[Yy]$ ]]; then
    RUN_SLURM=true
  fi
  echo "------------------------------------------------------------"
fi

# If --all is requested, enable all components
if [ "$RUN_ALL" = true ]; then
  RUN_COMPILERS=true
  RUN_NFS=true
  RUN_SLURM=true
fi

# Build tags list
TAGS=""

if [ "$RUN_COMPILERS" = true ]; then
  TAGS="${TAGS:+$TAGS,}compilers"
fi

if [ "$RUN_NFS" = true ]; then
  TAGS="${TAGS:+$TAGS,}nfs"
fi

if [ "$RUN_SLURM" = true ]; then
  TAGS="${TAGS:+$TAGS,}slurm"
fi

if [ -z "$TAGS" ]; then
  echo "No components selected. Exiting without changes."
  exit 0
fi

echo "Running Ansible Playbook with tags: [$TAGS]..."
echo "------------------------------------------------------------"

cd ansible
ansible-playbook site.yml --tags "$TAGS"
