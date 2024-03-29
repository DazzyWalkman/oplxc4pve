oplxc4pve
===========

Wrapper script for creating/upgrading unprivileged lxc instances from OpenWrt rootfs templates on the Proxmox VE hypervisor. 

Requirements
------------
The Proxmox VE 6.2 or later. 
This script or the resulting OpenWrt instances may work on older pve versions, however it's untested.
 
Configuration
-------------
Please refer to the top of opct.sh.

Usage and examples
------
Creating a new lxc instance of OpenWrt without nic: 

./opct.sh <new|ne> <New_vmid> <CT_template>

example: 

create new lxc instance with vmid 101, base on an openwrt template "/tmp/openwrt-snapshot-r13212-x86-64-plain.tar.gz"

./opct.sh new 101 /tmp/openwrt-snapshot-r13212-x86-64-plain.tar.gz

Notes: The new instance does NOT contain any nic. You may need to do the network configuration later via Proxmox VE GUI or CLI. And if you need the OpenWrt instance to access certain kernel features, e.g. making tunnel connection, accessing char devices in /dev, you may have to load the related kernel modules, grant the container certain rights on host startup, or preferably via hookscript. Please see "files" directory for detail.

------
Upgrading a running lxc instance of OpenWrt

./opct.sh <upgrade|up> <Old_vmid> <New_vmid> <CT_template>

example:

upgrade a running instance with vmid 101, base on an openwrt template "/tmp/openwrt-snapshot-r13212-x86-64-plain.tar.gz". The resulting new instance is assigned vmid 102.

./opct.sh upgrade 101 102 /tmp/openwrt-snapshot-r13212-x86-64-plain.tar.gz

------
Stop the old OpenWrt lxc instance, then start the new one, effectively do the swapping. Make OpenWrt downtime as short as possible.

./opct.sh <swap|sw> <Old_vmid> <New_vmid>

example:

Swap a running old instance (vmid 101), with new one (vmid 102)

./opct.sh swap 101 102

Please note:  It's advisable to run ./opct.sh swap inside screen or tmux, to avoid unexpected termination of this script, for the ssh session to the pve host may end when the old OpenWrt instance which handles WAN/LAN connection is shutdown. 

SEE ALSO:

Manpage for Proxmox VE pct utility: https://pve.proxmox.com/pve-docs/pct.1.html

Manual: pct.conf: https://pve.proxmox.com/wiki/Manual:_pct.conf

PVE Storage: https://pve.proxmox.com/wiki/Storage

Network Configuration: https://pve.proxmox.com/wiki/Network_Configuration

Further details (bind mounts, network and more) on lxc: https://pve.proxmox.com/wiki/Linux_Container


