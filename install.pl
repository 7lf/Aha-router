#!/usr/bin/perl

# Check if script running by root
my $login = (getpwuid $>);
 if ($login ne "root") {
    print "Must run as root!\n";
    exit 1;
 }

 # Count network cards
my @lans = `ls /sys/class/net | grep enp*`;
my @wlans = `ls /sys/class/net | grep wlp*`;
my $networkCount = length(@lans) + length(@wlans);

if ($networkCount < 2) {
   print "At least 2 network cards needeed!";
   exit 2;
}

`apt install -y isc-dhcp-server`; #iptables-persistent 

`cp /etc/netplan/00-installer-config.yaml /etc/netplan/00-installer-config.yaml.backup`;
my $handle;
unless (open $handle, "<:encoding(utf8)", "/etc/netplan/00-installer-config.yaml") {
   print STDERR "Could not open file '/etc/00-installer-config.yaml': $!\n";
   return undef
}
my @lines = <$handle>;
unless (close $handle) {
   print STDERR "Don't care error while closing '/etc/netplan/00-installer-config.yaml': $!\n";
}

# make bridge
my $firstLan = shift @lans; ## delete 1st lan
chomp($firstLan);
my $newConfig = "
# This is the network config written by 'aha-router'
network:
  version: 2
  ethernets:
    $firstLan:
      dhcp4: true\n";
foreach (@lans) {
  chomp($_);
  $newConfig .= "    $_:\n      dhcp4: false\n";
}
foreach (@wlans) {
  chomp($_);
  $newConfig .= "    $_:\n      dhcp4: false\n";
}

$newConfig .= "
  bridges:
    br0:
      addresses: [192.168.7.1/24]
      nameservers:
        addresses: [8.8.8.8,1.1.1.1,8.8.1.1]
      dhcp4: no
      dhcp6: no
      interfaces:\n";
foreach (@lans) {
  chomp($_);
  $newConfig .= "        - $_\n";
}

foreach (@wlans) {
  chomp($_);
  $newConfig .= "        - $_\n";
}

unless (open $handle, ">:encoding(utf8)", "/etc/netplan/00-installer-config.yaml") {
   print STDERR "Could not open file '/etc/00-installer-config.yaml': $!\n";
   return undef
}
print $handle $newConfig;
unless (close $handle) {
   print STDERR "Don't care error while closing '/etc/netplan/00-installer-config.yaml': $!\n";
} 

`netplan generate && netplan apply && echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf && sysctl -p`;

`iptables -F && iptables -X`;
`iptables -t nat -A POSTROUTING -o br0 -j MASQUERADE`;
`iptables -t nat -A OUTPUT -p udp --dport 53 -j DNAT --to 8.8.8.8:53`;
`iptables -t nat -A OUTPUT -p tcp --dport 53 -j DNAT --to 1.1.1.1:53`;
`iptables -t nat -A OUTPUT -p tcp --dport 53 -j DNAT --to 8.8.1.1:53`;
`iptables-save > /etc/iptables/rules.v4`;

# DHCP
`cp /etc/dhcp/dhcpd.conf /etc/dhcp/dhcpd.conf.backup`;
my $dhcpdConf = "# dhcpd.conf\n# Created by Aha router\n
option domain-name \"example.org\";
option domain-name-servers 8.8.8.8,1.1.1.1,8.8.1.1;

default-lease-time 600;
max-lease-time 7200;

ddns-update-style none;

authoritative;

subnet 192.168.7.0 netmask 255.255.255.0 {
  range 192.168.7.2 192.168.7.250;
  option domain-name-servers 8.8.8.8,1.1.1.1,8.8.1.1;
  option domain-name \"internal.example.org\";
  option subnet-mask 255.255.255.0;
  option routers 192.168.7.1;
  option broadcast-address 192.168.7.255;
  default-lease-time 600;
  max-lease-time 7200;
}
";
unless (open $handle, ">:encoding(utf8)", "/etc/dhcp/dhcpd.conf") {
   print STDERR "Could not open file '/etc/dhcp/dhcpd.conf': $!\n";
   return undef
}
print $handle $dhcpdConf;
unless (close $handle) {
   print STDERR "Don't care error while closing '/etc/dhcp/dhcpd.conf': $!\n";
} 

# Patching /etc/default/isc-dhcp-server
unless (open $handle, "<:encoding(utf8)", "/etc/default/isc-dhcp-server") {
   print STDERR "Could not open file '/etc/default/isc-dhcp-server': $!\n";
   return undef
}
@lines = <$handle>;
unless (close $handle) {
   print STDERR "Don't care error while closing '/etc/default/isc-dhcp-server': $!\n";
}

#print @lines;
my $newLines = '';
foreach (@lines) {
    chomp($_);
    if ($_ eq 'INTERFACESv4=""') { #br0
	$newLines .= "INTERFACESv4=\"br0\"\n";
    } else {
    $newLines .= "$_\n";
    }
}

unless (open $handle, ">:encoding(utf8)", "/etc/default/isc-dhcp-server") {
   print STDERR "Could not open file '/etc/default/isc-dhcp-server': $!\n";
   return undef
}
print $handle $newLines;
unless (close $handle) {
   print STDERR "Don't care error while closing '/etc/default/isc-dhcp-server': $!\n";
} 

# Patching resolv.conf
`rm /etc/resolv.conf`;
`echo "options rotate" > /etc/resolv.conf`;
`echo "options timeout:1" > /etc/resolv.conf`;
`echo "nameserver 8.8.8.8" > /etc/resolv.conf`;
`echo "nameserver 1.1.1.1" > /etc/resolv.conf`;
`echo "nameserver 8.8.1.1" > /etc/resolv.conf`;

`service isc-dhcp-server restart`;
`systemctl restart systemd-resolved.service`;
