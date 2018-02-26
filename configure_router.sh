#!/bin/ash
set -e

GAME_SERVER_NAME=${GAME_SERVER_NAME:=""}
GAME_SERVER_IP=${GAME_SERVER_IP:=""}
GAME_SERVER_MAC=${GAME_SERVER_MAC:=""}
LOCAL_NETWORK=${LOCAL_NETWORK:=""}
GAME_DOMAIN=${GAME_DOMAIN:=""}
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

# Check DHCP configuration
lease_set=false
game_domain=false

list_hosts() {
  local host=$1
  if [ "$(uci get dhcp.$host.mac)" = "$GAME_SERVER_MAC" ]; then
    if [ "$(uci get dhcp.$host.name)" = "$GAME_SERVER_NAME" ] \
    && [ "$(uci get dhcp.$host.ip)" = "$GAME_SERVER_IP" ]; then
      lease_set=true
    else
      echo "Found static lease for $GAME_SERVER_NAME with MAC: $(uci get dhcp.$host.mac) and IP: $(uci get dhcp.$host.ip)."
      echo "Setting static lease for $GAME_SERVER_NAME with MAC: $GAME_SERVER_MAC and IP: $GAME_SERVER_IP"
      uci set dhcp.$host.name=$GAME_SERVER_NAME
      uci set dhcp.$host.ip=$GAME_SERVER_IP
      uci commit dhcp
      lease_set=true
    fi;
  fi;
}

list_domains() {
  local domain=$1
  if [ "$(uci get dhcp.$domain.name)" = "$GAME_DOMAIN" ]; then
    if [ "$(uci get dhcp.$domain.ip)" = "$GAME_SERVER_IP" ]; then
      game_domain=true
    else
      echo "Found DNS entry for $GAME_DOMAIN on $(uci get dhcp.$domain.ip)."
      echo "Setting DNS entry for $GAME_DOMAIN on $GAME_SERVER_IP."
      uci set dhcp.$domain.name=$GAME_DOMAIN
      uci set dhcp.$domain.ip=$GAME_SERVER_IP
      uci commit dhcp
      game_domain=true
    fi;
  fi;
}

config_load dhcp
config_foreach list_hosts host
config_foreach list_domains domain

# Set static DHCP lease for game server
if [ $lease_set = false ]; then
  echo "Setting static lease for $GAME_SERVER_NAME to $GAME_SERVER_IP."
  uci add dhcp host
  uci set dhcp.@host[-1].name=$GAME_SERVER_NAME
  uci set dhcp.@host[-1].dns='1'
  uci set dhcp.@host[-1].mac=$GAME_SERVER_MAC
  uci set dhcp.@host[-1].ip=$GAME_SERVER_IP
  uci commit dhcp
else
  echo "Lease for $GAME_SERVER_NAME already set, skipping."
fi;

# Add game domain DNS entry
if [ $game_domain = false ]; then
  echo "Setting DNS entry for $GAME_DOMAIN on $GAME_SERVER_IP."
  uci add dhcp domain
  uci set dhcp.@domain[-1].name=$GAME_DOMAIN
  uci set dhcp.@domain[-1].ip=$GAME_SERVER_IP
  uci commit dhcp
else
  echo "DNS entry for $GAME_DOMAIN already set, skipping."
fi;

# Deny access to local network on WAN
deny_local=false

list_rules() {
  local rule=$1
  if [ "$(uci get firewall.$rule.name)" = "Deny-to-local" ]; then
    if [ "$(uci get firewall.$rule.dest_ip)" = "$LOCAL_NETWORK" ]; then
      deny_local=true
    else
      echo "Found Deny-to-local firewall rule for $(uci get firewall.$rule.dest_ip) network."
      echo "Setting firewall rule for denying access to $LOCAL_NETWORK local network."
      uci set firewall.$rule.name='Deny-to-local'
      uci set firewall.$rule.src='lan'
      uci set firewall.$rule.dest='wan'
      uci set firewall.$rule.proto='tcpudp'
      uci set firewall.$rule.dest_ip=$LOCAL_NETWORK
      uci set firewall.$rule.target='REJECT'
      uci commit firewall
      deny_local=true
    fi;
  fi;
}

config_load firewall
config_foreach list_rules rule

if [ $deny_local = false ]; then
  echo "Setting firewall rule for denying access to $LOCAL_NETWORK local network."
  uci add firewall rule
  uci set firewall.@rule[-1].name='Deny-to-local'
  uci set firewall.@rule[-1].src='lan'
  uci set firewall.@rule[-1].dest='wan'
  uci set firewall.@rule[-1].proto='tcpudp'
  uci set firewall.@rule[-1].dest_ip=$LOCAL_NETWORK
  uci set firewall.@rule[-1].target='REJECT'
  uci commit firewall
else
  echo "Firewall rule for denying access to local network already set, skipping."
fi;

# Deny ping to local network on WAN
deny_ping=false

list_ping_rules() {
  local rule=$1
  if [ "$(uci get firewall.$rule.name)" = "Deny-ping-to-local" ]; then
    if [ "$(uci get firewall.$rule.dest_ip)" = "$LOCAL_NETWORK" ]; then
      deny_ping=true
    else
      echo "Found Deny-ping-to-local firewall rule for $(uci get firewall.$rule.dest_ip) network."
      echo "Setting firewall rule for denying ping to $LOCAL_NETWORK local network."
      uci set firewall.$rule.name='Deny-ping-to-local'
      uci set firewall.$rule.src='lan'
      uci set firewall.$rule.dest='wan'
      uci set firewall.$rule.proto='icmp'
      uci set firewall.$rule.family='ipv4'
      uci set firewall.$rule.dest_ip=$LOCAL_NETWORK
      uci set firewall.$rule.target='REJECT'
      uci commit firewall
      deny_ping=true
    fi;
  fi;
}

config_load firewall
config_foreach list_ping_rules rule

if [ $deny_ping = false ]; then
  echo "Setting firewall rule for denying ping to $LOCAL_NETWORK local network."
  uci add firewall rule
  uci set firewall.@rule[-1].name='Deny-ping-to-local'
  uci set firewall.@rule[-1].src='lan'
  uci set firewall.@rule[-1].dest='wan'
  uci set firewall.@rule[-1].proto='icmp'
  uci set firewall.@rule[-1].family='ipv4'
  uci set firewall.@rule[-1].dest_ip=$LOCAL_NETWORK
  uci set firewall.@rule[-1].target='REJECT'
  uci commit firewall
else
  echo "Firewall rule for denying ping to local network already set, skipping."
fi;

# Configure wireless
echo "Configuring WIFI"
uci set wireless.default_radio0.ssid=$WIFI_SSID
uci set wireless.default_radio0.encryption='psk2'
uci set wireless.default_radio0.key=$WIFI_KEY
uci set wireless.radio0.disabled='0'
uci commit wireless

# Apply changes
/etc/init.d/firewall restart
/etc/init.d/dropbear restart
/etc/init.d/network restart
/etc/init.d/dnsmasq restart
