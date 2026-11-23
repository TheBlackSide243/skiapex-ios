# Ski Apex

**🇮🇹 Il diario delle tue giornate sugli sci, per iPhone.** · **🇬🇧 The diary of your days on skis, for iPhone.**

---

## Italiano

Premi **Inizia** ai piedi della pista, metti l'iPhone in tasca e scia. Ski Apex registra il GPS anche a schermo spento, misura la quota con il barometro e riconosce da sola **discese** e **risalite**: niente da toccare durante la giornata.

- Velocità massima e media, dislivello, chilometri sciati, quota massima, tempo in pista e in risalita.
- Mappa della giornata con ogni discesa nel suo colore e le risalite tratteggiate (mappa o satellite).
- Grafico della quota durante la giornata, e per ogni discesa velocità, pendenza, partenza e arrivo.
- Totali della stagione, esportazione GPX, unità metriche o imperiali, italiano e inglese.
- Se l'app viene chiusa a metà giornata, la registrazione si ritrova al prossimo avvio.
- Le giornate restano sull'iPhone (visibili anche nell'app File). Nessun account, nessun server.
- Niente neve? In Impostazioni si crea una giornata di prova.

<p>
  <img src="docs/screenshots/iphone-live.jpg" width="190" alt="Registrazione in corso: mappa, velocità e numeri della giornata">
  <img src="docs/screenshots/iphone-days.jpg" width="190" alt="Giornate e totali della stagione">
  <img src="docs/screenshots/iphone-day.jpg" width="190" alt="Una giornata: mappa e numeri">
  <img src="docs/screenshots/iphone-run.jpg" width="190" alt="Il dettaglio di una discesa">
</p>

### Installazione

- **TestFlight**: [link di invito](https://testflight.apple.com/join/Kszu8FAj).
- **Feather / AltStore / Sideloadly**: la `.ipa` non firmata delle [release](../../releases), oppure la sorgente Feather `https://raw.githubusercontent.com/TheBlackSide243/feather-repo/main/apps.json`.

Richiede iOS 17 o successivo. Velocità, distanze e quote sono stime del GPS e del barometro: non usarle per la sicurezza.

## English

Tap **Start** at the bottom of the slope, put your iPhone in your pocket and ski. Ski Apex records the GPS with the screen off, measures altitude with the barometer and recognizes **runs** and **lifts** on its own: nothing to touch during the day.

- Top and average speed, vertical, distance skied, top altitude, time on runs and on lifts.
- Map of the day with each run in its own color and dashed lifts (map or satellite).
- Altitude through the day, and for each run its speed, slope, start and finish.
- Season totals, GPX export, metric or imperial units, Italian and English.
- If the app is closed during the day, the recording comes back at the next launch.
- Your days stay on the iPhone (also visible in the Files app). No account, no server.
- No snow? Make a sample day in Settings.

### Install

- **TestFlight**: [invite link](https://testflight.apple.com/join/Kszu8FAj).
- **Feather / AltStore / Sideloadly**: the unsigned `.ipa` from the [releases](../../releases), or the Feather source `https://raw.githubusercontent.com/TheBlackSide243/feather-repo/main/apps.json`.

Requires iOS 17 or later. Speeds, distances and altitudes are estimates from GPS and the barometer: do not rely on them for safety.

---

### Build

SwiftUI, no dependencies. `xcodegen generate`, then open `SkiApex.xcodeproj`. The `.ipa` is built by GitHub Actions (`.github/workflows/ipa.yml`); the tests run with `unittests.yml`, the pictures above come from `screenshots.yml`.

© 2026 TheBlackSide243. All rights reserved: see [LICENSE](LICENSE).
