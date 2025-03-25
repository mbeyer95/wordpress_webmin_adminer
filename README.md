WordPress Installation mit Webmin und Adminer

Getestet hinter einem Nginx Reverse Proxy
In einem LXC Container mit Ubuntu 22

    Das Script "main.sh" mit sudo ausführen. Es wird nun automatisch WordPress, Webmin und Adminer installiert. Wenn danach gefragrt wird die Externe URL, das Admin-Passwort und die IP des Reverse-Proxy eingeben. 
    Nach der erfolgreichen Installation die angezeigten Infos (URL, Interne IP, MYSQL/MariaDB Root Passwort, Datenbank Benutzer, Datenbank Passwort und Datenbank-Name) abspeichern.
    Die Webadresse im Browser eingeben und die WordPress Installation durchführen.
    Nach erfolgreicher Installation "siteurl.sh" mit sudo ausführen.
    Die Externe URL eingeben wenn danach gefragt wird.
