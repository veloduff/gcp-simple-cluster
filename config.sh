# config.sh - Central configuration file for the Simple GCP HPC-Like Cluster

# GCP Project ID
export PROJECT_ID="${PROJECT_ID:-file-system-benchmarking}"

# Existing VPC Network and Subnetwork names
export VPC_NAME="${VPC_NAME:-default}"
export SUBNET_NAME="${SUBNET_NAME:-default}"

# Region and Zone
export REGION="${REGION:-us-east1}"
export ZONE="${ZONE:-us-east1-b}"

# Cluster naming and scale settings
export CLUSTER_NAME="${CLUSTER_NAME:-simple-hpc-cluster}"
export CLUSTER_SIZE="${CLUSTER_SIZE:-16}"

# VM Hardware and OS settings
export MACHINE_TYPE="${MACHINE_TYPE:-c4-standard-8}"
export IMAGE_FAMILY="${IMAGE_FAMILY:-rocky-linux-8-optimized-gcp}"
export IMAGE_PROJECT="${IMAGE_PROJECT:-rocky-linux-cloud}"

