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
PHP_VERSION=$(php -v | head -n1 | cut -d' ' -f2 | cut -d'.' -f1-2)
sed -i "s|memory_limit = 128M|memory_limit = 512M|" /etc/php/${PHP_VERSION}/apache2/php.ini

# Datenbank erstellen
echo "Datenbank wird erstellt"
MYSQL_ROOT_PW=$(openssl rand -base64 16 | tr -dc 'a-zA-Z0-9!%^*_+-')
DATENBANKNAME=wordpress
DATENBANKUSER=wordpressuser
DATENBANKPW=$(openssl rand -base64 16 | tr -dc 'a-zA-Z0-9!%^*_+-')

mysql --force <<EOF
ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '${MYSQL_ROOT_PW}';
FLUSH PRIVILEGES;
CREATE DATABASE \`${DATENBANKNAME}\`;
CREATE USER '${DATENBANKUSER}'@'localhost' IDENTIFIED BY '${DATENBANKPW}';
GRANT ALL PRIVILEGES ON \`${DATENBANKNAME}\`.* TO '${DATENBANKUSER}'@'localhost';
FLUSH PRIVILEGES;
EOF

# Apache neustarten und Proxy Unterstützung aktivieren
echo "Apache wird konfiguriert"
a2enmod rewrite proxy proxy_http headers remoteip
systemctl restart apache2
echo

# Wordpress herunterladen und installieren.
echo "Wordpress herunterladen und installieren"
cd /var/www/html
rm -rf *
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
read -p "Öffentliche Domain (example.com): " DOMAIN
read -p "E-Mail Adresse für den Admin: " EMAIL
read -p "IP/Subnetz des Reverse-Proxy (z.B. 10.0.0.1/24): " PROXY_IP

cp wp-config-sample.php wp-config.php
sed -i "s/database_name_here/${DATENBANKNAME}/" wp-config.php
sed -i "s/username_here/${DATENBANKUSER}/" wp-config.php
sed -i "s/password_here/${DATENBANKPW}/" wp-config.php

# Erweiterte WordPress-Einstellungen
cat >> wp-config.php << 'EOF'

/* Erweiterte WordPress-Einstellungen */
define('WP_MEMORY_LIMIT', '256M');
define('WP_HOME', 'https://' . $_SERVER['HTTP_HOST']);
define('WP_SITEURL', 'https://' . $_SERVER['HTTP_HOST']);
define('FORCE_SSL_ADMIN', true);

/* Proxy-Einstellungen */
if (isset($_SERVER['HTTP_X_FORWARDED_PROTO']) && $_SERVER['HTTP_X_FORWARDED_PROTO'] === 'https') {
    $_SERVER['HTTPS'] = 'on';
    $_SERVER['SERVER_PORT'] = 443;
}

/* Debugging (nur für Entwicklung) */
define('WP_DEBUG', false);
define('WP_DEBUG_LOG', false);
define('WP_DEBUG_DISPLAY', false);
EOF

# WordPress Salts hinzufügen
wget -q -O - https://api.wordpress.org/secret-key/1.1/salt/ >> wp-config.php

# Apache Virtual Host einrichten
echo "Apache Virtual Host wird konfiguriert"
cat > /etc/apache2/sites-available/wordpress.conf << EOF
<VirtualHost *:80>
    ServerAdmin ${EMAIL}
    DocumentRoot /var/www/html
    ServerName ${DOMAIN}
    ServerAlias www.${DOMAIN}

    # Proxy-Einstellungen
    ProxyPreserveHost On
    RemoteIPHeader X-Forwarded-For
    RemoteIPInternalProxy ${PROXY_IP}

    # Header für HTTPS
    RequestHeader set X-Forwarded-Proto "https"
    RequestHeader set X-Forwarded-Port "443"

    <Directory /var/www/html>
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
systemctl restart apache2
echo

# Infos anzeigen
echo -e "\e[32m=== Installation abgeschlossen ===\e[0m"
echo -e "\n\e[36mWordPress Zugangsdaten:\e[0m"
echo -e "URL: \e[35mhttps://${DOMAIN}\e[0m"
echo -e "Interne IP: \e[35m$(hostname -I | awk '{print $1}')\e[0m"
echo -e "MYSQL/MariaDB Root Passwort: \e[35m$MYSQL_ROOT_PW\e[0m"
echo -e "Datenbank-Benutzer: \e[35m$DATENBANKUSER\e[0m"
echo -e "Datenbank-Passwort: \e[35m$DATENBANKPW\e[0m"
echo -e "Datenbank-Name: \e[35m$DATENBANKNAME\e[0m"
echo -e "\n\e[33mTestbefehl für Proxy-Kommunikation:\e[0m"
echo -e "curl -I http://localhost -H 'Host: ${DOMAIN}' -H 'X-Forwarded-Proto: https'"
