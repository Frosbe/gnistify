# Gnistify

En WoW-addon til guilden **Gnisterne** på WoW Forever. Længe leve gnisten!

## Hvad kan den?

- **Ding:** når nogen i guilden stiger i level, lyder ding-lyden, og der står
  fx *"DING! Navn er dinget level X! Længe leve gnisten!"* i chatten og stort på
  skærmen. Teksten skifter, så det ikke bliver kedeligt. Den, der dinger, skriver det
  også i guild chat.
- **PvP-drab:** når en fra guilden får killing blow på en fjende, ser alle med addonen
  fx *"Navn (med Anna og Bo) gnistede Offer (lvl 34 Mage) til døde i Zone! (dagens drab
  nr. 3)"* i chatten, og der spilles en lyd. Teksten skifter fra gang til gang. "Med"
  er gruppemedlemmer tæt på, og tallet er, hvor mange drab personen har fået i dag.
  Selvom I er flere i gruppen, kommer beskeden kun én gang.
- **Leder i BG:** vælg én i gruppen som leder (shot caller), og tryk én tast for at
  tage lederens mål. Vælg lederen i det lille **Leder**-vindue (knappen *Vælg*). Vinduet
  dukker selv op i BG og dungeons, og ellers åbner du det fra `/gnist` (*Åbn
  leder-vindue*). Du kan også bruge `/gnist leder`, mens du har personen i target. Valget deles automatisk med alle
  i gruppen, der har addonen. Sæt tasten under *Indstillinger → Keybindings →
  Gnistify → "Mål lederens mål"*, eller tryk *Lav makro* i `/gnist` og træk makroen op på en
  action bar. Du kan også bare klikke på Leder-vinduet. Flyt vinduet ved at
  højreklikke og trække. Vinduet viser lederens mål og siger til, hvis du ikke har det samme, og
  der lyder et lille ping, når lederen skifter til en ny fjende. Lederen kan kun
  skiftes uden for kamp (et valg i kamp virker, så snart kampen er slut).
- **:gnist:** skriv `:gnist:` i chatten for at vise en lille gnist. Kun dem med addonen
  ser billedet.

## Installation

1. Hent den nyeste zip fra **Releases** eller CurseForge.
2. Pak den ud i `World of Warcraft/_forever_/Interface/AddOns/`, så mappen hedder
   `Gnistify`.
3. Genstart WoW.

## Kommandoer

| Kommando | Hvad den gør |
|---|---|
| `/gnist` | Åbner indstillinger, hvor du kan slå hver funktion til og fra |
| `/gnist hjælp` | Viser alle kommandoer |
| `/gnist leder` | Gør dit target til leder, eller åbner leder-vinduet |
| `/gnist leder Navn` / `mig` / `ingen` | Vælger en leder ved navn, dig selv, eller ingen |
| `/gnist makro` | Laver makroen "GnistMål", som tager lederens mål |

## Ny version (for udviklere)

Hver gang du pusher til `main`, laver GitHub automatisk en ny version (fx `v1.0.1`),
bygger zip-filen og lægger den op på GitHub Releases og CurseForge.

- Hvis du vil hoppe til et større versionsnummer, så lav selv et tag, fx `v1.1.0`, og
  push det.
- Ændringer, der kun rører README, CLAUDE.md, `art/` eller `.github/`, giver ikke en ny
  version.
- Skriv `[skip ci]` i commit-beskeden, hvis en push ikke skal blive til en version.
