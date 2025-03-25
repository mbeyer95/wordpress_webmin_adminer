#!/bin/bash

# WP CLI Installation Installation
echo "WP CLI Installation"
curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
chmod +x wp-cli.phar
mv wp-cli.phar /usr/local/bin/wp

# URL in der Datenbank anpassen
echo "URL in der Datenbank anpassen"
read -p "Öffentliche Domain (example.com): " DOMAIN
cd /var/www/html/
sudo -u www-data -- wp option update home "https://$DOMAIN"
sudo -u www-data -- wp option update siteurl "https://$DOMAIN"
