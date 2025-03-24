#!/bin/bash

# Updates installieren
echo "Updates werden installiert."
apt update
apt upgrade -y
apt autoremove -y
echo

# Alle benötigten Pakete installieren
echo "Alle benötigten Pakete werden installiert."
apt install gnupg unzip apache2 mysql-server php libapache2-mod-php php-mysql php-curl php-gd php-mbstring php-xml php-xmlrpc php-soap php-intl php-zip -y
echo

# Webmin installieren
echo "Webmin wird installiert."
echo "deb https://download.webmin.com/download/repository sarge contrib" >> /etc/apt/sources.list
wget -q https://download.webmin.com/jcameron-key.asc -O- | apt-key add -
apt update
apt install webmin -y
echo

# PHP mehr Arbeitsspeicher zuweisen
echo "PHP wird mehr Arbeitsspeicher zugewiesen."
sed -i "s|memory_limit = 128M|memory_limit = 512M|" /etc/php/8.1/apache2/php.ini

# Datenbank erstellen
echo "Datenbank wird erstellt."
mysql_root_pw=$(openssl rand -base64 16)
datenbankname=wordpress
datenbankuser=wordpressuser
datenbankpw=$(openssl rand -base64 16)
MYSQL_CMD="sudo mysql -u root -p${mysql_root_pw}"
SQL_CMD="CREATE DATABASE \`${datenbankname}\`; GRANT ALL PRIVILEGES ON \`${datenbankname}\`.* TO '${datenbankuser}'@'localhost' IDENTIFIED BY '${datenbankpw}'; FLUSH PRIVILEGES;"
echo $SQL_CMD | $MYSQL_CMD

# Apache neustarten
echo "Apache wird neugestartet."
a2enmod rewrite
systemctl restart apache2
echo

# Wordpress herunterladen und installieren.
echo "Wordpress herunterladen und installieren."
cd /var/www/html
wget https://wordpress.org/latest.tar.gz
tar -xzvf latest.tar.gz
chown -R www-data:www-data /var/www/html/wordpress
chmod -R 755 /var/www/html/wordpress
rm -rf latest.tar.gz
rm -rf index.html
echo

# Wordpress konfigurieren
echo "Wordpress konfigurieren."
cd /var/www/html/wordpress
cp wp-config-sample.php wp-config.php
wp config set DB_PASSWORD "$datenbankpw" --raw
wp config set DB_NAME "wordpress" --raw
wp config set DB_USER "wordpressuser" --raw
define('WP_MEMORY_LIMIT', '512M');

