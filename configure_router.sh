#!/bin/ash
set -e

GAME_SERVER_NAME=${GAME_SERVER_NAME:=""}
GAME_SERVER_IP=${GAME_SERVER_IP:=""}
GAME_SERVER_MAC=${GAME_SERVER_MAC:=""}
LOCAL_NETWORK=${LOCAL_NETWORK:=""}
GAME_DOMAIN=${GAME_DOMAIN:=""}
GAME_DOMAIN_SHORT=${GAME_DOMAIN_SHORT:=""}
WIFI_SSID=${WIFI_SSID:=""}
WIFI_KEY=${WIFI_KEY:=''}
SSH_PUBKEY=${SSH_PUBKEY:=''}
ROUTER_NETWORK=${ROUTER_NETWORK:=""}
ROUTER_IP=${ROUTER_IP:=""}

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
  local name=$2
  local dest_ip=$3
  local protocol=$4
  local policy=$5
  local src=$6
  local dest=$7
  local dest_port=$8
  if [ "$(uci get firewall.$rule.name)" = $name ]; then
    if [ "$(uci get firewall.$rule.dest_ip)" = "$dest_ip" ]; then
      firewall_rule_set=true
    else
      echo "Found $name firewall rule for $(uci get firewall.$rule.dest_ip)."
      echo "Setting firewall rule $name for $dest_ip."
      uci set firewall.$rule.name=$name
      uci set firewall.$rule.src=$src
      uci set firewall.$rule.dest=$dest
      uci set firewall.$rule.proto=$protocol
      uci set firewall.$rule.family='ipv4'
      uci set firewall.$rule.dest_ip=$dest_ip
      uci set firewall.$rule.target=$policy
      if [ $dest_port != "" ];then
        uci set firewall.$rule.dest_port=$dest_port
      fi;
      uci commit firewall
      firewall_rule_set=true
    fi;
  fi;
}

set_rule() {
  firewall_rule_set=false
  local name=$1
  local dest_ip=$2
  local protocol=$3
  local policy=$4
  local src=$5
  local dest=$6
  local dest_port=$7
  config_foreach list_rules rule $name $dest_ip $protocol $policy $src $dest $dest_port
  if [ $firewall_rule_set = false ]; then
    echo "Setting firewall rule $name for $dest_ip."
    uci add firewall rule
    uci set firewall.@rule[-1].name=$name
    uci set firewall.@rule[-1].src=$src
    uci set firewall.@rule[-1].dest=$dest
    uci set firewall.@rule[-1].proto=$protocol
    uci set firewall.@rule[-1].family='ipv4'
    uci set firewall.@rule[-1].dest_ip=$dest_ip
    uci set firewall.@rule[-1].target=$policy
    if [ $dest_port != "" ];then
      uci set firewall.@rule[-1].dest_port=$dest_port
    fi;
    uci commit firewall
  else
    echo "Firewall rule $name already set, skipping."
  fi;
}

config_load firewall
set_rule "Deny-to-gw-local" $LOCAL_NETWORK "tcpudp" "REJECT" "lan" "wan"
set_rule "Deny-ping-to-gw-local" $LOCAL_NETWORK "icmp" "REJECT" "lan" "wan"
set_rule "Allow-to-router" $ROUTER_IP "tcpudp" "ACCEPT" "lan" "lan"
set_rule "Allow-SSH-game-server" $GAME_SERVER_IP "tcp" "ACCEPT" "lan" "lan" "22"
set_rule "Allow-HTTP-game-server" $GAME_SERVER_IP "tcp" "ACCEPT" "lan" "lan" "80"
set_rule "Allow-HTTPS-game-server" $GAME_SERVER_IP "tcp" "ACCEPT" "lan" "lan" "443"
set_rule "Deny-to-local" $ROUTER_NETWORK "tcpudp" "REJECT" "lan" "lan"

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
