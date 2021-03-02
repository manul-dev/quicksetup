#!/bin/sh

#Personal Homeserver QuickInstall

#Installs and configures nginx, email server, matrix synapse server, element web UI, mattermost server, as well as certs

#Requirements: Fresh VPS, Debian 10

#TODO: Immediate: automate tar file verification, email server script, secure firewall, don't run as root. Future: Mattermost (once I figure out TLS), pleroma, parameters so you can choose which you want installed.

echo "This script installs and configures a personal NGINX web server running Matrix, Element, and Jitsi."

#--------------------User Input---------------------

#FQDN
echo "Enter your domain name (example.com):"
read -p "" FQDN

#Matrix Subdomain
echo "Enter the subdomain you'd like for your matrix server (for example, enter 'matrix' for matrix.example.com):"
read -p "" MATRIX_SUBD

#Element Subdomain
echo "Enter the subdomain you'd like for your element server (for example, enter 'element' for element.example.com):"
read -p "" ELEMENT_SUBD

#Jitsi Subdomain
echo "Enter the subdomain you'd like for your jitsi server (for example, enter 'jitsi' for jitsi.example.com):"
read -p "" JITSI_SUBD

echo $FQDN
echo $MATRIX_SUBD
echo $ELEMENT_SUBD
echo $JITSI_SUBD

#--------------------Nginx-----------------------
echo "CONFIGURING NGINX..."

#install nginx

apt-get update
apt-get install -y nginx

#configure site configs, make symlinks

cd /etc/nginx/sites-available/

echo "server {
	listen 80;
	listen [::]:80;

	server_name $FQDN;

	root /var/www/$FQDN;
	index index.html;

	location / {
		try_files \$uri \$uri/ =404;
	}

}" > $FQDN
ln -s /etc/nginx/sites-available/$FQDN /etc/nginx/sites-enabled/

echo "server {
	listen 80;
	listen [::]:80;

	server_name $MATRIX_SUBD.$FQDN;

	root /var/www/$FQDN;
	index index.html;

	location / {
		proxy_pass http://localhost:8008;
	}

}" > $MATRIX_SUBD.$FQDN
ln -s /etc/nginx/sites-available/$MATRIX_SUBD.$FQDN /etc/nginx/sites-enabled/

echo "server {
	listen 80;
	listen [::]:80;

	server_name $ELEMENT_SUBD.$FQDN;

	root /var/www/$ELEMENT_SUBD.$FQDN/element;
	index index.html;

	location / {
		try_files \$uri \$uri/ =404;
	}

}" > $ELEMENT_SUBD.$FQDN
ln -s /etc/nginx/sites-available/$ELEMENT_SUBD.$FQDN /etc/nginx/sites-enabled/


#--------------------LetsEncrypt--------------------

cd /root/

echo "OBTAINING HTTPS CERTIFICATES..."

#install certbot

apt install -y python3-certbot-nginx

#stop nginx before getting certs

systemctl stop nginx

#get certs

certbot --nginx -d $FQDN -d $MATRIX_SUBD.$FQDN -d $ELEMENT_SUBD.$FQDN

#start nginx again

systemctl start nginx

#--------------------Matrix Server--------------------

echo "INSTALLING MATRIX-SYNAPSE..."

#install matrix synapse
apt install -y lsb-release wget apt-transport-https
wget -O /usr/share/keyrings/matrix-org-archive-keyring.gpg https://packages.matrix.org/debian/matrix-org-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/matrix-org-archive-keyring.gpg] https://packages.matrix.org/debian/ $(lsb_release -cs) main" |
    tee /etc/apt/sources.list.d/matrix-org.list
apt update
apt install -y matrix-synapse-py3

#make .well-known directory

mkdir /var/www/$FQDN/
mkdir -p /var/www/$FQDN/.well-known/matrix/
echo "{ \"m.server\" : \"$MATRIX_SUBD.$FQDN:443\" }" > /var/www/$FQDN/.well-known/matrix/server

#--------------------Element Web UI--------------------

echo "INSTALLING ELEMENT..."

#install element

mkdir /var/www/$ELEMENT_SUBD.$FQDN/
cd /var/www/$ELEMENT_SUBD.$FQDN/
wget https://github.com/vector-im/element-web/releases/download/v1.7.22/element-v1.7.22.tar.gz
tar -zxvf element-v1.7.22.tar.gz
ln -s element-v1.7.22 element

#edit config files

cd element/
cp config.sample.json config.json
LINE_OLD='"base_url": "https://matrix-client.matrix.org"'
LINE_NEW="\"base_url\": \"https://$MATRIX_SUBD.$FQDN\""
sed -i "s%$LINE_OLD%$LINE_NEW%g" /var/www/$ELEMENT_SUBD.$FQDN/element/config.json
LINE_OLDER='"server_name": "matrix.org"'
LINE_NEWER="\"server_name\": \"$FQDN\""
sed -i "s%$LINE_OLDER%$LINE_NEWER%g" /var/www/$ELEMENT_SUBD.$FQDN/element/config.json
LINE_OLDEST='#enable_registration: false'
LINE_NEWEST='enable_registration: true'
sed -i "s%$LINE_OLDEST%$LINE_NEWEST%g" /etc/matrix-synapse/homeserver.yaml
systemctl restart matrix-synapse

#--------------------Jitsi--------------------

cd /root/
apt install -y curl
curl https://download.jitsi.org/jitsi-key.gpg.key | sh -c 'gpg --dearmor > /usr/share/keyrings/jitsi-keyring.gpg'
echo 'deb [signed-by=/usr/share/keyrings/jitsi-keyring.gpg] https://download.jitsi.org stable/' | tee /etc/apt/sources.list.d/jitsi-stable.list > /dev/null
apt update
apt install -y jitsi-meet

#edit config for jitsi integration to element

LINE1='"preferredDomain": "jitsi.matrix.org"'
LINE2="\"base_url\": \"$JITSI_SUBD.$FQDN\""
sed -i "s%$LINE1%$LINE2%g" /var/www/$ELEMENT_SUBD.$FQDN/element/config.json

#--------------------End Message--------------------

echo "Quick install complete! Go to "$ELEMENT_SUBD.$FQDN" to create an account for your personal matrix server!"

