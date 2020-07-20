#!/usr/bin/perl
#This script is placed in host /var/lib/vz/snippets by default. 
use strict;
use warnings;
print "GUEST HOOK: " . join(' ', @ARGV). "\n";
my $vmid = shift;
my $phase = shift;
if ($phase eq 'pre-start') {
#You can also load kernel modules via host /etc/modules. More or less kmods are needed depending on different use cases. Hook script is prefered this time with pppoe and sqm modules. 
#Needed by sqm
system("modprobe -q cls_fw");
system("modprobe -q cls_flow");
system("modprobe -q sch_htb");
system("modprobe -q sch_hfsc");
#Needed by pppoe
system("modprobe -q ppp_generic");
system("modprobe -q pppoe");
system("modprobe -q slhc");
#Use dedicated device file for the lxc instance.
system("mkdir -p /dev_lxc/");
system("mknod -m 600 /dev_lxc/ppp c 108 0");
system("chown 100000:100000 /dev_lxc/ppp");
#Make dir for shared bind mount among CTs 
system("mkdir -p /run/ctshare");
#Make ctshare owned by container root, thus rw by CT is possible.
system("chown 100000:100000 /run/ctshare");
#Caution: making ctshare rw by everyone has security implications. Only uncomment the line below if it fits your case. 
#system("chmod 777 /run/ctshare");
} elsif ($phase eq 'post-start') {
} elsif ($phase eq 'pre-stop') {
} elsif ($phase eq 'post-stop') {
#Cleanup
system("rm /dev_lxc/ppp");
} else {
    die "got unknown phase '$phase'\n";
}
exit(0);
