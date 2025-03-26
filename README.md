# WordPress Installation mit Webmin und Adminer

Hierbei handelt es sich um die Installation von WordPress mit Webmin und Adminer. Die Installation ist für einen LXC Container mit Ubuntu 22. Bei der Installation handelt es sich um eine WordPress Installation hinter einem Nginx Reverse Proxy.<br><br>
    1. Ausführen des Hauptskripts<br>
        Führen Sie main.sh mit sudo aus:<br>
        sudo ./main.sh<br>
        <br>
    2. Wichtige Informationen sichern<br>
        Nach der Installation die angezeigten Informationen sichern (Webadresse, Datenbank-User, Datenbank-Passwort, Datenbank-Name und Datenbank-Host)<br>
        <br>
    3. Die interne IP Adresse im Browser eingeben und die WordPress Installation durchführen
        <br><br>
    4. Zum Schluss das Script zum Anpassen der WordPress URL in der Datenbank ausführen<br>
        Führen Sie siteurl.sh mit sudo aus:<br>
        sudo ./siteurl.sh<br>
        <br>
