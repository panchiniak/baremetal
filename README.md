# Baremetal Infrastructure and Applications Handler and Hypervisor

This document will guide you through the installation and usage of Baremetal Infrastructure and Applications Handler and Hypervisor.
Baremetal helps you to setup a web infrastructure for multiple purposes and multiple machines based on Vagrant and Ansible automation tools.


## OS Requirement

Baremetal Vagrant/Ansible Infrastructure and Applications Handler has been tested with:
*  Ubuntu 22.04.2 LTS. (as guest and host)
*  MacOS Big Sur vs. 11.6 (as host)

If this is not your OS and you still want to use Baremetal Vagrant/Ansible Infrastructure and Applications Handler, please consider creating a PR with the changes needed for running it at your OS.

## Install Software Requirements

Make `install.sh` file executable and run it passing your user name as argument:

`whoami | sudo xargs ./install.sh`

This will be used to allow Ansible to access the host machine with no need of typing your password. 

## Custom variables

After installation you can copy `ansible/group_vars/baremetal_hosts` as `ansible/group_vars/my_app_hosts` for adding your custom variables. 

## Usage

Replace `<host>` by the host you want to run the playbook against. Use -K for being asked to prompt a password:

`cd ansible`

`ansible-playbook -l host -i app_hosts -u $(whoami) host.yml --extra-vars "ansible_sudo_pass=yourPassword"`

`ansible-playbook -l host -i app_hosts -u $(whoami) host.yml -K`

`ansible-playbook -l app -i app_hosts -u vagrant guest.yml`

`ansible-playbook -l app -i app_hosts -u vagrant project-app.yml`

Warning: for safety constrains please read and understand `playbook.yml` file before running it.

## Roadmap

https://www.vagrantup.com/docs/networking/private_network.html

Generate baremetal_host_username on install, based on the current user name.

Generate port numbers at Vagrantfile based on available ports.
