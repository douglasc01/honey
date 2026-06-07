# honey & bagel

honey & bagel are little digital versions of two real-life companions — now living quietly on your mac. i made this as a tiny virtual surprise for my girlfriend, so the two of them could keep her company on her desktop.

they hang out up in the menu bar while you're busy, and a bigger version pops up on the desktop when things are calm. sometimes it's just honey, sometimes just bagel, and sometimes they're together — doing little everyday things like sipping coffee, reading, watering plants, or dozing off. every so often the cast changes with a soft *"someone's visiting!"* hello.

> a little heads up: this app isn't signed by apple, so your mac will ask before opening it the very first time. it's totally safe — there's a quick one-time step below to let it through.

## meet the cast

<p align="center">
  <img src="assets/honey-waving.gif" width="140" alt="honey waving">
  &nbsp;&nbsp;&nbsp;
  <img src="assets/bagel-waving.gif" width="140" alt="bagel waving">
</p>
<p align="center"><strong>honey</strong> &nbsp;·&nbsp; <strong>bagel</strong> — and when they hang out together:</p>
<p align="center">
  <img src="assets/both-dance.gif" width="250" alt="honey and bagel dancing together">
</p>

## what you'll need

- macos 13 (ventura) or newer
- any mac — apple silicon or intel

## getting them set up

1. download **`Honey-macOS.zip`** from the [releases](../../releases) page
2. unzip it and drag **`Honey.app`** into your **applications** folder

### the first time you open it

since the app isn't signed by apple, your mac will block it at first. to let it through, do one of these (you only have to do it once):

- right-click **`Honey.app`** → **open** → **open**, or
- open **system settings → privacy & security**, scroll down to the message saying honey was blocked, and click **open anyway**, then confirm

or, if you'd rather use the terminal:

```bash
xattr -dr com.apple.quarantine /Applications/Honey.app
```

honey & bagel don't show up in the dock — just look for the little animated sprite up in your **menu bar**, and click it for options.

## playing with them

click the sprite up in the menu bar:

| option | what it does |
|--------|--------------|
| **cast** | let them rotate on their own, or pin it to just honey, just bagel, or the two of them together |
| **in the rotation** | choose who shows up while it's rotating — honey, bagel, or together (at least one always stays) |
| **scene** | jump to a specific little activity for whoever's on screen |
| **show on desktop** | turn the bigger desktop version on or off |
| **size** | small, medium, or large |
| **pin to corner** | tuck them into any corner — or just drag them wherever you like |
| **layer** | keep them behind your windows (calm and out of the way) or always on top |
| **break game** | settings for the little hover-to-play games (more below) |
| **quit** | say goodbye for now |

whatever you pick is remembered for next time.

## taking a break

rest your cursor on the desktop sprite for a few seconds and they'll perk up while a little bar fills underneath. when it fills, a small framed play area opens up around them and a quick game begins — a gentle nudge to step away from work for a moment.

there are three games, and whoever's on screen stars in it (shrunk down a touch to leave room to move):

- **snack catch** — slide left and right to catch falling treats before they hit the floor. three misses and it's over.
- **quick tap** — click the treats as they fall; chain them together for a combo bonus.
- **reaction** — wait for the signal, then click as fast as you can. clicking too early sets you back.

a short note tells you what to do when each round starts, and your best score in each game is remembered. move your cursor away mid-game and it politely pauses — come back and it counts down **3 · 2 · 1** before picking up where you left off. there's always a small **✕** in the corner to stop and send them back to their spot.

under **break game** in the menu you can:

| option | what it does |
|--------|--------------|
| **hover to play** | turn the whole thing on or off |
| **game** | let the games rotate at random, or pick just one |
| **games in rotation** | choose which games show up at random (at least one always stays) |
| **hover delay** | how long to rest your cursor before a game starts — 3, 5, or 8 seconds |
