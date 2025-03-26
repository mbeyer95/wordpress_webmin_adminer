#!/bin/bash

# Farbdefinitionen für Ausgaben
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

# Updates installieren
echo -e "${BLUE}Updates werden installiert${NC}"
apt update
apt upgrade -y
apt autoremove -y
echo

# Alle benötigten Pakete installieren
echo -e "${BLUE}Alle benötigten Pakete werden installiert${NC}"
apt install gnupg unzip apache2 mysql-server php libapache2-mod-php php-mysql php-curl php-gd php-mbstring php-xml php-xmlrpc php-soap php-intl php-zip curl -y
echo

# Webmin installieren
echo -e "${BLUE}Webmin wird installiert${NC}"
echo "deb https://download.webmin.com/download/repository sarge contrib" >> /etc/apt/sources.list
wget -q https://download.webmin.com/jcameron-key.asc -O- | apt-key add -
apt update
apt install webmin -y
echo

# PHP mehr Arbeitsspeicher zuweisen
echo -e "${BLUE}PHP wird mehr Arbeitsspeicher zugewiesen${NC}"
PHP_VERSION=$(php -v | head -n1 | cut -d' ' -f2 | cut -d'.' -f1-2)
sed -i "s|memory_limit = 128M|memory_limit = 512M|" /etc/php/${PHP_VERSION}/apache2/php.ini

# Datenbank erstellen
echo -e "${BLUE}Datenbank wird erstellt${NC}"
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
echo -e "${BLUE}Apache wird konfiguriert${NC}"
a2enmod rewrite proxy proxy_http headers remoteip
systemctl restart apache2
echo

# Wordpress herunterladen und installieren.
echo -e "${BLUE}Wordpress herunterladen und installieren${NC}"
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
echo -e "${BLUE}Wordpress wird konfiguriert${NC}"
read -p "Öffentliche Domain (example.com): " DOMAIN
read -p "E-Mail Adresse für den Admin: " EMAIL
read -p "IP/Subnetz des Reverse-Proxy (z.B. 10.0.0.1/24): " PROXY_IP
SERVER_IP=$(hostname -I | awk '{print $1}')

cp wp-config-sample.php wp-config.php
sed -i "s/database_name_here/${DATENBANKNAME}/" wp-config.php
sed -i "s/username_here/${DATENBANKUSER}/" wp-config.php
sed -i "s/password_here/${DATENBANKPW}/" wp-config.php

# Erweiterte WordPress-Einstellungen
cat >> wp-config.php << 'EOF'

/* Erweiterte WordPress-Einstellungen */
define('WP_MEMORY_LIMIT', '256M') ;
define('WP_HOME', "https://${DOMAIN}");
define('WP_SITEURL', "https://${DOMAIN}");
define('FORCE_SSL_ADMIN', true);

/* Proxy-Einstellungen */
if (isset($_SERVER['HTTP_X_FORWARDED_PROTO']) && $_SERVER['HTTP_X_FORWARDED_PROTO'] === 'https') {
    $_SERVER['HTTPS'] = 'on';
    $_SERVER['SERVER_PORT'] = 443;
}

/* Zusätzliche Proxy-Einstellungen */
if (isset($_SERVER['HTTP_X_FORWARDED_HOST'])) {
    $_SERVER['HTTP_HOST'] = $_SERVER['HTTP_X_FORWARDED_HOST'];
}

EOF

# WordPress Salts hinzufügen
wget -q -O - https://api.wordpress.org/secret-key/1.1/salt/ >> wp-config.php

# Apache Virtual Host einrichten
echo -e "${BLUE}Apache Virtual Host wird konfiguriert${NC}"
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

# WordPress Automatische Installation Script
# Dieses Script automatisiert die WordPress-Installation, die normalerweise im Browser erfolgt

# Funktion zum Anzeigen von Fehlermeldungen und Beenden des Scripts
function error_exit {
    echo -e "${RED}Fehler: $1${NC}" >&2
    exit 1
}

# Überprüfen, ob das Script mit Root-Rechten ausgeführt wird
if [ "$(id -u)" != "0" ]; then
   error_exit "Dieses Script muss mit Root-Rechten ausgeführt werden. Bitte mit sudo starten."
fi

# Pfad zur WordPress-Installation
WP_PATH="/var/www/html"

# Überprüfen, ob WordPress-Dateien existieren
if [ ! -f "$WP_PATH/wp-config.php" ]; then
    error_exit "WordPress-Dateien unter $WP_PATH nicht gefunden. Bitte stellen Sie sicher, dass WordPress heruntergeladen wurde."
fi

# Datenbankeinstellungen aus wp-config.php extrahieren
echo -e "${BLUE}Extrahiere Datenbankeinstellungen aus wp-config.php...${NC}"
DATENBANKNAME=$(grep DB_NAME $WP_PATH/wp-config.php | cut -d \' -f 4)
DATENBANKUSER=$(grep DB_USER $WP_PATH/wp-config.php | cut -d \' -f 4)
DATENBANKPW=$(grep DB_PASSWORD $WP_PATH/wp-config.php | cut -d \' -f 4)

if [ -z "$DATENBANKNAME" ] || [ -z "$DATENBANKUSER" ] || [ -z "$DATENBANKPW" ]; then
    error_exit "Konnte die Datenbankeinstellungen nicht aus wp-config.php extrahieren."
fi

echo -e "Datenbank: ${GREEN}$DATENBANKNAME${NC}"
echo -e "Benutzer: ${GREEN}$DATENBANKUSER${NC}"
echo

# Benutzer nach Website-Einstellungen fragen
echo -e "${BLUE}Bitte geben Sie die Einstellungen für Ihre WordPress-Website ein:${NC}"
read -p "Website-Titel: " SITE_TITLE
read -p "Admin-Benutzername: " ADMIN_USER
read -p "Admin-Passwort (leer lassen für zufälliges Passwort): " ADMIN_PASSWORD
read -p "Admin-E-Mail: " ADMIN_EMAIL
read -p "Domain (ohne http/https, z.B. example.com): " SITE_DOMAIN

# Protokoll abfragen
read -p "Möchten Sie http oder https verwenden? [https]: " PROTOCOL
PROTOCOL=${PROTOCOL:-https}

# Vollständige Site-URL erstellen
SITE_URL="${PROTOCOL}://${SITE_DOMAIN}"

# Zufälliges Passwort generieren, wenn keines angegeben wurde
if [ -z "$ADMIN_PASSWORD" ]; then
    ADMIN_PASSWORD=$(openssl rand -base64 12 | tr -dc 'a-zA-Z0-9!%^*_+-')
    echo -e "Generiertes Admin-Passwort: ${GREEN}$ADMIN_PASSWORD${NC}"
fi

# Bestätigung vom Benutzer einholen
echo
echo -e "${BLUE}WordPress wird mit folgenden Einstellungen installiert:${NC}"
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

# WP-CLI herunterladen, falls nicht vorhanden
if [ ! -f "/usr/local/bin/wp" ]; then
    echo -e "${BLUE}Installiere WP-CLI...${NC}"
    curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
    chmod +x wp-cli.phar
    mv wp-cli.phar /usr/local/bin/wp
fi

# Berechtigungen für WordPress-Verzeichnis setzen
echo -e "${BLUE}Setze Berechtigungen...${NC}"
chown -R www-data:www-data $WP_PATH
chmod -R 755 $WP_PATH

# WordPress mit WP-CLI installieren
echo -e "${BLUE}Installiere WordPress...${NC}"
cd $WP_PATH
wp core install --url="$SITE_URL" --title="$SITE_TITLE" --admin_user="$ADMIN_USER" --admin_password="$ADMIN_PASSWORD" --admin_email="$ADMIN_EMAIL" --skip-email --allow-root

if [ $? -ne 0 ]; then
    error_exit "Fehler bei der WordPress-Installation."
fi

# Aktualisiere die Site URL und Home URL in der wp-config.php
echo -e "${BLUE}Aktualisiere wp-config.php...${NC}"

# Überprüfen, ob WP_HOME und WP_SITEURL bereits in wp-config.php definiert sind
if grep -q "WP_HOME" $WP_PATH/wp-config.php && grep -q "WP_SITEURL" $WP_PATH/wp-config.php; then
    # Aktualisieren der bestehenden Definitionen
    sed -i "s|define('WP_HOME'.*|define('WP_HOME', '$SITE_URL');|" $WP_PATH/wp-config.php
    sed -i "s|define('WP_SITEURL'.*|define('WP_SITEURL', '$SITE_URL');|" $WP_PATH/wp-config.php
else
    # Hinzufügen der Definitionen, falls sie nicht existieren
    sed -i "/\/\* That's all, stop editing! Happy publishing. \*\//i \
define('WP_HOME', '$SITE_URL');\n\
define('WP_SITEURL', '$SITE_URL');\n\
" $WP_PATH/wp-config.php
fi

# Permalinks auf "Post name" setzen
echo -e "${BLUE}Konfiguriere Permalinks...${NC}"
wp option update permalink_structure "/%postname%/" --allow-root

# Installiere und aktiviere ein Standard-Theme (falls gewünscht)
read -p "Möchten Sie ein Standard-Theme installieren und aktivieren? (j/n): " INSTALL_THEME
if [[ "$INSTALL_THEME" =~ ^[jJ]$ ]]; then
    echo -e "${BLUE}Installiere und aktiviere Twenty Twenty-Four Theme...${NC}"
    wp theme install twentytwentyfour --activate --allow-root
fi

# Installiere und aktiviere wichtige Plugins (falls gewünscht)
read -p "Möchten Sie wichtige Plugins installieren? (j/n): " INSTALL_PLUGINS
if [[ "$INSTALL_PLUGINS" =~ ^[jJ]$ ]]; then
    echo -e "${BLUE}Installiere wichtige Plugins...${NC}"
    wp plugin install wordpress-seo --activate --allow-root
    wp plugin install wordfence --activate --allow-root
    wp plugin install wp-super-cache --activate --allow-root
    wp plugin install contact-form-7 --activate --allow-root
fi

# Apache neu starten
echo -e "${BLUE}Starte Apache neu...${NC}"
systemctl restart apache2

# Funktion zum Anzeigen von Fehlermeldungen und Beenden des Scripts
function error_exit {
    echo -e "${RED}Fehler: $1${NC}" >&2
    exit 1
}

# Datenbankeinstellungen
DATENBANKNAME=wordpress
DATENBANKUSER=wordpressuser

# Pfad zur WordPress-Installation
WP_PATH="/var/www/html"

# Überprüfen, ob das Script mit Root-Rechten ausgeführt wird
if [ "$(id -u)" != "0" ]; then
   error_exit "Dieses Script muss mit Root-Rechten ausgeführt werden. Bitte mit sudo starten."
fi

# Überprüfen, ob die WordPress-Installation existiert
if [ ! -f "$WP_PATH/wp-config.php" ]; then
    error_exit "WordPress-Installation unter $WP_PATH nicht gefunden."
fi

# Datenbankpasswort aus wp-config.php extrahieren
echo -e "${BLUE}Extrahiere Datenbankpasswort aus wp-config.php...${NC}"
DATENBANKPW=$(grep DB_PASSWORD $WP_PATH/wp-config.php | cut -d \' -f 4)

if [ -z "$DATENBANKPW" ]; then
    error_exit "Konnte das Datenbankpasswort nicht aus wp-config.php extrahieren."
fi

# Aktuelle Domain aus der Datenbank auslesen
echo -e "${BLUE}Lese aktuelle Domain-Einstellungen aus der Datenbank...${NC}"
CURRENT_SITEURL=$(mysql -u$DATENBANKUSER -p$DATENBANKPW $DATENBANKNAME -e "SELECT option_value FROM wp_options WHERE option_name='siteurl' LIMIT 1;" -s)
CURRENT_HOME=$(mysql -u$DATENBANKUSER -p$DATENBANKPW $DATENBANKNAME -e "SELECT option_value FROM wp_options WHERE option_name='home' LIMIT 1;" -s)

echo -e "Aktuelle Site URL: ${GREEN}$CURRENT_SITEURL${NC}"
echo -e "Aktuelle Home URL: ${GREEN}$CURRENT_HOME${NC}"
echo

# Benutzer nach neuer Domain fragen
read -p "Bitte geben Sie die neue Domain ein (ohne http/https, z.B. example.com): " NEW_DOMAIN

# Überprüfen, ob die Domain eingegeben wurde
if [ -z "$NEW_DOMAIN" ]; then
    error_exit "Keine Domain eingegeben. Vorgang abgebrochen."
fi

# Protokoll abfragen
read -p "Möchten Sie http oder https verwenden? [https]: " PROTOCOL
PROTOCOL=${PROTOCOL:-https}

# Vollständige neue URLs erstellen
NEW_SITEURL="${PROTOCOL}://${NEW_DOMAIN}"
NEW_HOME="${PROTOCOL}://${NEW_DOMAIN}"

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

# Datenbank aktualisieren
echo -e "${BLUE}Aktualisiere die Datenbank...${NC}"
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

# wp-config.php aktualisieren
echo -e "${BLUE}Aktualisiere wp-config.php...${NC}"

# Sichern der wp-config.php
cp $WP_PATH/wp-config.php $WP_PATH/wp-config.php.bak

# Überprüfen, ob WP_HOME und WP_SITEURL bereits in wp-config.php definiert sind
if grep -q "WP_HOME" $WP_PATH/wp-config.php && grep -q "WP_SITEURL" $WP_PATH/wp-config.php; then
    # Aktualisieren der bestehenden Definitionen
    sed -i "s|define('WP_HOME'.*|define('WP_HOME', '$NEW_HOME');|" $WP_PATH/wp-config.php
    sed -i "s|define('WP_SITEURL'.*|define('WP_SITEURL', '$NEW_SITEURL');|" $WP_PATH/wp-config.php
else
    # Hinzufügen der Definitionen, falls sie nicht existieren
    sed -i "/\/\* That's all, stop editing! Happy publishing. \*\//i \
define('WP_HOME', '$NEW_HOME');\n\
define('WP_SITEURL', '$NEW_SITEURL');\n\
" $WP_PATH/wp-config.php
fi

# Apache neu starten
echo -e "${BLUE}Starte Apache neu...${NC}"
systemctl restart apache2

echo -e "${GREEN}Domain wurde erfolgreich aktualisiert!${NC}"
echo -e "Neue Site URL: ${GREEN}$NEW_SITEURL${NC}"
echo -e "Neue Home URL: ${GREEN}$NEW_HOME${NC}"
echo -e "${BLUE}Eine Sicherungskopie der wp-config.php wurde unter wp-config.php.bak gespeichert.${NC}"
echo
echo -e "${BLUE}Hinweis: Möglicherweise müssen Sie den WordPress-Cache leeren und die Permalinks neu speichern.${NC}"
echo -e "${BLUE}Besuchen Sie dazu das WordPress-Admin-Dashboard unter $NEW_SITEURL/wp-admin${NC}"



# Infos anzeigen
echo -e "${GREEN}WordPress wurde erfolgreich installiert!${NC}"
echo -e "Website-URL: ${GREEN}$SITE_URL${NC}"
echo -e "Admin-URL: ${GREEN}$SITE_URL/wp-admin/${NC}"
echo -e "Interne IP: ${GREEN}$SITE_URL$(hostname -I | awk '{print $1}')${NC}"
echo -e "Admin-Benutzername: ${GREEN}$ADMIN_USER${NC}"
echo -e "Admin-Passwort: ${GREEN}$ADMIN_PASSWORD${NC}"
echo -e "MYSQL/MariaDB Root Passwort: ${GREEN}$MYSQL_ROOT_PW${NC}"
echo -e "Datenbank-Benutzer: ${GREEN}$DATENBANKUSER${NC}"
echo -e "Datenbank-Passwort: ${GREEN}$DATENBANKPW${NC}"
echo -e "Datenbank-Name: ${GREEN}$DATENBANKNAME${NC}"
echo
echo -e "${BLUE}Bitte notieren Sie sich diese Informationen für den späteren Zugriff.${NC}"

