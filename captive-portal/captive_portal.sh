#!/bin/ash
set -e

NGINX_USER=${NGINX_USER:=""}
NGINX_GROUP=${NGINX_GROUP:=""}
HTML_ROOT=${HTML_ROOT:="/html"}
FASTCGI_PORT=${FASTCGI_PORT:="1026"}
GAME_DOMAIN=${GAME_DOMAIN:=""}
ROUTER_IP=${ROUTER_IP:="192.168.1.1"}
LISTEN_PORT=${LISTEN_PORT:="8080"}
SITE_NAME=${SITE_NAME:=""}
USERS_FILE=${USERS_FILE:="/var/lib/users"}
DIR=$(dirname "$0")

# Install dependencies
opkg update
opkg install nginx php7 php7-cli php7-cgi php7-fpm php7-fastcgi conntrack shadow-useradd

# Configure nginx
echo "Configuring nginx user as $NGINX_USER and group as $NGINX_GROUP"

if ! grep -q $NGINX_USER /etc/passwd; then
  useradd -s /bin/false $NGINX_USER
fi

mkdir -p $HTML_ROOT
touch $USERS_FILE

echo "Configuring /etc/nginx/nginx.conf"

mv $DIR/nginx.conf /etc/nginx/nginx.conf

if ! grep -q "^\s*user\s\+$NGINX_USER;" /etc/nginx/nginx.conf; then
  sed -i "s/^user\s\+\w\+;$/user              $NGINX_USER;/" /etc/nginx/nginx.conf
fi

if ! grep -q "^\s*listen\s\+$LISTEN_PORT;" /etc/nginx/nginx.conf; then
  sed -i "s/^\s*listen\s\+\d\{1,5\};$/        listen       $LISTEN_PORT;/" /etc/nginx/nginx.conf
fi

if ! grep -q "^\s*root\s\+$HTML_ROOT;" /etc/nginx/nginx.conf; then
  sed -i "s/^\s*root\s\+.*;$/        root   $(echo $HTML_ROOT | sed -e 's/[\/]/\\&/g');/" /etc/nginx/nginx.conf
fi

if ! grep -q "fastcgi_pass\s\+127\.0\.0\.1:$FASTCGI_PORT;" /etc/nginx/nginx.conf; then
  sed -i "s/^\s*fastcgi_pass\s\+\d\{1,3\}\.\d\{1,3\}\.\d\{1,3\}\.\d\{1,3\}:\d\{1,5\};$/            fastcgi_pass   127.0.0.1:$FASTCGI_PORT;/" /etc/nginx/nginx.conf
fi

# Configure fastcgi
fpm_conf_file='/etc/php7-fpm.d/www.conf'
fastcgi_init_file='/etc/init.d/php7-fastcgi'

echo "Configuring $fpm_conf_file"

set_fpm_users() {
  if ! grep -q "^$(echo $1 | sed -e 's/[.]/\\&/g') = $2$"  $fpm_conf_file; then
    if grep -q "^$(echo $1 | sed -e 's/[.]/\\&/g') =.*$" $fpm_conf_file; then
      sed -i "s/^$(echo $1 | sed -e 's/[.]/\\&/g') =.*$/$1 = $2/" $fpm_conf_file
    elif grep -q "^;$(echo $1 | sed -e 's/[.]/\\&/g') =.*$" $fpm_conf_file; then
      sed -i "s/^;$(echo $1 | sed -e 's/[.]/\\&/g') =.*$/$1 = $2/" $fpm_conf_file
    fi
  fi
}

set_fpm_users 'user' $NGINX_USER
set_fpm_users 'group' $NGINX_GROUP
set_fpm_users 'listen.owner' $NGINX_USER
set_fpm_users 'listen.group' $NGINX_GROUP

echo "Configuring $fastcgi_init_file"

if ! grep -q "config_get port \"\$section\" 'port' $FASTCGI_PORT" $fastcgi_init_file; then
  sed -i "s/config_get port \"\$section\" 'port' \d*$/config_get port \"\$section\" 'port' $FASTCGI_PORT/" $fastcgi_init_file
fi

# Configure PHP
echo "Configuring /etc/php.ini"

if ! grep -q "^doc_root = \"$HTML_ROOT\"$" /etc/php.ini; then
  sed -i "s/^doc_root = .*$/doc_root = \"$(echo $HTML_ROOT | sed -e 's/[\/]/\\&/g')\"/" /etc/php.ini
fi

echo "Configuring $HTML_ROOT/index.php"

mv $DIR/index.php $HTML_ROOT/

configure_site() {
  if ! grep -q "^\$$1 = \"$2\";" $HTML_ROOT/index.php; then
    sed -i "s/^\$$1 = \".*\";$/\$$1 = \"$(echo $2 | sed -e 's/[.\/]/\\&/g')\";/" $HTML_ROOT/index.php
  fi
}

configure_site "game_site" "$GAME_DOMAIN"
configure_site "site_name" "$SITE_NAME"
configure_site "users" "$USERS_FILE"
chown -R $NGINX_USER:$NGINX_GROUP /html

# Configure firewall rules
echo "Configuring /etc/firewall.user"

mv $DIR/firewall.user /etc/firewall.user

if ! grep -q "^awk 'BEGIN { FS="\\t"; } { system(\"iptables -t mangle -A internet -m mac --mac-source \"\$3\" -j RETURN\"); }' $(echo $USERS_FILE | sed -e 's/[\/]/\\&/g')$" /etc/firewall.user; then
  sed -i "s/^awk 'BEGIN { FS="\\t"; } { system(\"iptables -t mangle -A internet -m mac --mac-source \"\$3\" -j RETURN\"); }'.*$/^awk 'BEGIN { FS="\\t"; } { system(\"iptables -t mangle -A internet -m mac --mac-source \"\$3\" -j RETURN\"); }' $(echo $USERS_FILE | sed -e 's/[\/]/\\&/g')$/" /etc/firewall.user
fi

if ! grep -q "^iptables -t nat -A PREROUTING -m mark --mark 99 -p tcp --dport 80 -j DNAT --to-destination $(echo $GAME_SERVER_IP | sed -e 's/[\/]/\\&/g'):$LISTEN_PORT$" /etc/firewall.user; then
  sed -i "s/^iptables -t nat -A PREROUTING -m mark --mark 99 -p tcp --dport 80 -j DNAT --to-destination .*$/iptables -t nat -A PREROUTING -m mark --mark 99 -p tcp --dport 80 -j DNAT --to-destination $(echo $ROUTER_IP | sed -e 's/[\/]/\\&/g'):$LISTEN_PORT/" /etc/firewall.user
fi

# Configure track removal
echo "Configuring /usr/bin/rmtrack"

mv $DIR/rmtrack /usr/bin/
chmod 755 /usr/bin/rmtrack

# Start captive portal
echo "Starting captive portal"

/etc/init.d/firewall restart
/etc/init.d/dnsmasq restart
/etc/init.d/php7-fastcgi stop
/etc/init.d/php7-fastcgi start
/etc/init.d/nginx restart
