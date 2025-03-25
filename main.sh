#!/bin/bash

# Updates installieren
echo "Updates werden installiert"
apt update
apt upgrade -y
apt autoremove -y
echo

# Alle benötigten Pakete installieren
echo "Alle benötigten Pakete werden installiert"
apt install gnupg unzip apache2 mysql-server php libapache2-mod-php php-mysql php-curl php-gd php-mbstring php-xml php-xmlrpc php-soap php-intl php-zip -y
echo

# Webmin installieren
echo "Webmin wird installiert"
echo "deb https://download.webmin.com/download/repository sarge contrib" >> /etc/apt/sources.list
wget -q https://download.webmin.com/jcameron-key.asc -O- | apt-key add -
apt update
apt install webmin -y
echo

# PHP mehr Arbeitsspeicher zuweisen
echo "PHP wird mehr Arbeitsspeicher zugewiesen"
sed -i "s|memory_limit = 128M|memory_limit = 512M|" /etc/php/8.1/apache2/php.ini

# Datenbank erstellen
echo "Datenbank wird erstellt"
MYSQL_ROOT_PW=$(openssl rand -base64 16)
DATENBANKNAME=wordpress
DATENBANKUSER=wordpressuser
DATENBANKPW=$(openssl rand -base64 16)
# MySQL sicher einrichten und Root-Passwort setzen
sudo mysql <<EOF
ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '${MYSQL_ROOT_PW}';
FLUSH PRIVILEGES;
CREATE DATABASE \`${DATENBANKNAME}\`;
CREATE USER '${DATENBANKUSER}'@'localhost' IDENTIFIED BY '${DATENBANKPW}';
GRANT ALL PRIVILEGES ON \`${DATENBANKNAME}\`.* TO '${DATENBANKUSER}'@'localhost';
FLUSH PRIVILEGES;
EOF

# Apache neustarten
echo "Apache wird neugestartet."
a2enmod rewrite
systemctl restart apache2
echo

# Wordpress herunterladen und installieren.
echo "Wordpress herunterladen und installieren"
cd /var/www/html
wget https://wordpress.org/latest.tar.gz
tar -xzvf latest.tar.gz
mv /var/www/html/wordpress/* /var/www/html
chown -R www-data:www-data /var/www/html
chmod -R 755 /var/www/html
rm -rf latest.tar.gz
rm -rf index.html
rmdir wordpress
echo

# Wordpress konfigurieren
echo "Wordpress konfigurieren"
read -p "Bitte geben Sie Ihre öffentliche Domain ein (example.com): " DOMAIN
read -p "Bitte geben Sie Ihre E-Mail ein (example@mail.com): " EMAIL
cd /var/www/html
cp wp-config-sample.php wp-config.php
sed -i "s/define( *'DB_NAME', *'[^']*' *);/define('DB_NAME', 'wordpress');/" wp-config.php
sed -i "s/define( *'DB_USER', *'[^']*' *);/define('DB_USER', 'wordpressuser');/" wp-config.php
sed -i "s/define( *'DB_PASSWORD', *'[^']*' *);/define('DB_PASSWORD', '$DATENBANKPW');/" wp-config.php
echo

# Apache Virtual Host für WordPress einrichten
echo "Apache Virtual Host für WordPress einrichten"
DOCUMENT_ROOT="/var/www/html"
CONF_FILE="/etc/apache2/sites-available/wordpress.conf"
cat > $CONF_FILE << EOF
<VirtualHost *:80>
    ServerAdmin $EMAIL
    DocumentRoot $DOCUMENT_ROOT
    ServerName $DOMAIN
    ServerAlias www.$DOMAIN

    <Directory $DOCUMENT_ROOT>
        Options FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog \${APACHE_LOG_DIR}/error.log
    CustomLog \${APACHE_LOG_DIR}/access.log combined
</VirtualHost>
EOF
a2ensite wordpress.conf
a2dissite 000-default.conf
apache2ctl configtest
systemctl restart apache2
echo

# Adminer installieren
echo "Adminer installieren"
apt install adminer -y
a2enconf adminer
a2enconf php*-fpm
systemctl restart apache2
echo

# Infos anzeigen
echo -e "Domain: www.$DOMAIN"
echo -e "MYSQL/MariaDB Root Passwort: \e[35m$MYSQL_ROOT_PW\e[0m"
echo -e "Datenbank-Benutzer: \e[35m$DATENBANKUSER\e[0m"
echo -e "Datenbank-Passwort: \e[35m$DATENBANKPW\e[0m"
echo -e "Datenbank-Name: \e[35m$DATENBANKNAME\e[0m"
