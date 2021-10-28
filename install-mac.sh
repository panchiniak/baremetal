#!/bin/bash
USERNAME=$1

# How to install in mac os:
# https://docs.ansible.com/ansible/latest/installation_guide/intro_installation.html#from-pip

# First, we want check if pip is installed:

#if [[ `python -m pip` == *"No module named"* ]]; then
#  echo "Error"
# Install pip
#fi

# curl https://bootstrap.pypa.io/get-pip.py -o get-pip.py
# python get-pip.py --user

# The install ansible:
# python -m pip install --user tornado
# python -m pip install --user nose
# python -m pip install --user ansible
# python -m pip install --user paramiko

# For allowing disk size in vagrant:
# vagrant plugin install vagrant-disksize

# Create data folder in vagrant


# Enable open-ssh following:
# https://superuser.com/questions/104929/how-do-you-run-a-ssh-server-on-mac-os-x


if [ -z "$USERNAME" ]; then
  echo "Username is required. See README.md for further instructions."
  exit 1
fi

# # Install Ansible:
# if [ ! -f /usr/bin/ansible ]; then
#   apt-add-repository ppa:ansible/ansible
#   apt update
#   apt -y install ansible
# fi  

# python -m pip install --user ansible (?)
# pip3 install ansible
# export PATH="$HOME/Library/Python/3.8/bin:/opt/homebrew/bin:$PATH"

# # Enable incomming SSH connection in the host machine:
# if [ ! -d /home/$USERNAME/.ssh ]; then
#   apt -y install openssh-server
# fi

# # Created shared data directory:
if [ ! -d ansible/vagrant/data ]; then
  mkdir ansible/vagrant/data
fi

# # Create ssh keys if needed:
# if [ ! -f /home/$USERNAME/.ssh/id_rsa.pub ]; then
#   su $USERNAME
#   ssh-keygen -t rsa -b 4096
# fi

# # Enable access without password:
# # If authorized_keys file does not exist:
# if [ ! -f /home/$USERNAME/.ssh/authorized_keys ]; then
#   # Create authorized_keys file
#   cp /home/$USERNAME/.ssh/id_rsa.pub /home/$USERNAME/.ssh/authorized_keys
# fi

# # If authorized_keys file already exists:
# if [ ! -f /home/$USERNAME/.ssh/authorized_keys ]; then
#   # Concatenate pubkey in the end of file:
#   cat /home/$USERNAME/.ssh/id_rsa.pub >> /home/$USERNAME/.ssh/authorized_keys
# fi

# # If there is no emnies_hosts variables custom file:
# if [ ! -f ./ansible/group_vars/emnies_hosts ]; then
#   # Concatenate pubkey in the end of file:
#   cp ./ansible/group_vars/emnies_hosts.default ./ansible/group_vars/emnies_hosts
#   printf "\nemnies_host_username: $USERNAME" >> ./ansible/group_vars/emnies_hosts
# fi

# # If there is no settings.local.php file copy settings.local.php.default as it
# if [ ! -f ./ansible/vagrant/data_web/assets/settings.local.php ]; then
#   # Concatenate pubkey in the end of file:
#   cp ./ansible/vagrant/data_web/assets/settings.local.php.default ./ansible/vagrant/data_web/assets/settings.local.php
# fi
