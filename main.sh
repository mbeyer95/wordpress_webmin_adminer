#!/bin/bash

# Updates installieren
echo "Updates werden installiert."
sudo apt update
sudo apt upgrade -y
sudo apt autoremove -y
echo

# Alle benötigten Pakete installieren
echo "Alle benötigten Pakete werden installiert."
apt install apache2 php php-gd sqlite php-sqlite3 php-curl php-zip php-xml php-mbstring php-imagick php7.4-intl libapache2-mod-php mariadb-server php-mysql libnet-ssleay-perl libauthen-pam-perl libio-pty-perl apt-show-versions net-tools unzip -y
echo

# Webmin installieren
echo "Webmin wird installiert."
wget https://sourceforge.net/projects/webadmin/files/webmin/2.303/newkey-webmin_2.303_all.deb
dpkg -i webmin_2.013_all.deb
echo

# PHP mehr Arbeitsspeicher zuweisen
echo "PHP wird mehr Arbeitsspeicher zugewiesen."
sed -i "s|memory_limit = 128M|memory_limit = 1024M|" /etc/php/8.1/apache2/php.ini
