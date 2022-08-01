#!/bin/bash
#Option for automatic ct hostname generation
declare -i autoname="1"
#Preset hostname for the ct
ctname=""
#Storage name in Proxmox for CT instance rootfs disk
ctStrg="local-lvm"
#Path of Proxmox CT conf
ct_conf_path="/etc/pve/lxc"
#rootfs size for the new CT instance in GB
rf_size="0.2"
#memory size for the new CT instance in MB
declare -i memory="128"
#arch of the new CT instance
arch="amd64"
#num of cpu cores assigned to the new CT instance
declare -i cores="1"
#swap size in MB
declare -i swap="0"
#unprivileged or not
declare -i unprivileged="1"
#OpenWrt config backup filename. DO NOT EDIT. Using non-default value will BREAK OpenWrt built-in config restoration after upgrade.
declare -r backup_filename="sysupgrade.tgz"

check_ct() {
	local ctid="$1"
	local chkstat="$2"
	local ctstat=""
	ctstat=$("$CMD" status "$ctid" 2>&1 | grep "$chkstat")
	if [ -n "$ctstat" ]; then
		return 1
	else
		return 0
	fi
}

create_newct() {
	#if the rootfs fails to hold the tarball content with 50% free space remaining, then set rootfs to the double of the tarball size.
	local tar_size=""
	tar_size=$(tar tzvf "$ct_template" | awk '{s+=$3} END{print (s/1024/1024/512)}')
	if [ $(echo "$tar_size > $rf_size" | bc) -ne 0 ]; then
		echo "The tarball is larger than the previously defined rootfs size. Increase the rootfs size to $tar_size GB."
		rf_size="$tar_size"
	fi
	if [ "$autoname" -ne 0 ]; then
		ctname=$(tar xfO "$ct_template" ./etc/openwrt_release 2>/dev/nul | grep DISTRIB_DESCRIPTION | sed -e "s/.*='\(.*\)'/\1/")
		if [ ! "$ctname" ]; then
			echo "Failed to extract ct name from the openwrt_release file. Fallback to extracting from the template filename."
			ctname=$(basename "$ct_template" | cut -d'-' -f1)-$(basename "$ct_template" | cut -d'-' -f2)-$(basename "$ct_template" | cut -d'-' -f3)-$(basename "$ct_template" | cut -d'-' -f4)
		fi
	else
		echo "Autoname is off. "
	fi
	ctname=$(echo "$ctname" | sed -e 's/[^a-zA-Z0-9-]/-/g' | sed -e 's/^--*//' | sed -e 's/--*$//')
	if [ ! "$ctname" ]; then
		ctname="Unknown"
	fi
	if ! "$CMD" create "$newct" "$ct_template" --rootfs "$ctStrg":"$rf_size" --ostype unmanaged --hostname "$ctname" --arch "$arch" --cores "$cores" --memory "$memory" --swap "$swap" --unprivileged "$unprivileged"; then
		echo "Failed to Create CT"
		exit 1
	fi
	echo "New CT Created."
}

oldct_backup() {
	confbakdir=$(mktemp -d -p /run)
	if [ ! -d "$confbakdir" ]; then
		echo "Failed to make tempdir. Abort."
		exit 1
	fi
	if "$CMD" exec "$oldct" -- ash -c "sysupgrade -b /tmp/$backup_filename"; then
		"$CMD" pull "$oldct" /tmp/"$backup_filename" "$confbakdir"/"$backup_filename"
		if [ -f "$confbakdir"/"$backup_filename" ]; then
			echo "Old CT conf backup completed."
		fi
	else
		echo "Old CT conf backup failed."
		exit 1
	fi
}

newct_restore() {
	#Validate the config backup file
	if gunzip -c "$confbakdir"/"$backup_filename" | tar -t >/dev/null; then
		local newct_rootfs=""
		newct_rootfs=$("$CMD" mount "$newct" | cut -d \' -f2)
		if [ -d "$newct_rootfs" ]; then
			#Copy the config backup file to the newct root. It will get restored during the first boot of the new ct.
			cp "$confbakdir"/"$backup_filename" "$newct_rootfs"
			#Clean up
			if [ -f "$newct_rootfs"/"$backup_filename" ]; then
				rm -rf "$confbakdir"
			fi
			if ! "$CMD" unmount "$newct"; then
				exit 1
			fi
			echo "New CT conf copied."
		else
			echo "Cannot mount the rootfs of the new CT. Failed to restore config."
			exit 1
		fi
	else
		echo "Invalid conf for the new ct."
		exit 1
	fi
}

stop_oldct() {
	if ! "$CMD" shutdown "$oldct"; then
		echo "The old ct is not shutdown. Try force stop."
		if ! "$CMD" stop "$oldct"; then
			echo "The old CT is not stopped."
			exit 1
		else
			echo "The old CT is stopped."
		fi
	else
		echo "The old CT is shutdown."
	fi
}

copyconf_old2new() {
	#Copy bind mounts to the new ct. a maximum number of 256 mps is allowed.
	grep -E "^mp([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])" "$octfn" >>"$nctfn"
	#Copy nics to the new ct. As of pve-container 3.1-13, a maximum number of 32 nics is allowed.
	grep -E "^net([0-9]|[12][0-9]|3[01])" "$octfn" >>"$nctfn"
	#For the lxc settings.
	grep "^lxc" "$octfn" >>"$nctfn"
	#Hookscript
	grep "^hookscript" "$octfn" >>"$nctfn"
	#Set the new ct start onboot setting following the old ct.
	grep "^onboot" "$octfn" >>"$nctfn"
	grep order "$octfn" >>"$nctfn"
	#Turn off start onboot for the old ct.
	"$CMD" set "$oldct" -onboot 0
	echo "Conf from the old to the new one copied."
}

start_newct() {
	if ! "$CMD" start "$newct"; then
		echo "The new CT is not started."
		exit 1
	fi
	echo "The new CT is started."
}

usage() {
	echo "$0 <new|upgrade|swap>"
	exit 1
}

getoctpara() {
	if [ "$autoname" -eq 0 ]; then
		echo "Autoname is off. Take ctname from the old ctname."
		ctname=$(grep "^hostname" "$octfn" | cut -d" " -f2)
	fi
	arch=$(grep "^arch" "$octfn" | cut -d" " -f2)
	cores=$(grep "^cores" "$octfn" | cut -d" " -f2)
	memory=$(grep "^memory" "$octfn" | cut -d" " -f2)
	ctStrg=$(grep "^rootfs" "$octfn" | cut -d":" -f2 | xargs)
	local tmp_size=""
	tmp_size=$(grep "^rootfs" "$octfn" | cut -d"=" -f2)
	case $(echo -n "$tmp_size" | tail -c 1) in
		"G") rf_size=$(echo "$tmp_size" | cut -d"G" -f1) ;;
			#When an integer is divided by 1024 (2^10), 10 decimal digits after the decimal point is enough.
		"M") rf_size=$(echo "$(echo "$tmp_size" | cut -d"M" -f1) 1024" | awk '{printf "%.10f",$1 / $2}') ;;
		*) echo "The disk size of the old ct is unknown. Default Value will be used." ;;
	esac
	swap=$(grep "^swap" "$octfn" | cut -d" " -f2)
	unprivileged=$(grep "^unprivileged" "$octfn" | cut -d" " -f2)
}

donew() {
	#The vmid of the new OpenWrt lxc instance to be created
	declare -i newct=$2
	#The path and filename of the OpenWrt plain template
	ct_template=$3
	if [ -z "$ct_template" ] || [ "$newct" -le "0" ] || [ -n "$4" ]; then
		echo "This command creates a new OpenWrt lxc instance based on a user-specified CT template."
		echo "Usage: $0 <new|ne> <New_vmid> <CT_template>"
		exit 1
	fi
	if [ ! -f "$ct_template" ]; then
		echo "$ct_template does not exist."
		exit 1
	fi

	if ! check_ct "$newct" status; then
		echo "The new CT already exists."
		exit 1
	fi
	create_newct
	echo "Please note that this new instance does NOT contain any nic. You may need to do the network configuration later via Proxmox VE GUI or CLI."
	echo 'And you may also have to adjust the hookscript settings of the new ct. Please see "files" directory for detail.'
	exit 0
}

doswap() {
	#The old and running OpenWrt lxc instance vmid
	declare -i oldct=$2
	#The vmid of the new OpenWrt lxc instance to be created
	declare -i newct=$3
	if [ -z "$newct" ] || [ "$oldct" -le "0" ] || [ "$newct" -le "0" ] || [ "$oldct" == "$newct" ] || [ -n "$4" ]; then
		echo "This command stops the old OpenWrt lxc instance, then starts the new one, effectively does the swapping."
		echo "Usage: $0 <swap|sw> <Old_vmid> <New_vmid>"
		exit 1
	fi
	if check_ct "$oldct" running; then
		echo "The old CT does not exist or is not running."
		exit 1
	fi

	if check_ct "$newct" stopped; then
		echo "The new CT does not exist or is not stopped."
		exit 1
	fi
	stop_oldct
	start_newct
	echo "OpenWrt CT instances swapping completed."
	exit 0
}

doupgrade() {
	#The old and running OpenWrt lxc instance vmid
	declare -i oldct=$2
	#The vmid of the new OpenWrt lxc instance to be created
	declare -i newct=$3
	#The old ct conf file full path name
	octfn="$ct_conf_path"/"$oldct".conf
	#The new ct conf file full path name
	nctfn="$ct_conf_path"/"$newct".conf
	#The path and filename of the OpenWrt plain template
	ct_template=$4
	if [ -z "$ct_template" ] || [ "$oldct" -le "0" ] || [ "$newct" -le "0" ] || [ "$oldct" == "$newct" ] || [ -n "$5" ]; then
		echo "This command creates an upgrade of the running OpenWrt lxc instance based on a user-specified CT template."
		echo "Usage: $0 <upgrade|up> <Old_vmid> <New_vmid> <CT_template>"
		exit 1
	fi
	if [ ! -f "$ct_template" ]; then
		echo "$ct_template does not exist."
		exit 1
	fi
	if check_ct "$oldct" running; then
		echo "The old CT does not exist or is not running."
		exit 1
	fi
	if ! check_ct "$newct" status; then
		echo "The new CT already exists."
		exit 1
	fi
	oldct_backup
	getoctpara
	create_newct
	newct_restore
	copyconf_old2new
	echo "An upgraded instance of OpenWrt CT has been created successfully. "
	echo "The old instance is left untouched except start_onboot disabled."
	echo "The new instance is independent of the old one. Users may delete the old instances via pct destroy when they see fit."
	exit 0
}
preq_chk() {
	CMD=$(command -v pct)
	if [ ! -x "$CMD" ]; then
		echo "Pct utility not found. Abort."
		exit 1
	fi
	if [ "$(id -u)" != 0 ]; then
		echo "You have to get root privileges to run this script. Abort."
		exit 1
	fi
}

preq_chk
subcmd="$1"
case $subcmd in
	"new" | "ne") donew "$@" ;;
	"upgrade" | "up") doupgrade "$@" ;;
	"swap" | "sw") doswap "$@" ;;
	*) usage ;;
esac
