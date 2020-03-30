#!/bin/bash
USERNAME=$1

# Install Ansible:
if [ ! -f /usr/bin/ansible ]; then
  apt-add-repository ppa:ansible/ansible
  apt update
  apt install ansible
fi  

# Enable incomming SSH connection in the host machine:
if [ ! -d /home/$USERNAME/.ssh ]; then
  apt install openssh-server
fi

# Create ssh keys if needed:
if [ ! -f /home/$USERNAME/.ssh/id_rsa.pub ]; then
  su $USERNAME
  ssh-keygen -t rsa -b 4096
fi

# Enable access without password:
# If authorized_keys file does not exist:
if [ ! -f /home/$USERNAME/.ssh/authorized_keys ]; then
  # Create authorized_keys file
  cp /home/$USERNAME/.ssh/id_rsa.pub /home/$USERNAME/.ssh/authorized_keys
fi

# If authorized_keys file already exists:
if [ ! -f /home/$USERNAME/.ssh/authorized_keys ]; then
  # Concatenate pubkey in the end of file:
  cat /home/$USERNAME/.ssh/id_rsa.pub >> /home/$USERNAME/.ssh/authorized_keys
fi
