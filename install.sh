#!/bin/bash
USERNAME=$1

# Function copied from https://stackoverflow.com/questions/24398242/check-if-service-exists-in-bash-centos-and-ubuntu
service_exists() {
    local n=$1
    if [[ $(systemctl list-units --all -t service --full --no-legend "$n.service" | sed 's/^\s*//g' | cut -f1 -d' ') == $n.service ]]; then
        return 0
    else
        return 1
    fi
}

if [ -z "$USERNAME" ]; then
  echo "### Username is required. See README.md for further instructions."
  exit 1
fi

if [ -f /usr/bin/ansible ]; then
  echo "### Ansible already installed. Skipping instalation."
fi

# Install Ansible:
if [ ! -f /usr/bin/ansible ]; then
  echo "### Installing ansible by running: apt -y install ansible."
  apt update
  apt-add-repository ppa:ansible/ansible
  apt -y install ansible
fi  

if service_exists ssh; then
  echo "### openssh-server is already installed. Skipping instalation."
else
  echo "### Installing openssh-server by running: apt -y install openssh-server."
  apt -y install openssh-server
fi

# Create shared data directory:
if [ ! -d ansible/vagrant/data ]; then
  echo "### Creating ansible/vagrant/data folder."
  mkdir ansible/vagrant/data
else
  echo "### Folder ansible/vagrant/data already created. Skipping creation."
fi

# Create ssh keys if needed:
if [ ! -f /home/$USERNAME/.ssh/id_rsa.pub ]; then
  echo "### Becoming initial user and generating ssh keys."
  su $USERNAME
  ssh-keygen -q -b 4096 -t rsa -N '' <<< $'\ny' >/dev/null 2>&1
else
  echo "### SSH keys already created. Skipping creation."
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
