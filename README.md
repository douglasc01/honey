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
| **quit** | say goodbye for now |

whatever you pick is remembered for next time.
