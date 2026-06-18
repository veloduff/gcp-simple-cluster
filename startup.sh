#!/bin/bash
set -e

# Configuration
CLUSTER_USER="hpcuser"
HOME_DIR="/home/${CLUSTER_USER}"
ANSIBLE_DIR="${HOME_DIR}/ansible"

echo "Starting cluster node configuration..."

# Check for internet access (required to download packages)
echo "Checking external internet connectivity..."
if ! curl -s --connect-timeout 5 https://www.google.com >/dev/null; then
  echo "ERROR: No internet access detected! Private VM instances require a Cloud NAT gateway configured in their VPC region to download packages." >&2
  exit 1
fi
echo "Internet connectivity verified. Proceeding..."

# 1. Detect OS and install pdsh, NFS client utilities, screen, tmux, & python3-pip
echo "Installing base packages..."
if [ -f /etc/debian_version ]; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y pdsh curl nfs-common screen tmux python3-pip
elif [ -f /etc/redhat-release ]; then
  # Rocky Linux / CentOS / RHEL
  dnf install -y epel-release
  dnf install -y pdsh pdsh-rcmd-ssh curl nfs-utils screen tmux python3-pip
else
  echo "Unsupported OS family. Package installation skipped."
fi

# 2. Upgrade PyYAML (required by SPECstorage SM2020 tool to support FullLoader)
echo "Upgrading PyYAML..."
pip3 install --upgrade PyYAML

# 3. Create the cluster user if they don't exist
if ! id -u "${CLUSTER_USER}" >/dev/null 2>&1; then
  echo "Creating user ${CLUSTER_USER}..."
  useradd -m -s /bin/bash "${CLUSTER_USER}"
else
  echo "User ${CLUSTER_USER} already exists."
fi

# Allow hpcuser passwordless sudo (needed for Ansible tasks executed from controller)
echo "${CLUSTER_USER} ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/${CLUSTER_USER}"
chmod 0440 "/etc/sudoers.d/${CLUSTER_USER}"

# 4. Retrieve SSH keys from GCP Metadata
echo "Retrieving cluster SSH keys from metadata..."
PUB_KEY=$(curl -s -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/attributes/cluster-public-key)
PRIV_KEY=$(curl -s -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/attributes/cluster-private-key)

if [ -z "$PUB_KEY" ] || [ -z "$PRIV_KEY" ]; then
  echo "ERROR: Failed to retrieve SSH keys from metadata."
  exit 1
fi

# 5. Setup SSH directory and files
SSH_DIR="${HOME_DIR}/.ssh"
mkdir -p "${SSH_DIR}"
chmod 700 "${SSH_DIR}"

echo "$PRIV_KEY" > "${SSH_DIR}/id_rsa"
chmod 600 "${SSH_DIR}/id_rsa"

echo "$PUB_KEY" > "${SSH_DIR}/authorized_keys"
chmod 600 "${SSH_DIR}/authorized_keys"

# 6. Disable Strict Host Key Checking for all hosts
cat << 'EOF' > "${SSH_DIR}/config"
Host *
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
    LogLevel ERROR
EOF
chmod 600 "${SSH_DIR}/config"

# 7. Configure pdsh profile variables
echo "Configuring shell environments..."
if ! grep -q "PDSH_RCMD_TYPE" "${HOME_DIR}/.bashrc"; then
  cat << 'EOF' >> "${HOME_DIR}/.bashrc"

# PDSH Settings
export PDSH_RCMD_TYPE="ssh"
export WCOLL="/home/hpcuser/hostfile"

# GCP Instance Metadata Helper Function
instance_md() {
  curl -s -H "Metadata-Flavor: Google" "http://metadata.google.internal/computeMetadata/v1/instance/$1"; echo
}
EOF
fi

# 8. Create a node discovery script
cat << 'EOF' > /usr/local/bin/discover-nodes
#!/bin/bash
# Query the local metadata server and GCP API to find other nodes in this cluster.
ZONE=$(curl -s -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/zone | awk -F/ '{print $4}')
HOSTNAME=$(hostname)
PREFIX=$(echo "$HOSTNAME" | sed -E 's/-[a-z0-9]+$//')

echo "Discovering cluster nodes with prefix '$PREFIX' in zone '$ZONE'..."

# Fetch node list using gcloud (available on GCP Linux images by default)
gcloud compute instances list \
  --filter="name ~ '^${PREFIX}-[a-z0-9]+$' AND zone:($ZONE)" \
  --format="value(name)" > /home/hpcuser/hostfile.tmp 2>/dev/null

if [ -s /home/hpcuser/hostfile.tmp ]; then
  mv /home/hpcuser/hostfile.tmp /home/hpcuser/hostfile
  chown hpcuser:hpcuser /home/hpcuser/hostfile
  echo "Node discovery complete. hostfile updated at /home/hpcuser/hostfile"
else
  echo "Warning: gcloud discovery returned no results. Make sure instance SA has Viewer permission."
  rm -f /home/hpcuser/hostfile.tmp
fi
EOF
chmod +x /usr/local/bin/discover-nodes

# 9. Setup a cron job to auto-discover nodes every minute
echo "* * * * * root /usr/local/bin/discover-nodes >/dev/null 2>&1" > /etc/cron.d/cluster-discovery
chmod 644 /etc/cron.d/cluster-discovery

# 10. Increase system limits (nofile, nproc, memlock) for hpcuser
cat << 'EOF' > /etc/security/limits.d/99-hpcuser.conf
hpcuser          soft    nofile          1048576
hpcuser          hard    nofile          1048576
hpcuser          soft    nproc           unlimited
hpcuser          hard    nproc           unlimited
hpcuser          soft    memlock         unlimited
hpcuser          hard    memlock         unlimited
EOF

# 11. Correct ownership of all home directories
chown -R "${CLUSTER_USER}:${CLUSTER_USER}" "${HOME_DIR}"

# Run discovery once on startup (though other nodes may still be booting)
/usr/local/bin/discover-nodes || true

echo "Cluster SSH, pdsh, Ansible, and node discovery configuration completed successfully."
