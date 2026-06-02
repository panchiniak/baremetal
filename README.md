# Baremetal Infrastructure and Applications Handler Hypervisor

This document will guide you through the installation and usage of Baremetal Infrastructure and Applications Handler Hypervisor, BH for short.
BH helps you to setup a web infrastructure for multiple purposes and multiple machines based on Vagrant and Ansible automation tools, either for the bootstrap configuration of the host machine, either for the configuration of guest machines.

## Philosophy

This program is guided by automation, freedom, independence and control as values. 

## OS Requirement

BH has been tested with:
*  Ubuntu 22.04 LTS. (as guest and host)
*  MacOS Big Sur vs. 11.6 (as host)

If this is not your OS and you still want to use BH, please consider creating a PR with the changes needed for running it at your OS.

## Install Software Requirements

Run `install.sh` passing your user name as argument:

`whoami | sudo xargs ./install.sh`

This will be used for allowing Ansible to access the host machine with no need of typing your password.

Vagrant is installed automatically via the official [HashiCorp apt repository](https://developer.hashicorp.com/vagrant/install).

## Custom variables

After installation you can copy `ansible/group_vars/default.baremetal_vars` as `ansible/group_vars/baremetal_vars` for adding your custom variables.

### Dynamic VM sizing — BAREMETAL_STAMINA

During `install.sh`, VM resource values are auto-detected from host hardware and written to `ansible/vagrant/.env`.  
The ratios used depend on the **stamina** setting, which controls how much of the host's resources are allocated to the VM.

| Setting | Flag | Memory | CPUs | Disk |
|---|---|---|---|---|
| `low` *(default)* | `--low-stamina` | 1/6 of host RAM | 1/3 of host CPUs | 1/6 of host disk |
| `high` | `--high-stamina` | 1/3 of host RAM | 1/2 of host CPUs | 1/3 of host disk |

**`low` (default)** is suitable for developer laptops that also run an IDE, browser, and other services alongside the VM.  
**`high`** is suitable for dedicated servers or CI machines where the VM is the primary workload.

#### Selecting stamina at install time

```bash
# Low stamina (default — safe for developer laptops):
sudo ./install.sh "$(whoami)"
sudo ./install.sh --low-stamina "$(whoami)"

# High stamina (dedicated / CI servers):
sudo ./install.sh --high-stamina "$(whoami)"
```

When using xws as the wrapper:

```bash
xws install                  # low stamina (default)
xws install --low-stamina
xws install --high-stamina
```

#### Explicit overrides always win

If `VM_DISK_SIZE`, `VM_MEMORY`, or `VM_CPUS` are already set in `config`, those values are used as-is and the stamina ratios are ignored for the overridden keys.

```bash
# config
VM_BOX=ubuntu/jammy64
VM_DISK_SIZE=100GB
VM_MEMORY=4096
VM_CPUS=4
```
