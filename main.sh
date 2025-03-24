#!/bin/bash

# Updates installieren
echo "Updates werden installiert."
sudo apt update
sudo apt upgrade -y
sudo apt autoremove -y
echo

# Alle benötigten Pakete installieren
echo "Alle benötigten Pakete werden installiert."
apt install gnupg -y
echo

# Webmin installieren
echo "Webmin wird installiert."
echo "deb https://download.webmin.com/download/repository sarge contrib" >> /etc/apt/sources.list
wget -q https://download.webmin.com/jcameron-key.asc -O- | apt-key add -
apt update
apt install webmin
echo

# PHP mehr Arbeitsspeicher zuweisen
echo "PHP wird mehr Arbeitsspeicher zugewiesen."
sed -i "s|memory_limit = 128M|memory_limit = 1024M|" /etc/php/8.1/apache2/php.ini
