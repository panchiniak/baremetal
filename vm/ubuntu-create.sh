#!/bin/bash
MACHINENAME=$1

# @TODO: abstract username
# Install Ansible:
# sudo apt-add-repository ppa:ansible/ansible; sudo apt update; sudo apt install ansible
# Check Ansible is installed:
# ansible --version
# Enable incomming SSH connection in the host machine:
# sudo apt install openssh-server
# And check SSH status:
# sudo systemctl status ssh
# Enable access without password:
# cd ~; cp id_rsa.pub authorized_keys
# Run playbook:
# Ping host for testing ssh/ansible self connection:
# cd <project-root>/ansible; ansible host -m ping -u rodrigo -i emnies-hosts
# Now run the test by the playbook:
# ansible-playbook -l host -i emnies-hosts -u rodrigo playbook.yml

# Download http://nl.releases.ubuntu.com/releases/18.04/ubuntu-18.04.4-live-server-amd64.iso
if [ ! -f ./home/rodrigo/Downloads/ubuntu-18.04.4-live-server-amd64.iso ]; then
    wget http://nl.releases.ubuntu.com/releases/18.04/ubuntu-18.04.4-live-server-amd64.iso -O /home/rodrigo/Downloads/ubuntu-18.04.4-live-server-amd64.iso
fi

#Create VM
VBoxManage createvm --name $MACHINENAME --ostype "Ubuntu_64" --register --basefolder `pwd`
#Set memory and network
VBoxManage modifyvm $MACHINENAME --ioapic on
VBoxManage modifyvm $MACHINENAME --memory 1024 --vram 128
VBoxManage modifyvm $MACHINENAME --nic1 nat
#Create Disk and connect Debian Iso
VBoxManage createhd --filename `pwd`/$MACHINENAME/$MACHINENAME_DISK.vdi --size 80000 --format VDI
VBoxManage storagectl $MACHINENAME --name "SATA Controller" --add sata --controller IntelAhci
VBoxManage storageattach $MACHINENAME --storagectl "SATA Controller" --port 0 --device 0 --type hdd --medium  `pwd`/$MACHINENAME/$MACHINENAME_DISK.vdi
VBoxManage storagectl $MACHINENAME --name "IDE Controller" --add ide --controller PIIX4
VBoxManage storageattach $MACHINENAME --storagectl "IDE Controller" --port 1 --device 0 --type dvddrive --medium `pwd`/debian.iso
VBoxManage modifyvm $MACHINENAME --boot1 dvd --boot2 disk --boot3 none --boot4 none

#Enable RDP
VBoxManage modifyvm $MACHINENAME --vrde on
VBoxManage modifyvm $MACHINENAME --vrdemulticon on --vrdeport 10001

#Start the VM
VBoxHeadless --startvm $MACHINENAME