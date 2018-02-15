#!/bin/ash
set -e

NGINX_USER=${NGINX_USER:=""}
NGINX_GROUP=${NGINX_GROUP:=""}
FASTCGI_PORT=${FASTCGI_PORT:="1026"}

# Install dependencies
opkg update
opkg install nginx php7 php7-cli php7-cgi php7-fpm php7-fastcgi conntrack shadow-useradd

# Configure nginx
if ! grep -q $NGINX_USER /etc/passwd; then
  useradd -s /bin/false $NGINX_USER
fi

mkdir -p /html

cat > /etc/nginx/nginx.conf << EOF
user $NGINX_USER $NGINX_GROUP;
worker_processes  1;

events {
    worker_connections  1024;
}

http {
    include       mime.types;
    sendfile        on;
    keepalive_timeout  65;

    server {
        listen       8080;
        server_name  localhost;

        root /html;
        index  index.php index.html index.htm;

        error_page   500 502 503 504  /50x.html;
        location = /50x.html {
            root   html;
        }

        location ~ \.php$ {
            fastcgi_pass   127.0.0.1:$FASTCGI_PORT;
            fastcgi_index  index.php;
            fastcgi_param  SCRIPT_FILENAME  \$request_filename;
            include        fastcgi_params;
        }
    }
}
EOF

# Configure fastcgi
fpm_conf_file='/etc/php7-fpm.d/www.conf'

set_fpm_users() {
  if ! grep -q "^$2 = $NGINX_USER$"  $fpm_conf_file; then
    echo "Setting PHP FastCGI Process Manager $1 to $NGINX_USER."
    if grep -q "^$2 =.*$" $fpm_conf_file; then
      sed -i "s/^$2 =.*$/$1 = $NGINX_USER/" $fpm_conf_file
    elif grep -q "^;$2 =.*$" $fpm_conf_file; then
      sed -i "s/^;$2 =.*$/$1 = $NGINX_USER/" $fpm_conf_file
    fi
  else
    echo "PHP FastCGI Process Manager user was already set, skipping."
  fi
}

set_fpm_users 'user' 'user'
set_fpm_users 'group' 'group'
set_fpm_users 'listen.owner' 'listen\.owner'
set_fpm_users 'listen.group' 'listen\.group'
