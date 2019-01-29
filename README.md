Lagerkasse – Kassensoftware für Getränkeverkauf auf Zeltlagern/Freizeiten
=========================================================================

Auf Zeltlagern oder Freizeiten hat man oft einen *Getränkeverkauf* oder auch
einen Verkauf anderer Artikel. Auch lässt man oft die Teilnehmer am Anfang in
die *Kasse einzahlen* – oder gewährt ihnen Kredit bis zur Abrechnung gegen Ende
der Veranstaltung. Traditionell verwendet man eine Strichliste.

In unserem Zeltlager war es zum Beispiel so:

- Am Anfang zahlen die Kinder ihr mitgebrachtes Geld (z.B. 20 €) in die Kasse
  ein.
- Unter der Woche können sie sich beim täglichen Verkauf Getränke kaufen.
- Sie können Pfandflaschen zurückgeben, aber nur so viele Flaschen, wie sie
  selbst vorher gekauft haben.
- Wenn ihnen das eingezahlte Geld (ihr Budget) ausgeht, können sie in der Regel
  nichts mehr kaufen.
- Am Ende des Lagers wird ihnen der Restbetrag ausgezahlt (oder bei Nachzahlung
  eingezahlt). Nicht zurückgegebene Pfandflaschen werden berechnet.

Dieses Programm ist eine Kassensoftware, die diese Anwendungsfälle abdeckt, aber
genauso gut auch nur als Strichliste verwendet werden kann. Mein Hauptziel war,
die Bedienung so effizient wie möglich zu gestalten.

Benutzung
---------

Nach der Installation (s. u.) kann man das Programm folgendermaßen verwenden.

### Allgemein

Die Eingabe der Befehle startet die Menüführung des Kassenprogramms. Verlassen
kann man das Kassenprogramm, indem man bei Auswahllisten Escape drückt oder im
Menü einer Person die Taste `q`. Strg+C funktionieren auch immer.

Anzahlen für die Strichliste bei Verkauf eines Artikels oder der Pfandrückgabe
kann man auf zwei Weisen eingeben:

- Eine Zahl, z.B. `3` und Enter für 3 Flaschen.
- Punkte (oder Leerzeichen) statt der Anzahl, z.B. `..` und Enter für 2 Flaschen.

Abbrechen kann man an dieser Stelle, indem man nichts eingibt oder die Eingabe mit
der Rücktaste löscht und dann Enter drückt.

Vor dem Start des Programms muss die Kassen-Datei festgelegt werden:

```
export LEDGER_FILE=lagerkasse.journal
```

### Anwendungsfälle bzw. Vorgänge

Einzahlung zu Beginn der Freizeit:

```
./lagerkasse.sh -PV
```

`-P` und `-V` verhindern, dass nach der Auswahl einer Person automatisch
die Vorgänge für Pfandrückgabe und Verkauf gestartet werden.
Um eine Einzahlung zu tätigen, muss man nach Auswahl der Person die Taste `e`
gefolgt von Enter drücken.

Normaler Lagerverkauf:

```
./lagerkasse.sh
```

Dabei wird nach der Auswahl der Person zuerst die Pfandrückgabe gestartet und
anschließend der Verkauf. Abbrechen kann man immer mit der Escape Taste oder
einer leeren Eingabe.

Abrechnung am Ende der Freizeit:

```
./lagerkasse.sh -V
```

Hier drückt man nach Auswahl der Person die Taste `a` gefolgt von Enter.

Installation
------------

Man braucht einen Computer, es ist keine Smartphone App.
Unter Windows ist es leider nicht so einfach zu installieren, sollte aber mit
der Git Bash und einem installierten [hledger](http://hledger.org/)
auch funktionieren.

Einfach zu benutzen ist es unter Linux:

```
sudo apt-get install hledger
git clone https://github.com/schoettl/lagerkasse
cd lagerkasse
./lagerkasse.sh
```

Angepasst werden muss nur noch die Liste der Personen (Teilnehmer) und die
Verkaufsartikel. Dazu müssen die Dateien `personen.txt` und `artikel.txt`
bearbeitet werden.

Hintergrundinformationen
------------------------

Meine Rahmenbedingunen für diese Software waren:

- Effiziente Bedienung
- Soll die Anwendungsfälle abdecken: Kasse, Einzahlung und Abrechnung, Verkauf,
  Pfandsystem)
- Soll die gespeicherten Informationen ("Strichliste") einfach zugänglich
  machen, so dass die Datei auch per Mail verschickt und z.B. am Handy geöffnet
  werden kann. Stichwort Datensicherheit.

...
