#!/usr/bin/perl
#This script is placed in host /var/lib/vz/snippets by default. 
use strict;
use warnings;
print "GUEST HOOK: " . join(' ', @ARGV). "\n";
my $vmid = shift;
my $phase = shift;
if ($phase eq 'pre-start') {
#You can also load kernel modules via host /etc/modules. More or less kmods are needed depending on different use cases. Hook script is prefered this time. 
#Needed by sqm
system("modprobe sch_ingress");
system("modprobe sch_fq_codel");
system("modprobe sch_hfsc");
system("modprobe sch_htb");
system("modprobe sch_tbf");
system("modprobe cls_basic");
system("modprobe cls_fw");
system("modprobe cls_route");
system("modprobe cls_flow");
system("modprobe cls_tcindex");
system("modprobe cls_u32");
system("modprobe em_u32");
system("modprobe act_gact");
system("modprobe act_mirred");
system("modprobe act_skbedit");
system("modprobe cls_matchall");
system("modprobe act_connmark");
system("modprobe act_ctinfo");
system("modprobe sch_cake");
system("modprobe sch_netem");
system("modprobe sch_mqprio");
system("modprobe em_ipset");
system("modprobe cls_bpf");
system("modprobe cls_flower");
system("modprobe act_bpf");
system("modprobe act_vlan");
system("modprobe ifb");
#Needed by ppp
system("modprobe slhc");
system("modprobe ppp_generic");
system("modprobe pppox");
system("modprobe pppoe");
system("modprobe pppoatm");
system("modprobe ppp_async");
system("modprobe ppp_mppe");
system("modprobe ip_gre");
system("modprobe gre");
system("modprobe pptp");
#Needed by nft_chain_nat
system("modprobe nft_chain_nat");
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
