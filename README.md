# EMNIES Ansible Project Handler

This document will guide you through the installation of EMNIES Ansible Project Handler. 


## OS Requirement

EMNIES Ansible Project Handler has been tested in:
*  Ubuntu 18.04.4 LTS. 

If this is not your OS and you still want to use EMNIES Ansible Project Handler, please consider creating a PR with the changes needed for running it at your OS.

## Install Software Requirements

Make `install.sh` file executable:

`whoami | sudo xargs ./install.sh`

This will be used to allow Ansible to access the host machine with no need of typing your password. 

## Usage

Replace `<host>` by the host you want to run the playbook against:

`cd ansible`

`ansible-playbook -l <host> -i emnies_hosts -u $(whoami) playbook.yml --extra-vars "ansible_sudo_pass=yourPassword"`

Warning: read and understand `playbook.yml` file before running it. For safety concerns you should always understand what you are doing.

## Custom variables

After installation you can add your custom variables at `ansible/group_vars/emnies_hosts`