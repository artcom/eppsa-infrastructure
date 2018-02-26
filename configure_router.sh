#!/bin/ash
set -e

GAME_SERVER_NAME=${GAME_SERVER_NAME:="***REMOVED***"}
GAME_SERVER_IP=${GAME_SERVER_IP:="***REMOVED***"}
GAME_SERVER_MAC=${GAME_SERVER_MAC:="***REMOVED***"}
LOCAL_NETWORK=${LOCAL_NETWORK:="***REMOVED***"}
GAME_DOMAIN=${GAME_DOMAIN:="***REMOVED***"}
GAME_DOMAIN_SHORT=${GAME_DOMAIN_SHORT:="***REMOVED***"}
WIFI_SSID=${WIFI_SSID:="***REMOVED***"}
WIFI_KEY=${WIFI_KEY:='***REMOVED***'}
SSH_PUBKEY=${SSH_PUBKEY:='***REMOVED***'}


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
config_load dhcp

# Set static DHCP lease for game server
lease_set=false

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

config_foreach list_hosts host

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
list_domains() {
  local domain=$1
  if [ "$(uci get dhcp.$domain.name)" = "$2" ]; then
    if [ "$(uci get dhcp.$domain.ip)" = "$GAME_SERVER_IP" ]; then
      game_domain=true
    else
      echo "Found DNS entry for $2 on $(uci get dhcp.$domain.ip)."
      echo "Setting DNS entry for $2 on $GAME_SERVER_IP."
      uci set dhcp.$domain.name=$2
      uci set dhcp.$domain.ip=$GAME_SERVER_IP
      uci commit dhcp
      game_domain=true
    fi;
  fi;
}

set_domain() {
  game_domain=false
  config_foreach list_domains domain $1
  if [ $game_domain = false ]; then
    echo "Setting DNS entry for $1 on $GAME_SERVER_IP."
    uci add dhcp domain
    uci set dhcp.@domain[-1].name=$1
    uci set dhcp.@domain[-1].ip=$GAME_SERVER_IP
    uci commit dhcp
  else
    echo "DNS entry for $1 already set, skipping."
  fi;
}

set_domain $GAME_DOMAIN
set_domain $GAME_DOMAIN_SHORT

# Deny access to local network on WAN
list_rules() {
  local rule=$1
  if [ "$(uci get firewall.$rule.name)" = "Deny-to-local" ]; then
    if [ "$(uci get firewall.$rule.dest_ip)" = "$LOCAL_NETWORK" ]; then
      firewall_rule_set=true
    else
      echo "Found $2 firewall rule for $(uci get firewall.$rule.dest_ip) network."
      echo "Setting firewall rule $2 for $LOCAL_NETWORK network."
      uci set firewall.$rule.name=$2
      uci set firewall.$rule.src='lan'
      uci set firewall.$rule.dest='wan'
      uci set firewall.$rule.proto=$3
      uci set firewall.$rule.family='ipv4'
      uci set firewall.$rule.dest_ip=$LOCAL_NETWORK
      uci set firewall.$rule.target='REJECT'
      uci commit firewall
      firewall_rule_set=true
    fi;
  fi;
}

set_rule() {
  firewall_rule_set=false
  config_foreach list_rules rule $1 $2
  if [ $firewall_rule_set = false ]; then
    echo "Setting firewall rule $1 for $LOCAL_NETWORK network."
    uci add firewall rule
    uci set firewall.@rule[-1].name=$1
    uci set firewall.@rule[-1].src='lan'
    uci set firewall.@rule[-1].dest='wan'
    uci set firewall.@rule[-1].proto=$2
    uci set firewall.@rule[-1].family='ipv4'
    uci set firewall.@rule[-1].dest_ip=$LOCAL_NETWORK
    uci set firewall.@rule[-1].target='REJECT'
    uci commit firewall
  else
    echo "Firewall rule $1 already set, skipping."
  fi;
}

config_load firewall
set_rule "Deny-to-local" "tcpudp"
set_rule "Deny-ping-to-local" "icmp"

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
