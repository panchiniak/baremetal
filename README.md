# EMNIES Ansible Project Handler

This document will guide you through the installation of EMNIES Ansible Project Handler. 


## OS Requirement

EMNIES Ansible Project Handler has been tested in:
*  Ubuntu 18.04.4 LTS. 

If this is not your OS and you still want to use EMNIES Ansible Project Handler, please consider creating a PR with the changes needed for running it at your OS.

## Install Software Requirements

Make `install.sh` file executable, replace `<username>` by your user name and run:

`sudo ./install.sh <username>`

This will be used to allow Ansible to access the host machine with no need of typing your password. 

## Usage: change and/or run your playbook

`cd ansible`

`ansible-playbook -l <host> -i emnies-hosts -u <user-name> playbook.yml`

Warning: read and understand `playbook.yml` file before running it. For safety concerns you should understand what you are doing.
