#!/usr/bin/env bash

baremetal_init_context() {
  local common_dir
  common_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

  BAREMETAL_ROOT="$(cd "$common_dir/.." && pwd)"
  VAGRANT_DIR="$BAREMETAL_ROOT/ansible/vagrant"
  MACHINES_YML="$VAGRANT_DIR/.baremetal-machines.yml"
  ENV_FILE="$VAGRANT_DIR/.env"

  BAREMETAL_CLR_YELLOW=""
  BAREMETAL_CLR_GREEN=""
  BAREMETAL_CLR_WHITE=""
  BAREMETAL_CLR_RESET=""
}

baremetal_init_colors() {
  if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    BAREMETAL_CLR_YELLOW=$'\033[33m'
    BAREMETAL_CLR_GREEN=$'\033[32m'
    BAREMETAL_CLR_WHITE=$'\033[37m'
    BAREMETAL_CLR_RESET=$'\033[0m'
  fi
}

baremetal_log() {
  printf '[baremetal] %s\n' "$1"
}

baremetal_detect_vagrant() {
  if command -v vagrant >/dev/null 2>&1; then
    command -v vagrant
    return 0
  fi
  return 1
}

# ─── YAML helpers (ruby-backed) ───────────────────────────────────────────────

baremetal_yaml_exists() {
  [ -f "$MACHINES_YML" ]
}

baremetal_yaml_init() {
  if ! baremetal_yaml_exists; then
    mkdir -p "$(dirname "$MACHINES_YML")"
    ruby -ryaml -e 'puts YAML.dump({"machines" => {}})' > "$MACHINES_YML"
    baremetal_log "Initialized machine registry: $MACHINES_YML"
  fi
}

# Outputs the list of machine names, one per line.
baremetal_yaml_list_names() {
  if ! baremetal_yaml_exists; then
    return 0
  fi
  ruby -ryaml -e '
    data = YAML.load_file(ARGV[0])
    machines = data["machines"] || {}
    machines.each_key { |k| puts k }
  ' "$MACHINES_YML" 2>/dev/null
}

# Check if a machine name exists. Returns 0 if it does, 1 otherwise.
baremetal_yaml_machine_exists() {
  local name="$1"
  if ! baremetal_yaml_exists; then
    return 1
  fi
  local found
  found="$(ruby -ryaml -e '
    data = YAML.load_file(ARGV[0])
    machines = data["machines"] || {}
    puts machines.key?(ARGV[1]) ? "yes" : "no"
  ' "$MACHINES_YML" "$name" 2>/dev/null)"
  [ "$found" = "yes" ]
}

# Get all ports used across all machines (one port per line).
baremetal_yaml_all_ports() {
  if ! baremetal_yaml_exists; then
    return 0
  fi
  ruby -ryaml -e '
    data = YAML.load_file(ARGV[0])
    machines = data["machines"] || {}
    machines.each do |name, cfg|
      cfg.each do |key, val|
        puts val if key.end_with?("_port") || key == "ssh_port"
      end
    end
  ' "$MACHINES_YML" 2>/dev/null
}

# Get a specific machine's YAML as key: value lines.
baremetal_yaml_get_machine() {
  local name="$1"
  if ! baremetal_yaml_exists; then
    return 1
  fi
  ruby -ryaml -e '
    data = YAML.load_file(ARGV[0])
    machines = data["machines"] || {}
    cfg = machines[ARGV[1]]
    if cfg.nil?
      exit 1
    end
    cfg.each { |k, v| puts "#{k}: #{v}" }
  ' "$MACHINES_YML" "$name" 2>/dev/null
}

# Add or update a machine entry in the YAML file.
baremetal_yaml_put_machine() {
  local name="$1"
  local ssh_port="$2"
  local host_port_80="$3"
  local host_port_443="$4"
  local host_port_8080="$5"
  local host_port_8081="$6"
  local host_port_9001="$7"
  local host_port_8983="$8"
  local host_port_8890="$9"
  local host_port_8585="${10}"
  local host_port_8443="${11}"

  baremetal_yaml_init

  ruby -ryaml -e '
    data = YAML.load_file(ARGV[0])
    data["machines"] ||= {}
    data["machines"][ARGV[1]] = {
      "ssh_port"       => ARGV[2].to_i,
      "host_port_80"   => ARGV[3].to_i,
      "host_port_443"  => ARGV[4].to_i,
      "host_port_8080" => ARGV[5].to_i,
      "host_port_8081" => ARGV[6].to_i,
      "host_port_9001" => ARGV[7].to_i,
      "host_port_8983" => ARGV[8].to_i,
      "host_port_8890" => ARGV[9].to_i,
      "host_port_8585" => ARGV[10].to_i,
      "host_port_8443" => ARGV[11].to_i,
    }
    File.write(ARGV[0], YAML.dump(data))
  ' "$MACHINES_YML" "$name" \
    "$ssh_port" "$host_port_80" "$host_port_443" \
    "$host_port_8080" "$host_port_8081" "$host_port_9001" \
    "$host_port_8983" "$host_port_8890" "$host_port_8585" \
    "$host_port_8443"
}

# Remove a machine from the YAML file.
baremetal_yaml_remove_machine() {
  local name="$1"
  if ! baremetal_yaml_exists; then
    return 1
  fi
  ruby -ryaml -e '
    data = YAML.load_file(ARGV[0])
    machines = data["machines"] || {}
    if machines.delete(ARGV[1]).nil?
      exit 1
    end
    File.write(ARGV[0], YAML.dump(data))
  ' "$MACHINES_YML" "$name" 2>/dev/null
}

# ─── Port allocation ──────────────────────────────────────────────────────────

# Base ports mirror the Vagrantfile defaults.
baremetal_base_ports() {
  local web_std="${1:-true}"
  if [ "$web_std" = "true" ]; then
    echo "2222 80 443 8282 8383 9004 9191 8890 8585 65535"
  else
    echo "2222 8080 8443 8282 8383 9004 9191 8890 8585 65535"
  fi
}

# Check if a port is already used by any machine.
baremetal_port_used() {
  local port="$1"
  if baremetal_yaml_all_ports | grep -qx "$port"; then
    return 0
  fi
  return 1
}

# Allocate the next free host port starting from the given base.
baremetal_next_free_port() {
  local base="$1"
  local port="$base"
  while baremetal_port_used "$port"; do
    port=$((port + 1))
    # Safety ceiling
    if [ "$port" -gt 65535 ]; then
      baremetal_log "ERROR: No free ports available above $base"
      exit 1
    fi
  done
  echo "$port"
}

# Allocate all ports for a new machine.
# Outputs 10 space-separated port numbers.
baremetal_allocate_ports() {
  local web_std="${1:-true}"

  # If no machines exist yet, use base ports.
  if ! baremetal_yaml_exists || [ -z "$(baremetal_yaml_list_names)" ]; then
    baremetal_base_ports "$web_std"
    return
  fi

  # Find the max used port for each port type and add 1.
  local max_ssh max_80 max_443 max_8080 max_8081 max_9001 max_8983 max_8890 max_8585 max_8443
  max_ssh=2222; max_80=80; max_443=443; max_8080=8282; max_8081=8383
  max_9001=9004; max_8983=9191; max_8890=8890; max_8585=8585; max_8443=65535

  # Read all existing ports to find max per guest-port mapping.
  # Since we store them with semantic keys, we can iterate machines.
  if baremetal_yaml_exists; then
    while IFS= read -r name; do
      [ -z "$name" ] && continue
      local cfg
      cfg="$(baremetal_yaml_get_machine "$name")"
      local ssh_p; ssh_p=$(echo "$cfg" | grep '^ssh_port:' | awk '{print $2}')
      local p80; p80=$(echo "$cfg" | grep '^host_port_80:' | awk '{print $2}')
      local p443; p443=$(echo "$cfg" | grep '^host_port_443:' | awk '{print $2}')
      local p8080; p8080=$(echo "$cfg" | grep '^host_port_8080:' | awk '{print $2}')
      local p8081; p8081=$(echo "$cfg" | grep '^host_port_8081:' | awk '{print $2}')
      local p9001; p9001=$(echo "$cfg" | grep '^host_port_9001:' | awk '{print $2}')
      local p8983; p8983=$(echo "$cfg" | grep '^host_port_8983:' | awk '{print $2}')
      local p8890; p8890=$(echo "$cfg" | grep '^host_port_8890:' | awk '{print $2}')
      local p8585; p8585=$(echo "$cfg" | grep '^host_port_8585:' | awk '{print $2}')
      local p8443; p8443=$(echo "$cfg" | grep '^host_port_8443:' | awk '{print $2}')
      [ -n "$ssh_p" ] && [ "$ssh_p" -gt "$max_ssh" ] && max_ssh="$ssh_p"
      [ -n "$p80" ] && [ "$p80" -gt "$max_80" ] && max_80="$p80"
      [ -n "$p443" ] && [ "$p443" -gt "$max_443" ] && max_443="$p443"
      [ -n "$p8080" ] && [ "$p8080" -gt "$max_8080" ] && max_8080="$p8080"
      [ -n "$p8081" ] && [ "$p8081" -gt "$max_8081" ] && max_8081="$p8081"
      [ -n "$p9001" ] && [ "$p9001" -gt "$max_9001" ] && max_9001="$p9001"
      [ -n "$p8983" ] && [ "$p8983" -gt "$max_8983" ] && max_8983="$p8983"
      [ -n "$p8890" ] && [ "$p8890" -gt "$max_8890" ] && max_8890="$p8890"
      [ -n "$p8585" ] && [ "$p8585" -gt "$max_8585" ] && max_8585="$p8585"
      [ -n "$p8443" ] && [ "$p8443" -gt "$max_8443" ] && max_8443="$p8443"
    done <<< "$(baremetal_yaml_list_names)"
  fi

  # Helper: pick the next port, clamping sentinel 65535 ("disabled") as-is.
  _next_or_sentinel() {
    local max="$1"
    if [ "$max" -ge 65535 ]; then
      echo "65535"
    else
      baremetal_next_free_port "$((max + 1))"
    fi
  }

  local n_ssh n_80 n_443 n_8080 n_8081 n_9001 n_8983 n_8890 n_8585 n_8443
  n_ssh=$(_next_or_sentinel "$max_ssh")
  n_80=$(_next_or_sentinel "$max_80")
  n_443=$(_next_or_sentinel "$max_443")
  n_8080=$(_next_or_sentinel "$max_8080")
  n_8081=$(_next_or_sentinel "$max_8081")
  n_9001=$(_next_or_sentinel "$max_9001")
  n_8983=$(_next_or_sentinel "$max_8983")
  n_8890=$(_next_or_sentinel "$max_8890")
  n_8585=$(_next_or_sentinel "$max_8585")
  n_8443=$(_next_or_sentinel "$max_8443")

  echo "$n_ssh $n_80 $n_443 $n_8080 $n_8081 $n_9001 $n_8983 $n_8890 $n_8585 $n_8443"
}

# ─── Vagrant helpers ──────────────────────────────────────────────────────────

baremetal_vagrant_status() {
  local name="$1"
  local vagrant_cmd
  if ! vagrant_cmd="$(baremetal_detect_vagrant)"; then
    echo "unknown"
    return
  fi
  (
    cd "$VAGRANT_DIR"
    "$vagrant_cmd" status "$name" --machine-readable 2>/dev/null | \
      awk -F, -v n="$name" '$2 == n && $3 == "state" { state = $4 } END { print state }'
  )
}

baremetal_vagrant_ssh_config() {
  local name="$1"
  local vagrant_cmd
  if ! vagrant_cmd="$(baremetal_detect_vagrant)"; then
    baremetal_log "vagrant not found on PATH."
    return 1
  fi
  (
    cd "$VAGRANT_DIR"
    "$vagrant_cmd" ssh-config "$name" 2>/dev/null
  )
}

# ─── Commands ─────────────────────────────────────────────────────────────────

baremetal_run_up() {
  local name="${1:-}"

  if [ -z "$name" ]; then
    baremetal_log "Usage: baremetal up <name>"
    baremetal_log "  <name>  Machine name (e.g. 'default', 'dev1', 'staging')"
    exit 1
  fi

  if ! baremetal_detect_vagrant >/dev/null 2>&1; then
    baremetal_log "Vagrant is not installed or not in PATH."
    exit 1
  fi

  if [ ! -d "$VAGRANT_DIR" ]; then
    baremetal_log "Vagrant directory not found: $VAGRANT_DIR"
    baremetal_log "Run 'install.sh' first to set up the environment."
    exit 1
  fi

  baremetal_yaml_init

  local ssh_port host_port_80 host_port_443 host_port_8080 host_port_8081
  local host_port_9001 host_port_8983 host_port_8890 host_port_8585 host_port_8443

  if baremetal_yaml_machine_exists "$name"; then
    baremetal_log "Machine '$name' found in registry. Loading configuration..."
    local cfg
    cfg="$(baremetal_yaml_get_machine "$name")"
    ssh_port=$(echo "$cfg" | grep '^ssh_port:' | awk '{print $2}')
    host_port_80=$(echo "$cfg" | grep '^host_port_80:' | awk '{print $2}')
    host_port_443=$(echo "$cfg" | grep '^host_port_443:' | awk '{print $2}')
    host_port_8080=$(echo "$cfg" | grep '^host_port_8080:' | awk '{print $2}')
    host_port_8081=$(echo "$cfg" | grep '^host_port_8081:' | awk '{print $2}')
    host_port_9001=$(echo "$cfg" | grep '^host_port_9001:' | awk '{print $2}')
    host_port_8983=$(echo "$cfg" | grep '^host_port_8983:' | awk '{print $2}')
    host_port_8890=$(echo "$cfg" | grep '^host_port_8890:' | awk '{print $2}')
    host_port_8585=$(echo "$cfg" | grep '^host_port_8585:' | awk '{print $2}')
    host_port_8443=$(echo "$cfg" | grep '^host_port_8443:' | awk '{print $2}')
  else
    baremetal_log "Machine '$name' is new. Allocating ports..."
    # Detect WEB_STANDARD_PORTS from .env for the first machine.
    local web_std=true
    if [ -f "$ENV_FILE" ] && grep -q '^WEB_STANDARD_PORTS=' "$ENV_FILE"; then
      web_std="$(grep '^WEB_STANDARD_PORTS=' "$ENV_FILE" | cut -d= -f2)"
      case "$web_std" in
        false|no|off|0) web_std=false ;;
        *) web_std=true ;;
      esac
    fi

    local ports
    ports="$(baremetal_allocate_ports "$web_std")"
    read -r ssh_port host_port_80 host_port_443 host_port_8080 host_port_8081 \
         host_port_9001 host_port_8983 host_port_8890 host_port_8585 host_port_8443 \
         <<< "$ports"

    baremetal_log "  SSH port:       $ssh_port"
    baremetal_log "  HTTP (80):      $host_port_80"
    baremetal_log "  HTTPS (443):    $host_port_443"
    baremetal_log "  HTTP alt (8080): $host_port_8080"
    baremetal_log "  HTTP alt (8081): $host_port_8081"
    baremetal_log "  Xdebug (9003):  $host_port_9001"
    baremetal_log "  Solr (8983):    $host_port_8983"
    baremetal_log "  Virtuoso (8890):$host_port_8890"
    baremetal_log "  PhpMyAdmin (8585):$host_port_8585"
    baremetal_log "  GitLab (8443):  $host_port_8443"

    baremetal_yaml_put_machine "$name" \
      "$ssh_port" "$host_port_80" "$host_port_443" \
      "$host_port_8080" "$host_port_8081" "$host_port_9001" \
      "$host_port_8983" "$host_port_8890" "$host_port_8585" \
      "$host_port_8443"
    baremetal_log "Machine '$name' registered in $MACHINES_YML"
  fi

  # Check if the machine is already running.
  local state
  state="$(baremetal_vagrant_status "$name")"
  if [ "$state" = "running" ]; then
    baremetal_log "Machine '$name' is already running."
    baremetal_log "SSH: vagrant ssh $name  (or: baremetal ssh $name)"
    return 0
  fi

  baremetal_log "Starting machine '$name'..."
  (
    cd "$VAGRANT_DIR"
    vagrant up "$name"
  )

  baremetal_log "Machine '$name' is up."
  baremetal_log "SSH port: $ssh_port"
  baremetal_log "Connect:  ssh vagrant@127.0.0.1 -p $ssh_port"
  baremetal_log "Or:       baremetal ssh $name"
}

baremetal_run_down() {
  local name="${1:-}"

  if [ -z "$name" ]; then
    baremetal_log "Usage: baremetal down <name>"
    exit 1
  fi

  if ! baremetal_detect_vagrant >/dev/null 2>&1; then
    baremetal_log "Vagrant is not installed or not in PATH."
    exit 1
  fi

  baremetal_yaml_init

  if ! baremetal_yaml_machine_exists "$name"; then
    baremetal_log "Machine '$name' is not registered."
    baremetal_log "Use 'baremetal list' to see registered machines."
    exit 1
  fi

  local state
  state="$(baremetal_vagrant_status "$name")"
  if [ "$state" != "running" ]; then
    baremetal_log "Machine '$name' is not running (state: ${state:-unknown})."
    return 0
  fi

  baremetal_log "Halting machine '$name'..."
  (
    cd "$VAGRANT_DIR"
    vagrant halt "$name"
  )
  baremetal_log "Machine '$name' halted."
}

baremetal_run_ssh() {
  local name="${1:-}"

  if [ -z "$name" ]; then
    baremetal_log "Usage: baremetal ssh <name>"
    exit 1
  fi

  if ! baremetal_detect_vagrant >/dev/null 2>&1; then
    baremetal_log "Vagrant is not installed or not in PATH."
    exit 1
  fi

  baremetal_yaml_init

  local ssh_port
  if baremetal_yaml_machine_exists "$name"; then
    local cfg
    cfg="$(baremetal_yaml_get_machine "$name")"
    ssh_port=$(echo "$cfg" | grep '^ssh_port:' | awk '{print $2}')
  else
    baremetal_log "Machine '$name' is not registered. Trying vagrant ssh-config..."
    ssh_port=""
  fi

  local state
  state="$(baremetal_vagrant_status "$name")"
  if [ "$state" != "running" ]; then
    baremetal_log "Machine '$name' is not running (state: ${state:-unknown})."
    baremetal_log "Start it with: baremetal up $name"
    exit 1
  fi

  if [ -n "$ssh_port" ]; then
    baremetal_log "Opening SSH session to vagrant@127.0.0.1:$ssh_port"
    exec ssh vagrant@127.0.0.1 -p "$ssh_port" \
      -o StrictHostKeyChecking=accept-new \
      -o UserKnownHostsFile=/dev/null
  else
    baremetal_log "Opening SSH session via vagrant..."
    (
      cd "$VAGRANT_DIR"
      exec vagrant ssh "$name"
    )
  fi
}

baremetal_run_destroy() {
  local name="${1:-}"

  if [ -z "$name" ]; then
    baremetal_log "Usage: baremetal destroy <name>"
    baremetal_log "  This will DESTROY the VM and remove it from the registry."
    exit 1
  fi

  if ! baremetal_detect_vagrant >/dev/null 2>&1; then
    baremetal_log "Vagrant is not installed or not in PATH."
    exit 1
  fi

  baremetal_yaml_init

  baremetal_log "WARNING: This will destroy machine '$name' and all its data."
  baremetal_log "Port mappings will be removed from the registry."
  printf 'Are you sure? (type "%s" to confirm): ' "$name"
  read -r confirm
  if [ "$confirm" != "$name" ]; then
    baremetal_log "Aborted."
    exit 0
  fi

  baremetal_log "Destroying machine '$name'..."
  (
    cd "$VAGRANT_DIR"
    vagrant destroy -f "$name"
  )

  if baremetal_yaml_remove_machine "$name"; then
    baremetal_log "Removed '$name' from registry."
  fi

  baremetal_log "Machine '$name' destroyed."
}

baremetal_run_list() {
  baremetal_yaml_init

  local vagrant_cmd
  vagrant_cmd="$(baremetal_detect_vagrant 2>/dev/null || true)"

  if ! baremetal_yaml_exists || [ -z "$(baremetal_yaml_list_names)" ]; then
    echo ""
    echo "  No machines registered."
    echo ""
    echo "  Create one with:  baremetal up <name>"
    echo "  Sync a legacy VM: baremetal sync <name>"
    echo ""
    return
  fi

  printf '\n'
  printf '  %-20s %-10s %-8s %s\n' 'NAME' 'STATE' 'SSH' 'PORTS'
  printf '  %-20s %-10s %-8s %s\n' '────' '─────' '───' '─────'

  while IFS= read -r name; do
    [ -z "$name" ] && continue
    local state="unknown"
    if [ -n "$vagrant_cmd" ]; then
      state="$(baremetal_vagrant_status "$name")"
      [ -z "$state" ] && state="unknown"
    fi
    local cfg ssh_port host_port_80 host_port_443
    cfg="$(baremetal_yaml_get_machine "$name")"
    ssh_port=$(echo "$cfg" | grep '^ssh_port:' | awk '{print $2}')
    host_port_80=$(echo "$cfg" | grep '^host_port_80:' | awk '{print $2}')
    host_port_443=$(echo "$cfg" | grep '^host_port_443:' | awk '{print $2}')
    local ports_info="${host_port_80}:80, ${host_port_443}:443, ..."
    printf '  %-20s %-10s %-8s %s\n' "$name" "${state:-unknown}" "${ssh_port:-?}" "$ports_info"
  done <<< "$(baremetal_yaml_list_names)"

  printf '\n'
}

baremetal_run_status() {
  baremetal_run_list
}

baremetal_run_info() {
  local name="${1:-}"

  if [ -z "$name" ]; then
    baremetal_log "Usage: baremetal info <name>"
    exit 1
  fi

  baremetal_yaml_init

  if ! baremetal_yaml_machine_exists "$name"; then
    baremetal_log "Machine '$name' is not registered."
    baremetal_log "Use 'baremetal list' to see registered machines."
    exit 1
  fi

  local cfg
  cfg="$(baremetal_yaml_get_machine "$name")"
  local state
  state="$(baremetal_vagrant_status "$name")"

  echo ""
  echo "  Machine: $name"
  echo "  State:   ${state:-unknown}"
  echo ""
  echo "  Port mappings (host → guest):"
  echo "$cfg" | while IFS=: read -r key val; do
    local guest_port
    case "$key" in
      ssh_port)       guest_port="22" ;;
      host_port_80)   guest_port="80" ;;
      host_port_443)  guest_port="443" ;;
      host_port_8080) guest_port="8080" ;;
      host_port_8081) guest_port="8081" ;;
      host_port_9001) guest_port="9003" ;;
      host_port_8983) guest_port="8983" ;;
      host_port_8890) guest_port="8890" ;;
      host_port_8585) guest_port="8585" ;;
      host_port_8443) guest_port="8443" ;;
      *) continue ;;
    esac
    printf "    %-6s → %-6s (host %s)\n" "$guest_port" "$(echo "$val" | xargs)" "$(echo "$key" | xargs)"
  done
  echo ""
}

baremetal_run_sync() {
  local name="${1:-}"

  if [ -z "$name" ]; then
    baremetal_log "Usage: baremetal sync <name>"
    baremetal_log "  Synchronize the metadata of a running legacy 'default' VM"
    baremetal_log "  into the registry under the given <name>."
    exit 1
  fi

  if ! baremetal_detect_vagrant >/dev/null 2>&1; then
    baremetal_log "Vagrant is not installed or not in PATH."
    exit 1
  fi

  baremetal_yaml_init

  # Check for name collision.
  if baremetal_yaml_machine_exists "$name"; then
    baremetal_log "Machine '$name' already exists in the registry."
    baremetal_log "Choose a different name or remove it first with: baremetal destroy $name"
    exit 1
  fi

  # Verify the default machine is running.
  local state
  state="$(baremetal_vagrant_status "default")"
  if [ "$state" != "running" ]; then
    baremetal_log "The 'default' machine is not running (state: ${state:-unknown})."
    baremetal_log "Start it first: cd $VAGRANT_DIR && vagrant up default"
    exit 1
  fi

  baremetal_log "Reading port mappings from running 'default' VM..."

  # Use vagrant port to get port mappings.
  local port_output
  port_output="$(cd "$VAGRANT_DIR" && vagrant port default 2>/dev/null)"

  # Parse the port output. Typical format:
  #       22 (guest) => 2222 (host)
  #       80 (guest) => 80 (host)
  #       ...
  local ssh_port host_port_80 host_port_443 host_port_8080 host_port_8081
  local host_port_9001 host_port_8983 host_port_8890 host_port_8585 host_port_8443

  # Use leading-space-anchored patterns to avoid 80 matching 8080, etc.
  ssh_port=$(echo "$port_output" | grep -E '[[:space:]]+22 \(guest\)' | sed -n 's/.*=> \([0-9]*\).*/\1/p' | head -1)
  host_port_80=$(echo "$port_output" | grep -E '[[:space:]]+80 \(guest\)' | sed -n 's/.*=> \([0-9]*\).*/\1/p' | head -1)
  host_port_443=$(echo "$port_output" | grep -E '[[:space:]]+443 \(guest\)' | sed -n 's/.*=> \([0-9]*\).*/\1/p' | head -1)
  host_port_8080=$(echo "$port_output" | grep -E '[[:space:]]+8080 \(guest\)' | sed -n 's/.*=> \([0-9]*\).*/\1/p' | head -1)
  host_port_8081=$(echo "$port_output" | grep -E '[[:space:]]+8081 \(guest\)' | sed -n 's/.*=> \([0-9]*\).*/\1/p' | head -1)
  host_port_9001=$(echo "$port_output" | grep -E '[[:space:]]+9003 \(guest\)' | sed -n 's/.*=> \([0-9]*\).*/\1/p' | head -1)
  host_port_8983=$(echo "$port_output" | grep -E '[[:space:]]+8983 \(guest\)' | sed -n 's/.*=> \([0-9]*\).*/\1/p' | head -1)
  host_port_8890=$(echo "$port_output" | grep -E '[[:space:]]+8890 \(guest\)' | sed -n 's/.*=> \([0-9]*\).*/\1/p' | head -1)
  host_port_8585=$(echo "$port_output" | grep -E '[[:space:]]+8585 \(guest\)' | sed -n 's/.*=> \([0-9]*\).*/\1/p' | head -1)
  host_port_8443=$(echo "$port_output" | grep -E '[[:space:]]+8443 \(guest\)' | sed -n 's/.*=> \([0-9]*\).*/\1/p' | head -1)

  # Fall back to defaults for any missing ports.
  ssh_port="${ssh_port:-2222}"
  host_port_80="${host_port_80:-80}"
  host_port_443="${host_port_443:-443}"
  host_port_8080="${host_port_8080:-8282}"
  host_port_8081="${host_port_8081:-8383}"
  host_port_9001="${host_port_9001:-9004}"
  host_port_8983="${host_port_8983:-9191}"
  host_port_8890="${host_port_8890:-8890}"
  host_port_8585="${host_port_8585:-8585}"
  host_port_8443="${host_port_8443:-65535}"

  baremetal_log "Synced ports from 'default' VM:"
  baremetal_log "  SSH port:       $ssh_port"
  baremetal_log "  HTTP (80):      $host_port_80"
  baremetal_log "  HTTPS (443):    $host_port_443"
  baremetal_log "  HTTP alt (8080):$host_port_8080"
  baremetal_log "  HTTP alt (8081):$host_port_8081"
  baremetal_log "  Xdebug (9003):  $host_port_9001"
  baremetal_log "  Solr (8983):    $host_port_8983"
  baremetal_log "  Virtuoso (8890):$host_port_8890"
  baremetal_log "  PhpMyAdmin (8585): $host_port_8585"
  baremetal_log "  GitLab (8443):  $host_port_8443"

  baremetal_yaml_put_machine "$name" \
    "$ssh_port" "$host_port_80" "$host_port_443" \
    "$host_port_8080" "$host_port_8081" "$host_port_9001" \
    "$host_port_8983" "$host_port_8890" "$host_port_8585" \
    "$host_port_8443"

  baremetal_log "Machine '$name' synced and registered in $MACHINES_YML"
  baremetal_log "You can now manage it with: baremetal <up|down|ssh|destroy> $name"
}

baremetal_run_help() {
  cat <<'EOF'
baremetal — Manage multiple Vagrant VMs for the Baremetal development environment.

Usage:
  baremetal <command> [options]

Commands:
  up       <name>   Bring up a VM (creates and registers it if new).
  down     <name>   Halt a running VM.
  ssh      <name>   Open an SSH session to the VM.
  destroy  <name>   Destroy a VM and remove it from the registry.
  status            List all registered VMs and their states.
  list              Alias for status.
  info     <name>   Show detailed information about a machine.
  sync     <name>   Sync metadata from a running legacy 'default' VM
                    into the registry under <name>.

Examples:
  baremetal up dev1          Create and start a VM named 'dev1'.
  baremetal up default       Start the default VM (legacy port mappings).
  baremetal ssh dev1         SSH into dev1.
  baremetal down dev1        Halt dev1.
  baremetal destroy dev1     Destroy dev1 permanently.
  baremetal list             Show all registered VMs.
  baremetal sync legacy1     Import the running 'default' VM as 'legacy1'.

Files:
  Machine registry:  ansible/vagrant/.baremetal-machines.yml
  Vagrant directory: ansible/vagrant/
EOF
}

baremetal_main() {
  baremetal_init_context
  baremetal_init_colors

  local command="${1:-help}"
  if [ "$#" -gt 0 ]; then
    shift
  fi

  case "$command" in
    up)
      baremetal_run_up "$@"
      ;;
    down)
      baremetal_run_down "$@"
      ;;
    ssh)
      baremetal_run_ssh "$@"
      ;;
    destroy)
      baremetal_run_destroy "$@"
      ;;
    status|list)
      baremetal_run_list "$@"
      ;;
    info)
      baremetal_run_info "$@"
      ;;
    sync)
      baremetal_run_sync "$@"
      ;;
    help|-h|--help)
      baremetal_run_help
      ;;
    *)
      baremetal_log "Unknown command: $command"
      baremetal_run_help
      exit 1
      ;;
  esac
}
