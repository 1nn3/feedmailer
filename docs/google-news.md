# Google News als RSS- oder Atom-Feed

Google News lässt sich als RSS- oder Atom‑Feed nutzen, denn Google News unterstützt weiterhin RSS und Atom-Feeds – die URLs sind nur nicht verlinkt.

## Feed für ein Thema

Format: `https://news.google.com/rss/topics/<TOPIC-ID>`

Beispie für Google News - Welt – Aktuell:

```
https://news.google.com/rss/topics/CAAqJggKIiBDQkFTRWdvSUwyMHZNRGx1YlY4U0FtUmxHZ0pFUlNnQVAB
```

Bzw für den Atom-Feed:

```
https://news.google.com/atom/topics/CAAqJggKIiBDQkFTRWdvSUwyMHZNRGx1YlY4U0FtUmxHZ0pFUlNnQVAB
```

## Feed für eine Suche

Format:`https://news.google.com/atom/search?q=<SUCHBEGRIFF>`

Beispiel:

```
https://news.google.com/atom/search?q=Eilmeldung
```

### Nur deutschsprachige Ergebnisse

Google News nutzt Parameter wie `hl=de&gl=DE&ceid=DE:de`

Beispiel:

```
https://news.google.com/atom/search?q=Eilmeldung&hl=de&gl=DE&ceid=DE:de
```
