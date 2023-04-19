#!/bin/bash
USERNAME=$1

if [ -z "$USERNAME" ]; then
  echo "### Username is required. See README.md for further instructions."
  exit 1
fi

# Install Ansible:
if [ ! -f /usr/bin/ansible ]; then
  echo "### Installing ansible by running: apt -y install ansible."
  apt update
  apt-add-repository ppa:ansible/ansible
  apt -y install ansible
fi  

# Enable incomming SSH connection in the host machine:
if [ ! -d /home/$USERNAME/.ssh ]; then
  echo "### Installing openssh-server by running: apt -y install openssh-server."
  apt -y install openssh-server
fi

# Created shared data directory:
if [ ! -d ansible/vagrant/data ]; then
  echo "### Creating ansible/vagrant/data folder."
  mkdir ansible/vagrant/data
fi

# Create ssh keys if needed:
if [ ! -f /home/$USERNAME/.ssh/id_rsa.pub ]; then
  echo "### Becoming original user and generating ssh keys."
  su $USERNAME
  ssh-keygen -q -b 4096 -t rsa -N '' <<< $'\ny' >/dev/null 2>&1
fi

# Enable access without password:
# If authorized_keys file does not exist:
if [ ! -f /home/$USERNAME/.ssh/authorized_keys ]; then
  echo "### Authorizing self key for self ssh session."
  # Create authorized_keys file
  cp /home/$USERNAME/.ssh/id_rsa.pub /home/$USERNAME/.ssh/authorized_keys
fi

# If authorized_keys file already exists:
if [ -f /home/$USERNAME/.ssh/authorized_keys ]; then
  echo "### Concatenating self key at the end of authorized keys file for self ssh session."
  # Concatenate pubkey in the end of file:
  cat /home/$USERNAME/.ssh/id_rsa.pub >> /home/$USERNAME/.ssh/authorized_keys
fi

# @todo: run root host.yml on install.
