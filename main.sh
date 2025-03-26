#!/bin/bash

GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

WP_PATH="/var/www/html"

# Updates installieren
echo -e "${BLUE}System und Pakete-Updates werden installiert... ${NC}"
apt update
apt upgrade -y
apt autoremove -y
echo

# Pakete installieren
echo -e "${BLUE}Benötigte Pakete werden installiert... ${NC}"
apt install gnupg unzip apache2 mysql-server php libapache2-mod-php php-mysql php-curl php-gd php-mbstring php-xml php-xmlrpc php-soap php-intl php-zip curl -y
echo

# Webmin installieren    
echo -e "${BLUE}Webmin wird installiert... ${NC}"

    if ! grep -q "download.webmin.com" /etc/apt/sources.list; then
    echo "deb https://download.webmin.com/download/repository sarge contrib" >> /etc/apt/sources.list
    fi
echo "deb https://download.webmin.com/download/repository sarge contrib" >> /etc/apt/sources.list
wget -q https://download.webmin.com/jcameron-key.asc -O- | apt-key add -
apt update
apt install webmin -y
echo
    
# PHP mehr Arbeitsspeicher zuweisen
echo -e "${BLUE}PHP wird mehr Arbeitsspeicher zugewiesen... ${NC}"
PHP_VERSION=$(php -v | head -n1 | cut -d' ' -f2 | cut -d'.' -f1-2)
sed -i "s|memory_limit = 128M|memory_limit = 512M|" /etc/php/${PHP_VERSION}/apache2/php.ini
echo

# Fragen, ob eine neue Datenbank erstellt werden soll
echo -e "${BLUE}Eine neue Wordpress-Datenbank wird erstellt${NC}"
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
echo

# Apache konfigurieren
echo -e "${BLUE}Apache wird konfiguriert... ${NC}"
a2enmod rewrite proxy proxy_http headers remoteip
systemctl restart apache2
echo

# WordPress herunterladen und installieren
echo -e "${BLUE}WordPress herunterladen und installieren... ${NC}"
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

# WordPress konfigurieren
echo -e "${BLUE}WordPress konfigurieren... ${NC}"
read -p "Öffentliche Domain (example.com): " DOMAIN
read -p "Möchten Sie http oder https verwenden? [https]: " PROTOCOL
PROTOCOL=${PROTOCOL:-https}
read -p "E-Mail Adresse für den Admin: " EMAIL
read -p "IP/Subnetz des Reverse-Proxy (z.B. 192.168.178.2/24): " PROXY_IP

SERVER_IP=$(hostname -I | awk '{print $1}')

cp $WP_PATH/wp-config-sample.php $WP_PATH/wp-config.php
sed -i "s/database_name_here/${DATENBANKNAME}/" $WP_PATH/wp-config.php
sed -i "s/username_here/${DATENBANKUSER}/" $WP_PATH/wp-config.php
sed -i "s/password_here/${DATENBANKPW}/" $WP_PATH/wp-config.php
    
sed -i "/\/\* That's all, stop editing! Happy publishing. \*\//i \
/* Erweiterte WordPress-Einstellungen */\n\
define('WP_MEMORY_LIMIT', '256M');\n\
define('WP_HOME', '${PROTOCOL}://${DOMAIN}');\n\
define('WP_SITEURL', '${PROTOCOL}://${DOMAIN}');\n\
define('FORCE_SSL_ADMIN', true);\n\
\n\
/* Proxy-Einstellungen */\n\
if (isset(\$_SERVER['HTTP_X_FORWARDED_PROTO']) && \$_SERVER['HTTP_X_FORWARDED_PROTO'] === 'https') {\n\
    \$_SERVER['HTTPS'] = 'on';\n\
    \$_SERVER['SERVER_PORT'] = 443;\n\
}\n\
\n\
/* Zusätzliche Proxy-Einstellungen */\n\
if (isset(\$_SERVER['HTTP_X_FORWARDED_HOST'])) {\n\
    \$_SERVER['HTTP_HOST'] = \$_SERVER['HTTP_X_FORWARDED_HOST'];\n\
}\n\
" $WP_PATH/wp-config.php
    
# WordPress Salts hinzufügen
SALT_KEYS=$(wget -q -O - https://api.wordpress.org/secret-key/1.1/salt/)
sed -i "/define('AUTH_KEY'/d" $WP_PATH/wp-config.php
sed -i "/define('SECURE_AUTH_KEY'/d" $WP_PATH/wp-config.php
sed -i "/define('LOGGED_IN_KEY'/d" $WP_PATH/wp-config.php
sed -i "/define('NONCE_KEY'/d" $WP_PATH/wp-config.php
sed -i "/define('AUTH_SALT'/d" $WP_PATH/wp-config.php
sed -i "/define('SECURE_AUTH_SALT'/d" $WP_PATH/wp-config.php
sed -i "/define('LOGGED_IN_SALT'/d" $WP_PATH/wp-config.php
sed -i "/define('NONCE_SALT'/d" $WP_PATH/wp-config.php    
sed -i "/put your unique phrase here/i $SALT_KEYS" $WP_PATH/wp-config.php
echo

# Apache Virtual Host einrichten
echo -e "${BLUE}Apache Virtual Host einrichten... ${NC}"
cat > /etc/apache2/sites-available/wordpress.conf << EOF
<VirtualHost *:80>
    ServerAdmin ${EMAIL}
    DocumentRoot /var/www/html
    ServerName ${DOMAIN}
    ServerAlias ${DOMAIN} www.${DOMAIN}

    # Proxy-Einstellungen
    ProxyPreserveHost On
    RemoteIPHeader X-Forwarded-For
    RemoteIPInternalProxy ${PROXY_IP}

    # Header für HTTPS
    <IfModule mod_headers.c>
        RequestHeader set X-Forwarded-Proto "https" env=HTTPS
    </IfModule>

    <Directory /var/www/html>
        Options FollowSymLinks
        AllowOverride All
        Require all granted
        
        # Zusätzliche Rewrite-Regeln für Proxy
        <IfModule mod_rewrite.c>
            RewriteEngine On
            RewriteCond %{HTTP:X-Forwarded-Proto} =https
            RewriteRule .* - [E=HTTPS:on,E=HTTP_AUTHORIZATION:%{HTTP:Authorization}]
        </IfModule>
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
echo -e "${BLUE}Adminer wird installiert${NC}"
apt install adminer -y
a2enconf adminer
systemctl restart apache2
echo

# Berechtigungen für WordPress-Verzeichnis setzen
chown -R www-data:www-data $WP_PATH
chmod -R 755 $WP_PATH

# WordPress Installation
echo -e "${BLUE}Bitte geben Sie die Einstellungen für Ihre WordPress-Website ein:${NC}"
read -p "Website-Titel: " SITE_TITLE
read -p "Admin-Benutzername: " ADMIN_USER
read -p "Admin-Passwort (leer lassen für zufälliges Passwort): " ADMIN_PASSWORD
read -p "Admin-E-Mail: " ADMIN_EMAIL
    
SITE_URL="${PROTOCOL}://${DOMAIN}"
    
# Zufälliges Passwort generieren, wenn keines angegeben wurde
    if [ -z "$ADMIN_PASSWORD" ]; then
        ADMIN_PASSWORD=$(openssl rand -base64 12 | tr -dc 'a-zA-Z0-9!%^*_+-')
        echo -e "Generiertes Admin-Passwort: ${GREEN}$ADMIN_PASSWORD${NC}"
    fi
    
echo
echo -e "WordPress wird mit folgenden Einstellungen installiert:"
echo -e "Website-Titel: ${GREEN}$SITE_TITLE${NC}"
echo -e "Admin-Benutzername: ${GREEN}$ADMIN_USER${NC}"
echo -e "Admin-E-Mail: ${GREEN}$ADMIN_EMAIL${NC}"
echo -e "Website-URL: ${GREEN}$SITE_URL${NC}"
echo
    
read -p "Sind Sie sicher, dass Sie WordPress mit diesen Einstellungen installieren möchten? (j/n): " CONFIRM
    if [[ ! "$CONFIRM" =~ ^[jJ]$ ]]; then
        echo "Installation abgebrochen."
        exit 0
    fi

# Überprüfen, ob die Datenbank bereits WordPress-Tabellen enthält
    TABLES_COUNT=$(mysql -u$DATENBANKUSER -p$DATENBANKPW $DATENBANKNAME -e "SHOW TABLES;" | wc -l)
    if [ $TABLES_COUNT -gt 0 ]; then
        read -p "Die Datenbank enthält bereits Tabellen. Möchten Sie diese löschen und neu installieren? (j/n): " CONFIRM_DB
    if [[ ! "$CONFIRM_DB" =~ ^[jJ]$ ]]; then
            echo "Installation abgebrochen."
            exit 0
    fi
        
echo -e "${BLUE}Lösche bestehende Datenbank-Tabellen...${NC}"
        mysql -u$DATENBANKUSER -p$DATENBANKPW $DATENBANKNAME -e "DROP TABLE IF EXISTS \`wp_commentmeta\`, \`wp_comments\`, \`wp_links\`, \`wp_options\`, \`wp_postmeta\`, \`wp_posts\`, \`wp_term_relationships\`, \`wp_term_taxonomy\`, \`wp_termmeta\`, \`wp_terms\`, \`wp_usermeta\`, \`wp_users\`;"
    fi
echo

echo -e "${BLUE}Installiere WP-CLI...${NC}"
curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
chmod +x wp-cli.phar
mv wp-cli.phar /usr/local/bin/wp
echo

# WordPress mit WP-CLI installieren
echo -e "${BLUE}Installiere WordPress...${NC}"
cd $WP_PATH
wp core install --url="$SITE_URL" --title="$SITE_TITLE" --admin_user="$ADMIN_USER" --admin_password="$ADMIN_PASSWORD" --admin_email="$ADMIN_EMAIL" --skip-email --allow-root
    
    if [ $? -ne 0 ]; then
        error_exit "Fehler bei der WordPress-Installation."
    fi
    
# Permalinks auf "Post name" setzen
echo -e "${BLUE}Konfiguriere Permalinks...${NC}"
wp option update permalink_structure "/%postname%/" --allow-root
echo
    
# Standard Theme installieren
echo -e "${BLUE}Installiere und aktiviere Twenty Twenty-Four Theme...${NC}"
wp theme install twentytwentyfour --activate --allow-root
echo

# Wenn keine automatische Installation, dann Domain-Update anbieten
echo -e "${BLUE}Domain wird in der Datenbank angepasst...${NC}"
CURRENT_SITEURL=$(mysql -u$DATENBANKUSER -p$DATENBANKPW $DATENBANKNAME -e "SELECT option_value FROM wp_options WHERE option_name='siteurl' LIMIT 1;" -s)
CURRENT_HOME=$(mysql -u$DATENBANKUSER -p$DATENBANKPW $DATENBANKNAME -e "SELECT option_value FROM wp_options WHERE option_name='home' LIMIT 1;" -s)
echo
        
echo -e "Aktuelle Site URL: ${GREEN}$CURRENT_SITEURL${NC}"
echo -e "Aktuelle Home URL: ${GREEN}$CURRENT_HOME${NC}"
echo
              
NEW_SITEURL="${PROTOCOL}://${DOMAIN}"
NEW_HOME="${PROTOCOL}://${DOMAIN}"
        
echo
echo -e "${BLUE}Die Domain wird aktualisiert auf:${NC}"
echo -e "Neue Site URL: ${GREEN}$NEW_SITEURL${NC}"
echo -e "Neue Home URL: ${GREEN}$NEW_HOME${NC}"
echo
        
# Bestätigung vom Benutzer einholen
read -p "Sind Sie sicher, dass Sie die Domain aktualisieren möchten? (j/n): " CONFIRM
    if [[ ! "$CONFIRM" =~ ^[jJ]$ ]]; then
            echo "Vorgang abgebrochen."
            exit 0
    fi
echo
        
# Datenbank aktualisieren
echo -e "${BLUE}Aktualisiere die Datenbank... ${NC}"
mysql -u$DATENBANKUSER -p$DATENBANKPW $DATENBANKNAME <<EOF
UPDATE wp_options SET option_value='$NEW_SITEURL' WHERE option_name='siteurl';
UPDATE wp_options SET option_value='$NEW_HOME' WHERE option_name='home';
UPDATE wp_posts SET guid = REPLACE(guid, '$CURRENT_SITEURL', '$NEW_SITEURL');
UPDATE wp_posts SET post_content = REPLACE(post_content, '$CURRENT_SITEURL', '$NEW_SITEURL');
UPDATE wp_postmeta SET meta_value = REPLACE(meta_value, '$CURRENT_SITEURL', '$NEW_SITEURL') WHERE meta_value LIKE '%$CURRENT_SITEURL%';
EOF
        
    if [ $? -ne 0 ]; then
            error_exit "Fehler beim Aktualisieren der Datenbank."
    fi
echo
        
# wp-config.php aktualisieren
echo -e "${BLUE}Aktualisiere wp-config.php... ${NC}"
        
cp $WP_PATH/wp-config.php $WP_PATH/wp-config.php.bak
        
# Überprüfen, ob WP_HOME und WP_SITEURL bereits in wp-config.php definiert sind
    if grep -q "WP_HOME" $WP_PATH/wp-config.php && grep -q "WP_SITEURL" $WP_PATH/wp-config.php; then
        sed -i "s|define('WP_HOME'.*|define('WP_HOME', '$NEW_HOME');|" $WP_PATH/wp-config.php
        sed -i "s|define('WP_SITEURL'.*|define('WP_SITEURL', '$NEW_SITEURL');|" $WP_PATH/wp-config.php
    else
        sed -i "/\/\* That's all, stop editing! Happy publishing. \*\//i \
define('WP_HOME', '$NEW_HOME');\n\
define('WP_SITEURL', '$NEW_SITEURL');\n\
" $WP_PATH/wp-config.php
    fi
echo
        
echo -e "${BLUE}Domain wurde erfolgreich aktualisiert!${NC}"
echo -e "Neue Site URL: ${GREEN}$NEW_SITEURL${NC}"
echo -e "Neue Home URL: ${GREEN}$NEW_HOME${NC}"
echo

# Apache neu starten
echo -e "${BLUE}Starte Apache neu... ${NC}"
systemctl restart apache2
echo

# Infos anzeigen
echo -e "${BLUE}=== Installation abgeschlossen ===${NC}"
echo -e "WordPress URL: ${GREEN}$SITE_URL${NC}"
echo -e "WordPress Admin URL: ${GREEN}$NEW_SITEURL/wp-admin${NC}"
echo -e "WordPress Adminer URL: ${GREEN}$NEW_SITEURL/adminer${NC}"
echo -e "Interne IP-Adresse: ${GREEN}$(hostname -I | awk '{print $1}')${NC}"
echo -e "Webmin IP-Adresse: ${GREEN}$(hostname -I | awk '{print $1}'):10000${NC}"
echo -e "MYSQL/MariaDB Root Passwort: ${GREEN}$MYSQL_ROOT_PW${NC}"
echo -e "Datenbank-Benutzer: ${GREEN}$DATENBANKUSER${NC}"
echo -e "Datenbank-Passwort: ${GREEN}$DATENBANKPW${NC}"
echo -e "Datenbank-Name: ${GREEN}$DATENBANKNAME${NC}"
