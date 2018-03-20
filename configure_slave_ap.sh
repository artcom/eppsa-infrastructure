#!/bin/ash
set -e

WIFI_SSID=${WIFI_SSID:=""}
WIFI_KEY=${WIFI_KEY:=''}
SSH_PUBKEY=${SSH_PUBKEY:=''}

# Import uci helper functions
. /lib/functions.sh

# Deny password authentication for SSH
echo "Configuring SSH"
if cat /etc/dropbear/authorized_keys | grep "$SSH_PUBKEY" >/dev/null; then
  echo "Your public key is already present in /etc/dropbear/authorized_keys, skipping."
else
  echo "Adding your public key to /etc/dropbear/authorized_keys"
  echo $SSH_PUBKEY >> /etc/dropbear/authorized_keys
fi;
uci set dropbear.@dropbear[0].PasswordAuth='off'
uci set dropbear.@dropbear[0].RootPasswordAuth='off'
uci commit dropbear

# Remove WAN and use WAN port as LAN port
uci set network.lan.ifname='eth0 eth1'
uci set network.lan.proto='dhcp'
uci delete network.lan.ipaddr
uci delete network.lan.netmask
uci delete network.lan.ip6assign
uci delete network.wan
uci delete network.wan6
uci set network.@switch_vlan[0].ports='0 1 2 3 4 5'
uci delete network.@switch_vlan[1]
uci commit network

# Disable DHCP server
uci set dhcp.lan.ignore=1
uci delete dhcp.lan.start
uci delete dhcp.lan.limit
uci delete dhcp.lan.leasetime
uci delete dhcp.lan.dhcpv6
uci delete dhcp.lan.ra
uci delete dhcp.wan
uci commit dhcp

# Configure wireless
echo "Configuring WIFI"
uci set wireless.default_radio0.ssid=$WIFI_SSID
uci set wireless.default_radio0.encryption='psk2'
uci set wireless.default_radio0.key=$WIFI_KEY
uci set wireless.radio0.disabled='0'
uci set wireless.default_radio1.ssid=$WIFI_SSID
uci set wireless.default_radio1.encryption='psk2'
uci set wireless.default_radio1.key=$WIFI_KEY
uci set wireless.radio1.disabled='0'
uci commit wireless

# Disable firewall
/etc/init.d/firewall disable
/etc/init.d/firewall stop

# Apply changes
/etc/init.d/dnsmasq restart
/etc/init.d/network restart
