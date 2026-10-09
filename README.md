# Baremetal — Infrastructure & Application Handler Hypervisor

Baremetal (BH) sets up a reproducible web-infrastructure environment based on
Vagrant and Ansible.  It bootstraps the **host** machine and provisions
**guest** VMs, and now supports multiple sibling VMs managed through the
`baremetal` CLI.

## Philosophy

Automation, freedom, independence, and control.

## Supported operating systems

BH has been tested on:

* Ubuntu 22.04 LTS (guest and host)
* macOS Big Sur 11.6 (host)

Other platforms may work but are untested.  PRs are welcome.

---

## Quick start — installation

Run `install.sh`, passing your username so Ansible can access the host
without prompting for a password:

```bash
whoami | sudo xargs ./install.sh
```

Vagrant and VirtualBox are installed automatically from the official
[HashiCorp apt repository](https://developer.hashicorp.com/vagrant/install).
Use `--skip-vagrant` if you already have them.

The script writes detected values (network bridge, VM resources, …) to
`ansible/vagrant/.env`, which the Vagrantfile reads on every `vagrant`
invocation.

---

## The `baremetal` command

`baremetal` is a CLI wrapper around Vagrant that manages **multiple sibling
VMs** instead of a single `default` machine.  It lives at the repository root.

### Symlink (optional)

```bash
ln -s "$(pwd)/baremetal" ~/.local/bin/baremetal
```

### Commands

| Command | Description |
|---|---|
| `baremetal up <name>` | Create (if new) and start a VM.  New machines get unique host-port allocations. |
| `baremetal up <name> --fixed-ip` | Same as `up`, but also assigns a static private IP for VM-to-VM networking. |
| `baremetal up <name> --fixed-ip-public[=<ip>]` | Same as `up`, but also bridges the VM onto your LAN: DHCP (router-assigned IP) by default, or a static LAN IP when given as `=<ip>`. |
| `baremetal up <name> --high-stamina` / `--low-stamina` | Same as `up`, but with per-machine resource allocation (saved in the registry; falls back to the global install.sh setting when not given). |
| `baremetal down <name>` | Halt a running VM. |
| `baremetal ssh <name>` | Open an SSH session to the VM. |
| `baremetal destroy <name>` | Destroy the VM **and** remove its metadata from the registry. |
| `baremetal list` / `baremetal status` | List all registered VMs with state, fixed IP, stamina, and port summary. |
| `baremetal info <name>` | Show detailed host → guest port mappings and fixed IP for one machine. |
| `baremetal sync <name>` | Import a running legacy `default` VM into the registry under `<name>`. |
| `baremetal connect <origin-ip> <target-ip> [--sudo]` | Set up SSH key auth from one VM to another; `--sudo` enables passwordless sudo on the target. |
| `baremetal help` | Print usage reference. |

### Examples

```bash
baremetal up dev1               # create & start a sibling VM
baremetal up dev1 --fixed-ip    # create with a static private IP
baremetal up dev1 --fixed-ip-public
                                # also bridge onto the LAN (DHCP IP)
baremetal up dev1 --fixed-ip-public=192.168.129.60
                                # also bridge onto the LAN with a static IP
baremetal up dev1 --low-stamina # create with conservative per-VM resources
baremetal up default            # start the original default VM (legacy ports)
baremetal up default --fixed-ip # add a fixed IP to an existing VM
baremetal ssh dev1              # SSH into dev1
baremetal down dev1             # halt dev1
baremetal destroy dev1          # permanently destroy dev1
baremetal list                  # see all registered VMs
baremetal sync legacy1          # import the running 'default' VM as 'legacy1'
```

### How it works

1. **Registry** — a YAML file at `ansible/vagrant/.baremetal-machines.yml`
   stores every registered machine name together with its host-side port
   numbers.  The file is created automatically on first use.

2. **Port allocation** — the first machine gets the standard base ports
   (SSH 2222, HTTP 80/8080, …).  Every subsequent machine increments each
   mapping by at least 1 and checks for cross-type collisions, so no two
   VMs share a host port.

3. **Vagrantfile integration** — when the registry contains machines the
   Vagrantfile enters *multi-machine mode* and defines one
   `config.vm.define` block per registered machine.  When the registry is
   empty it falls back to *legacy mode* with the single `default` machine,
   preserving full backward compatibility with existing workflows.

4. **Legacy sync** — if you created a VM by running `vagrant up default`
   before the `baremetal` command existed, `baremetal sync <name>` reads
   its port mappings from `vagrant port` and writes them into the registry
   so you can manage it alongside newer sibling VMs.

---

## Fixed IP — VM-to-VM networking

By default, VMs can only be reached from the host via port-forwarded
connections (e.g. `ssh -p 2222 127.0.0.1`).  The `--fixed-ip` flag adds a
**static IP on a VirtualBox host-only network** so VMs can communicate
directly with each other.

### How it works

When `--fixed-ip` is passed to `baremetal up`:

1. An available IP is auto-allocated from the VirtualBox host-only range
   `192.168.56.0/21` (192.168.56.10 – 192.168.63.254), skipping addresses
   already assigned to other machines.
2. The IP is stored in `.baremetal-machines.yml` under a `fixed_ip` key.
3. The Vagrantfile reads the stored IP and configures a `private_network`
   adapter with that static address.

Machines without `--fixed-ip` continue to use the default DHCP or
nested-static private network — no existing workflow is affected.

### Usage

```bash
# Create two VMs with fixed IPs:
baremetal up vm1 --fixed-ip      # → e.g. 192.168.56.10
baremetal up vm2 --fixed-ip      # → e.g. 192.168.56.11

# From inside vm1, reach vm2 directly:
ssh vagrant@192.168.56.11

# Add a fixed IP to an existing machine:
baremetal up default --fixed-ip  # allocates an IP, then starts the VM

# Check assigned IPs:
baremetal list                   # FIXED IP column
baremetal info vm1               # detailed view
```

### Registry format

The `fixed_ip` field is optional.  Existing machines that were created
without `--fixed-ip` simply omit it:

```yaml
machines:
  default:
    ssh_port: 2222
    host_port_80: 80
    # … other ports …
  vm1:
    ssh_port: 2223
    host_port_80: 81
    # … other ports …
    fixed_ip: 192.168.56.10
  vm2:
    ssh_port: 2224
    host_port_80: 82
    # … other ports …
    fixed_ip: 192.168.56.11
    fixed_ip_public: dhcp   # or a static LAN IP, e.g. 192.168.129.60
```

---

## Public IP — LAN networking

By default VMs are only reachable from the host (via port forwarding) and
from each other (via the host-only private network).  The
`--fixed-ip-public` flag adds an extra **bridged (public_network) adapter**,
so the VM appears on your LAN like a separate physical device: every device
on the LAN can reach it, and it shows up in your router's list of connected
clients.

### private_network vs public_network

* `private_network` — a host-only virtual network (VirtualBox `vboxnet0`,
  `192.168.56.0/21`).  Only the host and its VMs are on this network; nobody
  on the LAN can see the VM, which is why port forwarding is needed.
* `public_network` — a **bridged** adapter attached to your physical NIC
  (`PUBLIC_NETWORK_BRIDGE` in `.env`).  The VM behaves like a machine plugged
  into the same LAN/switch as the host: it can get an IP from the router's
  DHCP or use a static LAN IP.

The two can coexist: a VM with both flags gets a host-only NIC (VM ↔ host /
VM ↔ VM) **and** a bridged NIC (VM ↔ LAN), plus the default NAT NIC for
internet access.  Nothing about the existing port forwarding changes.

### How it works

When `--fixed-ip-public` is passed to `baremetal up`:

1. Without a value (`--fixed-ip-public`) the machine is bridged with **DHCP**:
   the router assigns the IP automatically.
2. With a value (`--fixed-ip-public=192.168.129.60`) the machine is bridged
   with that **static IP**.
3. The choice is stored in `.baremetal-machines.yml` under a
   `fixed_ip_public` key (`dhcp` or the IP address).
4. The Vagrantfile reads the stored value and configures a `public_network`
   adapter on the `PUBLIC_NETWORK_BRIDGE` interface.

Machines without the flag default to DHCP on the bridge.

### Usage

```bash
# Bridge with an IP assigned automatically by your router:
baremetal up vm1 --fixed-ip-public

# Bridge with a static LAN IP:
baremetal up vm1 --fixed-ip-public=192.168.129.60

# Add/change it on an existing machine (a reload applies the change):
baremetal up default --fixed-ip-public   # running → vagrant reload default

# Check assigned IPs:
baremetal list                   # PUBLIC IP column
baremetal info vm1               # detailed view
```

### Notes and caveats

* A static IP must be **free on the LAN** and **outside the router's DHCP
  pool** (or reserved for the VM in the router), otherwise you can get IP
  conflicts.
* The netmask used for static public IPs comes from `PUBLIC_NETWORK_NETMASK`
  in `ansible/vagrant/.env` (default `255.255.255.0`; `install.sh` detects it
  automatically).
* Bridging over **Wi-Fi** (`wlp3s0` here) works for outgoing traffic and
  DHCP, but other LAN devices reaching *into* the VM can be unreliable
  because many access points drop frames from MAC addresses they did not
  associate.  An Ethernet bridge is the most dependable setup.
* In nested-virtualization mode the public bridge is skipped entirely.

---

## VM-to-VM SSH and passwordless sudo

Once two (or more) VMs have fixed IPs, you often need one to SSH directly
into the other — for example, to run deployments, sync files, or execute
remote commands.  The `baremetal connect` command automates everything from
the host (it delegates to `setup-vm-ssh.sh` under the hood):

1. **Generates an SSH key** on the origin VM (ed25519, if one does not
   already exist).
2. **Authorises that key** on the target VM's `authorized_keys`.
3. **Pre-populates `known_hosts`** on the origin so the first connection
   does not prompt.
4. **Verifies** end-to-end SSH from origin → target.
5. *(Optional)* **Enables passwordless `sudo`** for the `vagrant` user on
   the target.

### Quick start

```bash
# SSH key setup only (origin → target):
baremetal connect 192.168.56.10 192.168.56.11

# SSH key setup + passwordless sudo on target:
baremetal connect 192.168.56.10 192.168.56.11 --sudo
```

After running the command, from inside the **origin** VM:

```bash
ssh vagrant@192.168.56.11          # no password prompt
```

And on the **target** VM (when `--sudo` was used):

```bash
sudo apt update                    # no password prompt
```

### How it works

| Step | What happens |
|---|---|
| Key generation | `ssh-keygen -t ed25519` runs inside origin (skipped if key exists). |
| Key authorisation | Origin's public key is appended to target's `~/.ssh/authorized_keys`. |
| Known hosts | `ssh-keyscan` adds target's host key to origin's `~/.ssh/known_hosts`. |
| Verification | The script SSHs from origin → target and checks for `SSH_OK`. |
| Passwordless sudo | A `/etc/sudoers.d/vagrant-nopasswd` file is created on target with `vagrant ALL=(ALL) NOPASSWD:ALL`, validated by `visudo -c`. |

### Prerequisites

* Both VMs must be running (`baremetal up origin --fixed-ip`,
  `baremetal up target --fixed-ip`).
* The host must be able to SSH into both VMs as `vagrant` (this is set up
  automatically by the Vagrantfile).

### Re-running the command

The command is idempotent.  Running it again skips steps that are already
done (key exists, key already authorised, sudoers already configured).

---

## Custom variables

After installation, copy the default vars file and edit it to suit your
project:

```bash
cp ansible/group_vars/default.baremetal_vars \
   ansible/group_vars/baremetal_vars
```

The playbooks load `baremetal_vars` when present, so your copy takes
precedence.

---

## Dynamic VM sizing — stamina

During `install.sh`, VM resource values are auto-detected from the host
hardware and written to `ansible/vagrant/.env`.  The ratios depend on the
**stamina** setting, which controls how much of the host's resources are
allocated to the VM.

| Setting | Flag | Memory | CPUs | Disk |
|---|---|---|---|---|
| `high` *(default)* | `--high-stamina` | ⅓ of host RAM | ½ of host CPUs | ⅓ of host disk |
| `low` | `--low-stamina` | ⅙ of host RAM | ⅓ of host CPUs | ⅙ of host disk |

**`high` (default)** is suitable for dedicated servers or CI machines where
the VM is the primary workload.  
**`low`** is suitable for developer laptops that also run an IDE, browser,
and other services alongside the VM.

### Selecting stamina at install time

```bash
# High stamina (default — dedicated / CI):
sudo ./install.sh "$(whoami)"
sudo ./install.sh --high-stamina "$(whoami)"

# Low stamina (developer laptops):
sudo ./install.sh --low-stamina "$(whoami)"
```

### Selecting stamina per VM

`baremetal up` accepts the same two flags, and the choice is stored per
machine in the registry (`stamina` key in `.baremetal-machines.yml`), so
sibling VMs can have different sizes:

```bash
baremetal up bigvm --high-stamina    # 1/3 RAM, 1/2 CPUs, 1/3 disk
baremetal up smallvm --low-stamina   # 1/6 RAM, 1/3 CPUs, 1/6 disk
baremetal up bigvm --low-stamina     # resize: applies on next reload
```

The resource values are computed with the same ratios as `install.sh`, from
the host hardware at the time `vagrant` reads the Vagrantfile.  Machines
without a `stamina` entry fall back to the global `VM_MEMORY` / `VM_CPUS` /
`VM_DISK_SIZE` values in `ansible/vagrant/.env` (the install-time setting).
Use `baremetal info <name>` to see the effective stamina of a machine.

### Explicit overrides always win

If `VM_DISK_SIZE`, `VM_MEMORY`, or `VM_CPUS` are already set in `config`,
those values are used as-is and the stamina ratios are ignored for the
overridden keys.

```bash
# config
VM_BOX=ubuntu/jammy64
VM_DISK_SIZE=100GB
VM_MEMORY=4096
VM_CPUS=4
```

---

## File overview

| Path | Purpose |
|---|---|
| `baremetal` | CLI entry point for multi-VM management. |
| `libexec/baremetal-common.sh` | Shared library (context init, YAML helpers, port allocator, commands). |
| `setup-vm-ssh.sh` | Configures VM-to-VM SSH key auth and optional passwordless sudo. |
| `install.sh` | Host bootstrap: Vagrant, VirtualBox, `.env` generation. |
| `config` | Default values read by `install.sh` (`VM_BOX`, …). |
| `ansible/vagrant/Vagrantfile` | VM definition — supports both legacy `default` and multi-machine mode. |
| `ansible/vagrant/.env` | Runtime overrides (bridge, RAM, CPU, disk, …). |
| `ansible/vagrant/.baremetal-machines.yml` | Machine registry (auto-managed by `baremetal`). |
| `ansible/group_vars/default.baremetal_vars` | Ansible variable defaults for guest provisioning. |
| `ansible/baremetal_hosts` | Ansible inventory. |
| `ansible/lib/` | Playbooks (host, guest, site provisioning, …). |
| `ansible/roles/` | External Ansible roles (auto-installed). |

---

## Troubleshooting

* **"Vagrant is not installed"** — run `install.sh` or install Vagrant
  manually and ensure it is on `PATH`.
* **Port collision** — `baremetal` refuses to allocate a port already owned
  by another registered machine.  Run `baremetal list` to audit.
* **Legacy VM not showing in `baremetal list`** — use `baremetal sync`
  while the VM is running to import its metadata.
* **Vagrantfile complains about missing `.env`** — run `install.sh` to
  generate it, or create `ansible/vagrant/.env` manually with the required
  keys (`HOST_USER_NAME`, `PUBLIC_NETWORK_BRIDGE`, `VM_BOX`,
  `VM_DISK_SIZE`, `VM_MEMORY`, `VM_CPUS`).
