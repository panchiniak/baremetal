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

### Reusing cached Vagrant binary

To speed up repeated installs, `install.sh` now reuses a cached Vagrant binary from `/tmp/baremetal/vagrant` when available.

- If the cache exists, it is copied into `ansible/vagrant/vagrant` and download/unzip can be skipped.
- After installation, the current `ansible/vagrant/vagrant` binary is saved back to `/tmp/baremetal/vagrant`.

If you want a clean install without cache reuse, clear it first with:

```bash
sudo ./install.sh --clear-tmp-baremetal-cache "$(whoami)"
```

## Custom variables

After installation you can copy `ansible/group_vars/defualt.baremetal_vars` as `ansible/group_vars/baremetal_vars` for adding your custom variables.

### Dynamic VM sizing

During `install.sh`, VM resource values are written to `ansible/vagrant/.env`.

If `VM_DISK_SIZE`, `VM_MEMORY`, or `VM_CPUS` are not defined in `config`, they are computed automatically from host resources:

- `VM_DISK_SIZE`: 1/5 of host disk (rounded up), written with `GB` suffix (example: `80GB`).
- `VM_MEMORY`: 1/10 of host memory in MB (rounded up).
- `VM_CPUS`: 1/3 of host CPUs (rounded up).

You can override these defaults by setting values in `config` before running `install.sh`:

```bash
VM_BOX=ubuntu/jammy64
VM_DISK_SIZE=100GB
VM_MEMORY=1200
VM_CPUS=4
```

If keys are present in `config`, those values are used instead of auto-detection.
