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
| `baremetal down <name>` | Halt a running VM. |
| `baremetal ssh <name>` | Open an SSH session to the VM. |
| `baremetal destroy <name>` | Destroy the VM **and** remove its metadata from the registry. |
| `baremetal list` / `baremetal status` | List all registered VMs with state, fixed IP, and port summary. |
| `baremetal info <name>` | Show detailed host → guest port mappings and fixed IP for one machine. |
| `baremetal sync <name>` | Import a running legacy `default` VM into the registry under `<name>`. |
| `baremetal help` | Print usage reference. |

### Examples

```bash
baremetal up dev1               # create & start a sibling VM
baremetal up dev1 --fixed-ip    # create with a static private IP
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
```

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
