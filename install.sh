#!/bin/bash

USERNAME=""
CLEAR_TMP_BAREMETAL_CACHE=false
TMP_BAREMETAL_DIR="/tmp/baremetal"

print_usage() {
  cat <<'EOF'
Usage: ./install.sh [options] <username>

Options:
  --clear-tmp-baremetal-cache  Remove /tmp/baremetal before running install steps.
  -h, --help                   Show this help message.
EOF
}

for arg in "$@"; do
  case "$arg" in
    --clear-tmp-baremetal-cache)
      CLEAR_TMP_BAREMETAL_CACHE=true
      ;;
    -h|--help)
      print_usage
      exit 0
      ;;
    -* )
      echo "[baremetal-install] Unknown option: $arg"
      print_usage
      exit 1
      ;;
    *)
      if [ -z "$USERNAME" ]; then
        USERNAME="$arg"
      else
        echo "[baremetal-install] Unexpected extra argument: $arg"
        print_usage
        exit 1
      fi
      ;;
  esac
done

# Load default configuration.
SCRIPT_DIR="$(dirname "$0")"
CONFIG_FILE="$SCRIPT_DIR/config"
if [ -f "$CONFIG_FILE" ]; then
  # shellcheck source=config
  source "$CONFIG_FILE"
else
  echo "[baremetal-install] WARNING: config file not found at $CONFIG_FILE. Using built-in defaults."
  VM_BOX="ubuntu/jammy64"
fi

# Function copied from https://stackoverflow.com/questions/24398242/check-if-service-exists-in-bash-centos-and-ubuntu
service_exists() {
    local n=$1
    if [[ $(systemctl list-units --all -t service --full --no-legend "$n.service" | sed 's/^\s*//g' | cut -f1 -d' ') == $n.service ]]; then
        return 0
    else
        return 1
    fi
}

detect_active_network_interface() {
    local detected_interface

    if ! command -v ip >/dev/null 2>&1; then
        return 1
    fi

    detected_interface=$(ip route show default 2>/dev/null | awk '/default/ {print $5; exit}')

    if [ -z "$detected_interface" ]; then
        detected_interface=$(ip -o link show up 2>/dev/null | awk -F': ' '$2 != "lo" {print $2; exit}')
    fi

    if [ -z "$detected_interface" ] || [ "$detected_interface" = "lo" ]; then
        return 1
    fi

    echo "$detected_interface"
}

upsert_env_var() {
    local env_file=$1
    local key=$2
    local value=$3

    if grep -q "^${key}=" "$env_file"; then
        echo "[baremetal-install] Updating ${key} in $env_file."
        sed -i "s|^${key}=.*$|${key}=${value}|" "$env_file"
    else
        echo "[baremetal-install] Adding ${key}=${value} to $env_file."
        echo "${key}=${value}" >> "$env_file"
    fi
}

clear_tmp_baremetal_cache_if_requested() {
    if [ "$CLEAR_TMP_BAREMETAL_CACHE" = true ]; then
        echo "[baremetal-install] Removing temporary cache directory: $TMP_BAREMETAL_DIR"
        rm -rf "$TMP_BAREMETAL_DIR"
    fi
}

restore_cached_vagrant_binary() {
    local target_vagrant="$SCRIPT_DIR/ansible/vagrant/vagrant"
    local cached_vagrant="$TMP_BAREMETAL_DIR/vagrant"

    if [ -x "$target_vagrant" ]; then
        return 0
    fi

    if [ -x "$cached_vagrant" ]; then
        echo "[baremetal-install] Restoring cached vagrant binary from $cached_vagrant"
        mkdir -p "$(dirname "$target_vagrant")"
        cp "$cached_vagrant" "$target_vagrant"
        chmod +x "$target_vagrant"
    fi
}

cache_vagrant_binary_if_available() {
    local target_vagrant="$SCRIPT_DIR/ansible/vagrant/vagrant"
    local cached_vagrant="$TMP_BAREMETAL_DIR/vagrant"

    if [ -x "$target_vagrant" ]; then
        mkdir -p "$TMP_BAREMETAL_DIR"
        cp "$target_vagrant" "$cached_vagrant"
        chmod +x "$cached_vagrant"
        echo "[baremetal-install] Cached vagrant binary at $cached_vagrant"
    fi
}

get_user_home() {
    local username=$1
    local user_home

    user_home=$(getent passwd "$username" | cut -d: -f6)

    if [ -z "$user_home" ]; then
        echo "[baremetal-install] User '$username' does not exist on this machine."
        return 1
    fi

    echo "$user_home"
}

run_as_user() {
    local username=$1
    shift

    if command -v runuser >/dev/null 2>&1; then
        runuser -u "$username" -- "$@"
    else
        su - "$username" -c "$(printf '%q ' "$@")"
    fi
}

ensure_ssh_access_for_user() {
    local username=$1
    local user_home=$2
    local user_group
    local ssh_dir
    local private_key
    local public_key
    local authorized_keys

    user_group=$(id -gn "$username") || return 1
    ssh_dir="$user_home/.ssh"
    private_key="$ssh_dir/id_rsa"
    public_key="$ssh_dir/id_rsa.pub"
    authorized_keys="$ssh_dir/authorized_keys"

    install -d -m 700 -o "$username" -g "$user_group" "$ssh_dir"

    if [ ! -f "$private_key" ]; then
        echo "[baremetal-install] Generating SSH key pair for $username."
        rm -f "$public_key"
        run_as_user "$username" ssh-keygen -q -t rsa -b 4096 -N "" -f "$private_key"
    elif [ ! -f "$public_key" ]; then
        echo "[baremetal-install] Rebuilding missing public SSH key for $username."
        ssh-keygen -y -f "$private_key" > "$public_key"
        chown "$username:$user_group" "$public_key"
        chmod 644 "$public_key"
    else
        echo "[baremetal-install] SSH keys already created. Skipping creation."
    fi

    touch "$authorized_keys"
    chown "$username:$user_group" "$authorized_keys"
    chmod 600 "$authorized_keys"

    if ! grep -qxF "$(cat "$public_key")" "$authorized_keys"; then
        echo "[baremetal-install] Authorizing self key for self ssh session."
        cat "$public_key" >> "$authorized_keys"
        chown "$username:$user_group" "$authorized_keys"
    else
        echo "[baremetal-install] SSH public key already authorized. Skipping update."
    fi
}

ensure_known_host_for_user() {
    local username=$1
    local user_home=$2
    local host_target=$3
    local ssh_port=${4:-22}
    local user_group
    local ssh_dir
    local known_hosts
    local known_host_entry
    local scanned_keys

    user_group=$(id -gn "$username") || return 1
    ssh_dir="$user_home/.ssh"
    known_hosts="$ssh_dir/known_hosts"
    known_host_entry="$host_target"

    if [ "$ssh_port" != "22" ]; then
        known_host_entry="[$host_target]:$ssh_port"
    fi

    install -d -m 700 -o "$username" -g "$user_group" "$ssh_dir"
    touch "$known_hosts"
    chown "$username:$user_group" "$known_hosts"
    chmod 600 "$known_hosts"

    echo "[baremetal-install] Seeding SSH known_hosts entry for $known_host_entry."
    ssh-keygen -R "$known_host_entry" -f "$known_hosts" >/dev/null 2>&1 || true

    scanned_keys=$(ssh-keyscan -H -T 10 -p "$ssh_port" "$host_target" 2>/dev/null)

    if [ -z "$scanned_keys" ]; then
        echo "[baremetal-install] Unable to collect SSH host key for $known_host_entry."
        return 1
    fi

    printf '%s\n' "$scanned_keys" >> "$known_hosts"
    chown "$username:$user_group" "$known_hosts"
    chmod 600 "$known_hosts"
}

# Function to detect available disk space (in GB) and return 1/5
detect_vm_disk_size() {
    local total_disk_gb
    total_disk_gb=$(df / | awk 'NR==2 {print int($2 / 1024 / 1024)}')
    # Calculate 1/5 of disk and round up
    awk -v disk="$total_disk_gb" 'BEGIN { printf "%.0f\n", disk / 6 + 0.5 }'
}

# Function to detect available memory (in MB) and return 1/10
detect_vm_memory() {
    local total_mem_kb
    total_mem_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    local total_mem_mb=$((total_mem_kb / 1024))
    # Calculate 1/10 of memory and round up
    awk -v mem="$total_mem_mb" 'BEGIN { printf "%.0f\n", mem / 10 + 0.5 }'
}

# Function to detect available CPUs and return 1/3
detect_vm_cpus() {
    local total_cpus
    total_cpus=$(nproc 2>/dev/null || echo 1)
    # Calculate 1/3 of CPUs and round up
    awk -v cpus="$total_cpus" 'BEGIN { printf "%.0f\n", cpus / 3 + 0.5 }'
}

if [ -z "$USERNAME" ]; then
  echo "[baremetal-install] Username is required. See README.md for further instructions."
  print_usage
  exit 1
fi

clear_tmp_baremetal_cache_if_requested
restore_cached_vagrant_binary

USER_HOME=$(get_user_home "$USERNAME") || exit 1

if [ -f /usr/bin/ansible ]; then
  echo "[baremetal-install] Ansible already installed. Skipping installation."
fi

# Install Ansible:
if [ ! -f /usr/bin/ansible ]; then
  echo "[baremetal-install] Installing ansible by running: apt -y install ansible."
  apt update
  apt-add-repository ppa:ansible/ansible
  apt -y install ansible
fi  

if service_exists ssh; then
  echo "[baremetal-install] openssh-server is already installed. Skipping installation."
else
  echo "[baremetal-install] Installing openssh-server by running: apt -y install openssh-server."
  apt -y install openssh-server
fi

# Create shared data directory:
if [ ! -d ansible/vagrant/data ]; then
  echo "[baremetal-install] Creating ansible/vagrant/data folder."
  mkdir ansible/vagrant/data
else
  echo "[baremetal-install] Folder ansible/vagrant/data already created. Skipping creation."
fi

ensure_ssh_access_for_user "$USERNAME" "$USER_HOME"
ensure_known_host_for_user "$USERNAME" "$USER_HOME" "127.0.0.1"
ensure_known_host_for_user "$USERNAME" "$USER_HOME" "localhost"

# Add baremetal_host_username and default_box to baremetal_hosts.
HOSTS_FILE="$SCRIPT_DIR/ansible/baremetal_hosts"
upsert_env_var "$HOSTS_FILE" "baremetal_host_username" "$USERNAME"
upsert_env_var "$HOSTS_FILE" "default_box" "$VM_BOX"

# Ensure vagrant .env exists and contains HOST_USER_NAME.
ENV_FILE="$SCRIPT_DIR/ansible/vagrant/.env"
mkdir -p "$(dirname "$ENV_FILE")"
touch "$ENV_FILE"

PUBLIC_NETWORK_BRIDGE=$(detect_active_network_interface)
if [ -z "$PUBLIC_NETWORK_BRIDGE" ]; then
  echo "[baremetal-install] Unable to detect the active network interface automatically."
  echo "[baremetal-install] Please ensure the host has an active network connection and the 'ip' command is available."
  exit 1
fi

upsert_env_var "$ENV_FILE" "HOST_USER_NAME" "$USERNAME"
upsert_env_var "$ENV_FILE" "PUBLIC_NETWORK_BRIDGE" "$PUBLIC_NETWORK_BRIDGE"

# Add VM_BOX default only if not already set (user may have customised it).
if ! grep -q "^VM_BOX=" "$ENV_FILE"; then
  echo "[baremetal-install] Adding VM_BOX=${VM_BOX} to $ENV_FILE."
  echo "VM_BOX=${VM_BOX}" >> "$ENV_FILE"
else
  echo "[baremetal-install] VM_BOX already set in $ENV_FILE. Skipping."
fi

# Handle VM_DISK_SIZE: use config value if defined, otherwise auto-detect.
if [ -z "$VM_DISK_SIZE" ]; then
  VM_DISK_SIZE=$(detect_vm_disk_size)
  echo "[baremetal-install] Auto-detected VM_DISK_SIZE=${VM_DISK_SIZE} GB (1/6 of available disk)."
fi
upsert_env_var "$ENV_FILE" "VM_DISK_SIZE" "${VM_DISK_SIZE}GB"

# Handle VM_MEMORY: use config value if defined, otherwise auto-detect.
if [ -z "$VM_MEMORY" ]; then
  VM_MEMORY=$(detect_vm_memory)
  echo "[baremetal-install] Auto-detected VM_MEMORY=${VM_MEMORY} MB (1/10 of available memory)."
fi
upsert_env_var "$ENV_FILE" "VM_MEMORY" "$VM_MEMORY"

# Handle VM_CPUS: use config value if defined, otherwise auto-detect.
if [ -z "$VM_CPUS" ]; then
  VM_CPUS=$(detect_vm_cpus)
  echo "[baremetal-install] Auto-detected VM_CPUS=${VM_CPUS} (1/3 of available CPUs)."
fi
upsert_env_var "$ENV_FILE" "VM_CPUS" "$VM_CPUS"

cache_vagrant_binary_if_available

