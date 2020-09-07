#!/bin/bash
#Storage name in Proxmox for CT instance rootfs disk
ctStrg="local-lvm"
#Full path of Proxmox pct utility
CMD="/usr/sbin/pct"
#Path of Proxmox CT conf
ct_conf_path="/etc/pve/lxc"
#OpenWRT config backup filename
backup_filename="opctbak"
#bind mount MP in the CT instance
guest_mp_path="/shared"
#bind mount dirname on host
host_share_dirname="ctshare"
#bind mount full path on host
host_mp_path="/run/$host_share_dirname"
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

check_oldct() {
	#The old ct conf file full path name
	octfn="$ct_conf_path"/"$oldct".conf
	local oldstat=""
	oldstat=$("$CMD" status "$oldct" 2>&1 | grep running)
	if [ -z "$oldstat" ]; then
		echo "The old CT does not exist or is not running."
		exit 1
	fi
}

check_newct() {
	#The new ct conf file full path name
	nctfn="$ct_conf_path"/"$newct".conf
	local newstat=""
	newstat=$("$CMD" status "$newct" 2>&1 | grep status)
	if [ -n "$newstat" ]; then
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
	#The CTs use a bind mount of host_mp_path on host to share files among them.
	mkdir -p "$host_mp_path"
	chown 100000:100000 "$host_mp_path"
	local newstat=""
	ctname=$(basename "$ct_template" | cut -d'-' -f1)-$(basename "$ct_template" | cut -d'-' -f3)
	"$CMD" create "$newct" "$ct_template" --rootfs "$ctStrg":"$rf_size" --ostype unmanaged --hostname "$ctname" --arch "$arch" --cores "$cores" --memory "$memory" --mp0 "$host_mp_path/,mp=$guest_mp_path" --swap "$swap" --unprivileged "$unprivileged"
	newstat=$?
	if [ "$newstat" -ne 0 ]; then
		echo "Failed to Create CT"
		exit 1
	fi
	echo "New CT Created."
}

oldct_backup() {
	if [ -f "$host_mp_path"/"$backup_filename" ]; then
		rm "$host_mp_path"/"$backup_filename"
	fi
	"$CMD" exec "$oldct" -- ash -c "sysupgrade -b $guest_mp_path/$backup_filename"
	local res=$?
	if [ $res -eq 0 ]; then
		echo "Old CT conf backup completed."
	else
		echo "Old CT conf backup failed."
		exit 1
	fi
}

newct_restore() {
	local newstat=""
	"$CMD" start "$newct"
	newstat=$?
	if [ "$newstat" -eq 0 ]; then
		#Wait for the new CT init complete.
		sleep 5
		"$CMD" exec "$newct" -- ash -c "sysupgrade -r $guest_mp_path/$backup_filename"
		local res=$?
		if [ $res -eq 0 ]; then
			echo "New CT conf restored."
		else
			echo "New CT conf restoration failed."
			exit 1
		fi
	else
		echo "The new CT is not running. Failed to restore."
		exit 1
	fi
}

stop_oldct() {
	local oldstat=""
	"$CMD" stop "$oldct"
	oldstat=$?
	if [ "$oldstat" -ne 0 ]; then
		echo "The old CT is not stopped."
		exit 1
	fi
	echo "The old CT stopped."
}

stop_newct() {
	local newstat=""
	"$CMD" stop "$newct"
	newstat=$?
	if [ "$newstat" -ne 0 ]; then
		echo "The new CT is not stopped."
		exit 1
	fi
	echo "The new CT stopped."
}

copyconf_old2new() {
	#Copy remaining bind mounts to the new ct. 10 bind mounts ought to be enough.
	grep "^mp[1-9]" "$octfn" >>"$nctfn"
	#Copy nics to the new ct. 10 nics ought to be enough.
	grep "^net[0-9]" "$octfn" >>"$nctfn"
	#For the lxc settings.
	grep "^lxc" "$octfn" >>"$nctfn"
	#Hookscript
	grep "^hookscript" "$octfn" >>"$nctfn"
	#Set the new ct start onboot
	grep onboot "$octfn" >>"$nctfn"
	grep order "$octfn" >>"$nctfn"
	#Turn off start onboot for the old ct. Not using sed -i due to bug on pve.
	local tmp=""
	tmp=$(mktemp)
	sed -e '/^onboot/s/^/#/' "$octfn" >"$tmp" && cat "$tmp" >"$octfn" && rm "$tmp"
	echo "Conf from the old to the new one copied."
}

start_newct() {
	local newstat=""
	"$CMD" start "$newct"
	newstat=$?
	if [ "$newstat" -ne 0 ]; then
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
	#The vmid of the new OpenWRT lxc instance to be created
	declare -i newct=$2
	#The path and filename of the OpenWRT plain template
	ct_template=$3
	if [ -z "$ct_template" ] || [ "$newct" -le "0" ]; then
		echo "This command creates a new OpenWRT lxc instance based on a user-specified CT template."
		echo "Usage: $0 <new|ne> <New_vmid> <CT_template>"
		exit 1
	fi
	if [ ! -f "$ct_template" ]; then
		echo "$ct_template does not exist."
		exit 1
	fi
	check_newct
	retval=$?
	if [ "$retval" -eq 1 ]; then
		echo "The new CT already exists."
		exit 1
	fi
	create_newct
	echo "Please note that this new instance does NOT contain any nic. You may need to do the network configuration later via Proxmox VE GUI or CLI. "
	exit 0
}

doswap() {
	#The old and running OpenWRT lxc instance vmid
	declare -i oldct=$2
	#The vmid of the new OpenWRT lxc instance to be created
	declare -i newct=$3
	if [ -z "$newct" ] || [ "$oldct" -le "0" ] || [ "$newct" -le "0" ] || [ "$oldct" == "$newct" ]; then
		echo "This command stops the old OpenWRT lxc instance, then starts the new one, effectively does the swapping."
		echo "Usage: $0 <swap|sw> <Old_vmid> <New_vmid>"
		exit 1
	fi
	check_oldct
	check_newct
	retval=$?
	if [ "$retval" -eq 0 ]; then
		echo "The new CT does not exist."
		exit 1
	fi
	stop_oldct
	start_newct
	echo "OpenWRT CT instances swapping completed."
	exit 0
}

doupgrade() {
	#The old and running OpenWRT lxc instance vmid
	declare -i oldct=$2
	#The vmid of the new OpenWRT lxc instance to be created
	declare -i newct=$3
	#The path and filename of the OpenWRT plain template
	ct_template=$4
	if [ -z "$ct_template" ] || [ "$oldct" -le "0" ] || [ "$newct" -le "0" ] || [ "$oldct" == "$newct" ]; then
		echo "This command creates an upgrade of the running OpenWRT lxc instance based on a user-specified CT template."
		echo "Usage: $0 <upgrade|up> <Old_vmid> <New_vmid> <CT_template>"
		exit 1
	fi
	if [ ! -f "$ct_template" ]; then
		echo "$ct_template does not exist."
		exit 1
	fi
	check_oldct
	check_newct
	retval=$?
	if [ "$retval" -eq 1 ]; then
		echo "The new CT already exists."
		exit 1
	fi
	oldct_backup
	getoctpara
	create_newct
	newct_restore
	stop_newct
	copyconf_old2new
	echo "An upgraded instance of OpenWRT CT has been created successfully. "
	echo "The old instance is left untouched except start_onboot disabled."
	echo "The new instance is independent of the old one. Users may delete the old instances via pct destory when they see fit."
	exit 0
}

subcmd="$1"
case $subcmd in
	"new" | "ne") donew "$@" ;;
	"upgrade" | "up") doupgrade "$@" ;;
	"swap" | "sw") doswap "$@" ;;
	*) usage ;;
esac
