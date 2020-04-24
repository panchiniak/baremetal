# EMNIES Ansible Project Handler

This document will guide you through the installation and usage of EMNIES Ansible Project Handler. 


## OS Requirement

EMNIES Ansible Project Handler has been tested for both host and guest sides with:
*  Ubuntu 18.04.4 LTS. 

If this is not your OS and you still want to use EMNIES Ansible Project Handler, please consider creating a PR with the changes needed for running it at your OS.

## Install Software Requirements

Make `install.sh` file executable and run it passing your user name as argument:

`whoami | sudo xargs ./install.sh`

This will be used to allow Ansible to access the host machine with no need of typing your password. 

## Custom variables

After installation you can add your custom variables at `ansible/group_vars/emnies_hosts`

## Usage

Replace `<host>` by the host you want to run the playbook against:

`cd ansible`

`ansible-playbook -l host -i emnies_hosts -u $(whoami) host.yml --extra-vars "ansible_sudo_pass=yourPassword"`

`ansible-playbook -l emnies -i emnies_hosts -u vagrant guest.yml`

`ansible-playbook -l emnies -i emnies_hosts -u vagrant project-emnies.yml`

Warning: for safety constrains please read and understand `playbook.yml` file before running it.

## Roadmap

https://www.vagrantup.com/intro/getting-started/share.html

https://www.vagrantup.com/docs/networking/private_network.html
