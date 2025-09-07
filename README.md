<h1>WordPress-Installation mit Webmin und Adminer in einem LXC-Container</h1>
<p>Diese Anleitung beschreibt die Installation von WordPress, Webmin und Adminer in einem LXC-Container unter Ubuntu 22.04. Während der Einrichtung wird nach einer öffentlichen Domain sowie Proxy-Einstellungen gefragt, da die WordPress-Instanz gemäß dieser Anleitung hinter einem Proxy betrieben wird.</p>

<h2>Vorbereitungen</h2>
<ol>
  <li>Erstellen Sie einen LXC-Container mit Ubuntu 22.04.</li>
</ol>

<h2>Installation</h2>
<ol start="2">
  <li>Führen Sie das Hauptskript im neu erstellten LXC-Container aus:
    <pre><code>sudo ./main.sh</code></pre>
  </li>
</ol>

<h2>Nachbereitung</h2>
<ol start="3">
  <li>Notieren und sichern Sie alle Informationen, die am Ende der Installation angezeigt werden.</li>
</ol>

<p>Diese optimierte Installationsmethode ermöglicht eine sichere und effiziente Einrichtung von WordPress mit zusätzlichen Verwaltungstools in einer containerisierten Umgebung.</p>
