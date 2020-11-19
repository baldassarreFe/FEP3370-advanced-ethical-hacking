!# /bin/env bash

set -e

SSH_KEY="ssh_ethhack"
if [ ! -f "${SSH_KEY}" ]; then
    ssh-keygen -f "${SSH_KEY}" -t ed25519 -N ''
fi

echo -e "\e[32;1mDowloading ISO files\e[0m"
wget 'https://ftp.lysator.liu.se/ubuntu-releases/18.04.5/ubuntu-18.04.5-live-server-amd64.iso'
wget 'https://archives.fedoraproject.org/pub/archive/fedora/linux/releases/28/Server/x86_64/iso/Fedora-Server-dvd-x86_64-28-1.1.iso'
md5sum --check << EOF
18740b445159c54d10bd887650e8d1d7  Fedora-Server-dvd-x86_64-28-1.1.iso
fcd77cd8aa585da4061655045f3f0511  ubuntu-18.04.5-live-server-amd64.iso
EOF

# GATEWAY -----------------------------------------------------------------------------------------

VM_NAME="gateway"
VRDE_PORT=5001
SSH_PORT=6001
VM_USER='ubuntu'
VM_MAC='08:00:dd:dd:dd:dd'
echo -e "\e[32;1mCreating ${VM_NAME}\e[0m"

# VM creation
VBoxManage createvm --name "${VM_NAME}" --ostype Ubuntu_64 --register
VBoxManage modifyvm "${VM_NAME}" \
  --memory 2048 \
  --acpi on \
  --boot1 dvd \
  --nic1 nat \
  --nic2 intnet \
  --macaddress2 "${VM_MAC//:/}" \
  --natpf1 "guestssh,tcp,,${SSH_PORT},,22" \
  --audio none
VBoxManage createhd disk --filename "${VM_NAME}.vdi" --size 10000
VBoxManage storagectl "${VM_NAME}" --name "IDE Controller" --add ide --controller PIIX4
VBoxManage storageattach "${VM_NAME}" \
  --storagectl "IDE Controller" \
  --port 0 \
  --device 0 \
  --type hdd \
  --medium "${VM_NAME}.vdi"
VBoxManage storageattach "${VM_NAME}" \
  --storagectl "IDE Controller" \
  --port 0 \
  --device 1 \
  --type dvddrive \
  --medium "$(realpath ubuntu-18.04.5-live-server-amd64.iso)"

# OS install
echo -e "\e[32;1mPlease install OS on ${VM_NAME} (user ${VM_USER}, install ssh)\e[0m"
VBoxHeadless --startvm "${VM_NAME}" --vrde on --vrdeproperty "TCP/Ports=${VRDE_PORT}" &
sleep 3
rdesktop-vrdp "localhost:${VRDE_PORT}"
kill %%
VBoxManage storageattach "${VM_NAME}" \
  --storagectl "IDE Controller" \
  --port 0 \
  --device 1 \
  --type dvddrive \
  --medium "none"
VBoxManage modifyvm "${VM_NAME}" --vrde off

# VM configuration
echo -e "\e[32;1mConfiguring ${VM_NAME}\e[0m"
VBoxHeadless --startvm "${VM_NAME}" &
sleep 10
ansible-playbook \
  --extra-vars "ansible_port=${SSH_PORT}" \
  --user "${VM_USER}" --ask-pass \
  --ask-become-pass \
  --extra-vars "user_ssh_key_pub=${SSH_KEY}.pub" \
  "${VM_NAME}.yml"
# Leave the gateway VM on so that the other two VMs find the DHCP during installation

# ATTACKER -----------------------------------------------------------------------------------------

VM_NAME="attacker"
VRDE_PORT=5002
SSH_PORT=6002
VM_MAC='08:00:aa:aa:aa:aa'
VM_USER='ubuntu'
echo -e "\e[32;1mCreating ${VM_NAME}\e[0m"

# VM creation
VBoxManage createvm --name "${VM_NAME}" --ostype Ubuntu_64 --register
VBoxManage modifyvm "${VM_NAME}" \
  --memory 2048 \
  --acpi on \
  --boot1 dvd \
  --nic1 nat \
  --nic2 intnet \
  --macaddress2 "${VM_MAC//:/}" \
  --natpf1 "guestssh,tcp,,${SSH_PORT},,22" \
  --audio none
VBoxManage createhd disk --filename "${VM_NAME}.vdi" --size 10000
VBoxManage storagectl "${VM_NAME}" --name "IDE Controller" --add ide --controller PIIX4
VBoxManage storageattach "${VM_NAME}" \
  --storagectl "IDE Controller" \
  --port 0 \
  --device 0 \
  --type hdd \
  --medium "${VM_NAME}.vdi"
VBoxManage storageattach "${VM_NAME}" \
  --storagectl "IDE Controller" \
  --port 0 \
  --device 1 \
  --type dvddrive \
  --medium "$(realpath ubuntu-18.04.5-live-server-amd64.iso)"

# OS install
echo -e "\e[32;1mPlease install OS on ${VM_NAME} (user ${VM_USER}, install ssh)\e[0m"
VBoxHeadless --startvm "${VM_NAME}" --vrde on --vrdeproperty "TCP/Ports=${VRDE_PORT}" &
sleep 3
rdesktop-vrdp "localhost:${VRDE_PORT}"
kill %%
VBoxManage storageattach "${VM_NAME}" \
  --storagectl "IDE Controller" \
  --port 0 \
  --device 1 \
  --type dvddrive \
  --medium "none"
VBoxManage modifyvm "${VM_NAME}" --vrde off

# VM configuration
echo -e "\e[32;1mConfiguring ${VM_NAME}\e[0m"
VBoxHeadless --startvm "${VM_NAME}" &
sleep 5
ansible-playbook \
  --extra-vars "ansible_port=${SSH_PORT}" \
  --user "${VM_USER}" --ask-pass \
  --ask-become-pass \
  --extra-vars "user_ssh_key_pub=${SSH_KEY}.pub" \
  "${VM_NAME}.yml"

# VICTIM ------------------------------------------------------------------------------------------

VM_NAME="victim"
VRDE_PORT=5003
SSH_PORT=6003
VM_MAC='08:00:ff:ff:ff:ff'
VM_USER='fedora'
echo -e "\e[32;1mCreating ${VM_NAME}\e[0m"

# VM creation
VBoxManage createvm --name "${VM_NAME}" --ostype Fedora_64 --register
VBoxManage modifyvm "${VM_NAME}" \
  --memory 2048 \
  --acpi on \
  --boot1 dvd \
  --nic1 nat \
  --nic2 intnet \
  --macaddress2 "${VM_MAC//:/}" \
  --natpf1 "guestssh,tcp,,${SSH_PORT},,22" \
  --audio none
VBoxManage createhd disk --filename "${VM_NAME}.vdi" --size 10000
VBoxManage storagectl "${VM_NAME}" --name "IDE Controller" --add ide --controller PIIX4
VBoxManage storageattach "${VM_NAME}" \
  --storagectl "IDE Controller" \
  --port 0 \
  --device 0 \
  --type hdd \
  --medium "${VM_NAME}.vdi"
VBoxManage storageattach "${VM_NAME}" \
  --storagectl "IDE Controller" \
  --port 0 \
  --device 1 \
  --type dvddrive \
  --medium "$(realpath Fedora-Server-dvd-x86_64-28-1.1.iso)"

# OS install
echo -e "\e[32;1mPlease install OS on ${VM_NAME} (user ${VM_USER}, make it admin, install ssh)\e[0m"
VBoxHeadless --startvm "${VM_NAME}" --vrde on --vrdeproperty "TCP/Ports=${VRDE_PORT}" &
sleep 5
rdesktop-vrdp "localhost:${VRDE_PORT}"
kill %%
VBoxManage storageattach "${VM_NAME}" \
  --storagectl "IDE Controller" \
  --port 0 \
  --device 1 \
  --type dvddrive \
  --medium "none"
VBoxManage modifyvm "${VM_NAME}" --vrde off

# VM configuration
echo -e "\e[32;1mConfiguring ${VM_NAME}\e[0m"
VBoxHeadless --startvm "${VM_NAME}" &
sleep 12
ansible-playbook \
  --extra-vars "ansible_port=${SSH_PORT}" \
  --user "${VM_USER}" --ask-pass \
  --ask-become-pass \
  --extra-vars "user_ssh_key_pub=${SSH_KEY}.pub" \
  "${VM_NAME}.yml"

# END ---------------------------------------------------------------------------------------------
echo -e "\e[32;1mVMs running in the background:\e[0m"
jobs
VBoxManage list runningvms