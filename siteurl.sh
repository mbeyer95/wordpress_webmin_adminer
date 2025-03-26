#!/bin/bash

# WP CLI Installation Installation
echo "WP CLI Installation"
curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
chmod +x wp-cli.phar
mv wp-cli.phar /usr/local/bin/wp
#!/bin/bash

# Script zum Aktualisieren der WordPress Domain in der Datenbank
# Dieses Script aktualisiert sowohl die Einträge in der Datenbank als auch in der wp-config.php

# Farbdefinitionen für Ausgaben
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

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


