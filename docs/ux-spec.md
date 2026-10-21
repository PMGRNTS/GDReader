# GDReader — UX Spec

A read-only spatial viewer for GDScript projects. Built in Godot 4.7 (GL Compatibility),
it opens *another* project's `res://` and lays its scripts out on an infinite canvas for
high-level reading and hand-drawn annotation.

Status: **UX complete.** Decided items are marked ✅. Values marked 🎚 are tunable — they
need feel-testing, not debate. The two remaining items in
[Open Questions](#open-questions) resolve at the keyboard, not in discussion.

---

## 1. Core metaphor

A notebook, not an editor. Nothing here writes to the target project's source. The only
thing the user authors is **twine**: red string drawn between methods, with a typed
description of why they're related.

Navigation is modeled on [Niri](https://github.com/YaLTeR/niri): an infinite scrollable
strip where **focus is a single cell and the camera is derived from it.** The user never
scrolls the camera directly — they move focus, and the camera follows. ✅

**One project open at a time.** ✅ `Ctrl+O` swaps the canvas to another project —
recents first, browse always one key away. Switching saves where you were in the old
project and restores where you were in the new one.

---

## 2. Spatial model

### 2.1 The grid

- **Row = folder.** Every folder in the target project containing at least one `.gd`. ✅
- **Column = file** within that folder, left to right, **alphabetical.** ✅ Order is not
  user-arrangeable, so layout never becomes user data.
- Rows run as long as they need to. A folder with 40 scripts is a 40-card row. ✅
- Only `.gd` files are shown. `.tscn` and other resources are **excluded entirely.** ✅
- **`addons/` is excluded entirely**, along with `.godot/` and hidden directories. ✅

### 2.2 Nesting

Folder depth is shown with **indent + gutter**, not with a tree widget. ✅

- Each row has a sticky label on the left edge of the viewport showing the folder path.
  It stays pinned as you pan horizontally, like a frozen table header.
- Row start-x is offset by depth, so `res://scenes/enemies/` visibly hangs off
  `res://scenes/`.
- Gutter color/weight encodes depth as a secondary cue for when a row is scrolled past
  its own indent.

### 2.3 The card

Each file is a **fixed letter-paper rectangle** (portrait, 8.5:11). The file's code
scrolls *inside* that fixed viewport. Cards never resize to fit content and files are
never paginated across multiple cards — one file, one card, one scrollable viewport. ✅

**100% zoom is defined by the card filling the viewport vertically**: card height ≈ 🎚90%
of viewport height, width derived from the aspect. ✅ On 16:9 that puts the focused card
at ~750px wide with ~580px of margin each side — so most of a neighbor card is visible on
each flank. That flanking sliver is the whole point: you always see that there's more.

**No scrollbars.** ✅ Scroll position is communicated by three cues:

- A line-range readout in the card header — e.g. `142–184 / 520`.
- A soft gradient fade at the top/bottom edge of the text area when content continues.
- A hairline tick on the right edge that fades in during scroll and out 🎚600ms after.

Card header carries: filename, `extends` target, twine count, line-range readout.

Clicking a card focuses it; the camera animates to center it. ✅

### 2.4 Line rendering — no wrapping ✅

A card is ~80–90 monospace characters wide at 100% zoom. Longer lines are **clipped, not
wrapped**, with a soft fade at the right edge and a subtle marker on any clipped line.
Horizontal scroll inside a card stays off the table — horizontal belongs to navigation.

🎚 Optional: hovering a clipped line reveals its full text in an overlay ribbon that
extends past the card edge.

This is the right call for a structural reading tool — over-long lines are almost always
detail, not shape — and it buys a real architectural simplification: **every line is
exactly one row height.** Line→y mapping is uniform and constant, which makes anchor
clamping (§5.1), the line-range readout (§2.3), refresh-by-line-number (§6.2), and the
Skim-zoom signature view all trivially exact. Soft-wrapping would have made every one of
those variable-height calculations.

---

## 3. Navigation

### 3.1 The vertical-axis conflict

Vertical is overloaded: scrolling code and hopping folders both want it. Resolution:

**Vertical scroll never leaves the focused card. Folder hop is a separate, discrete
jump.** ✅

- No scroll-chaining. Hitting the bottom of a file stops, with a rubber-band. It does
  **not** pull the next folder into view — GDScript files are long and that would misfire
  constantly.
- Scroll input always targets the **focused** card. Neighbors visible on screen are not
  independently scrollable; to read another file, focus it.

### 3.2 Bindings

| Action | Input |
|---|---|
| Scroll focused card | Wheel / two-finger |
| Move focus left / right (one file) | `H` / `L`, trackpad swipe |
| Hop folder up / down | `Shift+Wheel`, `Shift+J` / `Shift+K` |
| Zoom | `Ctrl+Wheel`, `+` / `-` |
| Peek overview | Hold `Space` |
| Cycle twines / follow | `Tab` / `Shift+Tab`, then `Enter` |
| Back / forward | `Alt+←` / `Alt+→` |
| Jump to file (fuzzy find) | `Ctrl+P` |
| Find within focused card | `Ctrl+F`, `Enter` / `Shift+Enter` to cycle |
| Detected lines: pointed at → this file → all | `Ctrl+E` |
| Connections panel | `C` |
| Overview (latched; click a card to land) | `M` |
| Back out (overview, framing, selection) | `Esc` |
| Quit | `Ctrl+Q` / `⌘Q` |
| Select text (see §8) | `Alt`-drag |
| Loose ends panel | `Ctrl+L` |
| Shortcut legend | `?` / `F1` |
| Open another project | `Ctrl+O` |
| Cycle / adopt couplings | `G` / `Shift+G`, then `A` |

`Ctrl+Wheel` goes to zoom (universal convention); folder hop takes `Shift+Wheel`. ✅

Every chord accepts `Ctrl` or `⌘`; labels show the one the platform uses.

### 3.2a Chrome ✅

The keyboard is the fast path, but every binding worth a button has one, and every
button's tooltip names its key — so the chrome is also how the keyboard is learnt.

- **Toolbar** (top): move (`‹ › ▴ ▾`, Back / Forward), where you are (folder, file,
  position), find (Go to file, Find), zoom (`−`, Read · Skim · Map, `+`, Overview),
  panels (Loose ends — only when something is loose — Connections, refresh, open, `?`).
- **Connections panel** (right) — §5.7.
- **Context pill** (bottom centre): names the temporary state you're in — peek,
  overview, framing a coupling, a selected twine, a drag in progress — with that
  state's next moves as buttons. None of them is a mode you can get lost in.

Focus centres in the space the toolbar and panel leave free, not in the raw window,
so the panel never sits on the card you're reading. Buttons never take keyboard
focus: a focused button would swallow `Space`, `Enter` and the arrows.

`Esc` backs out one level at a time and **no longer quits** — a key you press to
dismiss things shouldn't also close the window. Quit is `Ctrl+Q` / `⌘Q`.

### 3.3 Column memory

Each folder remembers the last file focused in it. Hop down and back up and you land
where you left, not at column 0. First visit to a row defaults to its first file. ✅

Rejected: resetting to column 0 (loses your place) and preserving the raw column index
across rows (file #4 in another folder is meaningless).

### 3.4 Camera

Focused card is **always centered**, even at the start or end of a row. ✅ This leaves
dead space on one side rather than clamping flush — the emptiness is itself a position
cue, and a consistent focal point matters more than filling the viewport.

Unfocused cards are dimmed and lowered in contrast. No blur (expensive under GL
Compatibility).

Camera moves are eased, 🎚~180ms. Every jump — focus move, folder hop, twine-follow,
fuzzy-find — animates rather than cutting, so the user keeps their spatial bearings.

### 3.5 First open ✅

Read zoom (100%), focused on the first file of the root row. Alphabetical order means
there is nothing to the left — the user starts at the left edge of the project and
travels right. Map-zoom-first was considered and rejected: the better first impression,
but the wrong habit to teach.

### 3.6 Peek overview ✅

A 40-card row needs a way across that isn't 40 keypresses.

- **Hold** `Space` → camera zooms out to fit the **current row** end to end.
  Hold past 🎚400ms → continues out to full-project Map.
- While peeking, arrow keys or the mouse move a selection across the visible cards.
- **Release** → camera returns to Read zoom, focused on whatever was selected. Release
  without moving and you land exactly where you started.

Spring-loaded, so it's a glance and not a mode. A *tap* of `Space` (under 🎚150ms) does
nothing, to keep taps from flickering the view.

### 3.7 Fuzzy find ✅

`Ctrl+P` opens a fuzzy finder over every `.gd` path in the project. Selecting one flies
the camera to that card and focuses it. Peek only helps within the region you're near;
this covers the rest.

### 3.8 Find within a card ✅

`Ctrl+F` searches the **focused card only**. Matches highlight in place; `Enter` /
`Shift+Enter` cycle through them, scrolling the card to each. `Esc` closes and restores
the prior scroll position. A sealed reading room still wants find.

Deliberately **not** in v1: project-wide text search. `Ctrl+P` covers paths, `Ctrl+F`
covers the file in front of you, and a full-project grep wants a results surface that
doesn't exist yet on this canvas.

### 3.9 Navigation history ✅

Twine-follow and fuzzy-find can teleport you anywhere, so there's a back-stack.
`Alt+←` / `Alt+→` walk it. Every discrete jump pushes an entry; incremental `H`/`L`
stepping does not (it would flood the stack).

---

## 4. Zoom as the mode axis

There is no separate "graph view." Zoom is continuous, with **semantic breakpoints** —
one camera, one dataset. ✅

| Zoom | Name | Card renders as |
|---|---|---|
| 100%–50% | **Read** | Full syntax-highlighted source, scrollable |
| 50%–25% | **Skim** | Method signatures only — a table of contents |
| <25% | **Map** | Titled node; folder bands visible; twine is the point |

The focused card stays fixed under the cursor while zooming, so zoom never loses your
place. ✅

Consequence: a twine drawn in Map is the *same* twine, on the *same* anchors, when you
zoom into Read. There is no "easy version" and "hard version" of the feature.

---

## 5. Twine

### 5.1 Anchoring

An anchor stores a **symbol reference** (`func take_damage`), never a line number. ✅
Line numbers rot the moment the target project changes; symbol names survive.

Rendering degrades by available precision rather than disappearing:

- Anchor's line is **visible** → twine attaches at that exact y on the card edge.
- Anchor is scrolled **off-screen** → twine slides to the card's top or bottom edge and
  pins there, with a small chevron (`↑`/`↓`) meaning "your anchor is that way." ✅
- Card is **too small to resolve lines** (Skim/Map) → all of that file's twines converge
  on a single dock point per edge, fanned slightly so they stay distinguishable. ✅
- Far endpoint is **entirely off-screen** (the common case at Read zoom) → the twine
  renders as a short stub at the card edge, angled toward its target, labeled with the
  far file's name on hover. `Tab`-cycling (§5.5) is how you actually traverse them. ✅

This is the answer to "the method disappears while scrolling and the twine goes away."
It doesn't go away; it clamps.

### 5.2 Creating a twine ✅

Mouse-driven. Plain drag on a card draws twine — it's the app's defining act, so it gets
the unmodified gesture.

1. Drag from a func in card A (or from anywhere on card A).
2. Release anywhere on card B.
3. A **picker** appears listing B's symbols — funcs, with `Whole file` as the top entry.
   Type to fuzzy-filter. `Esc` cancels the entire drag.
4. The same picker resolves the source end, so **neither card ever has to be scrolled to
   line up two methods.**
5. A description field follows. It is **optional** — but an undescribed twine renders as
   a *loose end* (pale, dashed) rather than solid red, so it visibly nags until labeled.

### 5.3 Two colors ✅

- **Red** — user-authored, carries a typed description. The whole point of the app.
- **Blue** — *inferred* from source, thin, desaturated, unlabeled. **In v1.**

Inferred edges are nearly free: §7's line scanner already walks every line, so reference
sites come out of the same pass. They're what makes first-open show a real dependency web
instead of an empty canvas.

Parsed for v1: `preload()` / `load()` with literal paths, `extends`, `class_name`
references, `signal` + `connect()` targets, autoload usage. The edge anchors at the
*reference line* in the source file and terminates at the target file's whole-file anchor.

### 5.4 Rendering

- Slight catenary sag, so it reads as string rather than as a graph edge.
- Drawn over cards; cards carry a soft shadow to keep depth legible.
- Description label sits at the twine's midpoint: always visible at Map, on hover/focus
  at Read.

**Clutter control** ✅ — different defaults per color:

- **Red** always draws. Twine not touching the focused file is dimmed 🎚.
- **Blue** draws only the edge you point at in the connections panel (§5.7) or select
  with `G`. Even one file's inferred lines are soup past a handful — a well-used
  autoload has dozens, all leaving one card corner toward cards that are off-screen —
  and the panel is where they're read. `Ctrl+E` widens to *this file*, then *all*
  (useful at Map zoom to see the whole web). A highlighted edge whose far end is
  off-screen draws as a stub labelled with the far file, not a line out of the window.

### 5.5 Twine as navigation ✅

`Tab` / `Shift+Tab` cycles the focused file's twines, highlighting each and its far
endpoint. `Enter` follows — the camera flies to the far end and focuses that card,
pushing a history entry (§3.8).

This makes twine functional rather than decorative, which is what makes it worth drawing
carefully.

### 5.6 Loose ends ✅

Two kinds of twine need attention, and they share one surface — a **Loose Ends** panel
(`Ctrl+L`) with a badge count:

- **Undescribed** — drawn but never labeled (§5.2). Pale and dashed.
- **Broken** — the anchored symbol or file no longer exists after a refresh (§6.2).
  Rendered frayed, anchored to whatever still resolves (file, if the func is gone).

Broken twine is **never auto-deleted.** ✅ A rename is indistinguishable from a deletion
at the text level, and silently discarding a user's annotation because they refactored is
unacceptable. From the panel each entry can be repointed to a new symbol or deleted
deliberately.

### 5.7 Connections panel ✅

On the canvas a connection is a line, and a line to an off-screen card only says
"somewhere that way". The panel is the same data as a list you can read:

- **Twine** — the focused file's red string: far file, direction, description (or a
  nudge if unlabelled), broken flag. Click selects (same as `Tab`), **Go** follows
  (`Enter`), **×** deletes.
- **Uses** / **Used by** — detected couplings out of and into the focused file,
  strongest first, with the evidence (`autoload ×13`) and the far file's folder.
  Pointing at a row draws that one line; click frames the pair (same as `G`); **Go**
  focuses the far file; **+** adopts it as twine (`A`).
- The **Lines** switch (pointed at · this file · all) is `Ctrl+E`.

The panel and the keyboard select the same things — rows carry indices into the
canvas's twine cycle and coupling list — so `Tab` and `G` light up rows and clicks
light up the pill. Open/closed and the lines mode persist in the session file.

An empty Twine section explains how to draw one, which answers Open Question 1: first
open is never an empty canvas, and the panel says what to do with it.

---

## 6. Live data and persistence

### 6.1 Refresh ✅

The target project changes underneath this app constantly — it's meant to sit open beside
Godot. **Re-scan on window focus-gain**, plus a manual refresh key. Cheap enough at
project scale, and it matches the moment the user actually looks back at the notebook.

### 6.2 What a refresh does to a card ✅

- **Scroll position holds by line number**, not by pixel offset or proportion, clamped to
  the new file length. The line you were reading stays where it was.
- Anchors re-resolve by symbol name. Found → twine reattaches silently at the new line.
  Not found → the twine goes **broken** (§5.6), not deleted.
- No modal, no interruption. The Loose Ends badge increments; that's the notification.

### 6.3 Persistence ✅

Two stores, deliberately split.

**`.gdreader/links.json`** — in the *target* project. Shared, human-readable, diffable,
committable. Annotation only: never layout, never viewport state.

```json
{
  "version": 1,
  "links": [
    {
      "id": "b3f1c2",
      "from": { "file": "res://player/player.gd", "symbol": "func take_damage" },
      "to":   { "file": "res://ui/health_bar.gd", "symbol": "func _on_damage" },
      "description": "damage path — signal hop, not a direct call"
    }
  ]
}
```

**`user://gdreader_session.json`** — local, private, never committed. The recent project
list, per project the focused cell, zoom level and per-folder column memory (§3.3), and
the reader's chrome preferences (connections panel open, lines mode).
Nobody should diff someone else's scroll position.

Switching projects saves the outgoing one's position first, so returning to a project
lands you on the card you left at the zoom you left it.

---

## 7. Parsing

Symbols must be extracted with **line numbers**, which rules out loading the script as a
resource and calling `get_method_list()` — that gives names without positions, and
loading foreign scripts risks side effects (`class_name` registration, tool scripts).

So: a hand-rolled line scanner over raw text, capturing `func`, `signal`, `class_name`,
`extends`, `const`, top-level `var`, and the inferred-edge reference sites of §5.3.
Cheap, safe, and it yields exactly the line-number index that anchor clamping (§5.1) and
refresh (§6.2) need.

Syntax highlighting follows Godot's own editor theme, so code looks like it does at home.

---

## 8. Text selection ✅

Allowed, behind a modifier. Plain drag draws twine; **`Alt`-drag selects text**, `Ctrl+C`
copies. Copying out of a notebook isn't editing, and being unable to lift a snippet would
be needlessly precious — but twine keeps the primary gesture.

---

## 9. Explicitly out of scope

- Editing source. ✅ Sealed notebook — no writes to the target project's `.gd` files.
- Opening files in an external editor. ✅ No escape hatch to Godot or VS Code.
- `.tscn` / scene structure. ✅
- `addons/`. ✅
- Pagination of long files across multiple cards. ✅
- Multiple projects open *simultaneously*. ✅ One at a time; `Ctrl+O` switches.
- User-arranged file order. ✅

---

## 10. Automatic coupling detection

The analyser proposes connections; the user adopts the ones that mean something.
**Inferred edges never become twine on their own** — the analyser knows *that* two files
are coupled, only the reader knows *why*, and the why is the entire point of twine.

GDScript can't be fully resolved without running it, but it is strongly idiomatic and
coupling leaves recognisable text behind. Every rule is **evidence-bearing**: an edge
cites the lines that produced it, so a wrong guess is visibly wrong rather than
mysterious.

### 10.1 Rules and weights

| Weight | Rule | How it's found | Confidence |
|---|---|---|---|
| 10 | **extends** | `extends Foo` resolved through the `class_name` registry | certain |
| 6 | **preload** | `preload()` / `load()` with a literal `res://` path | certain |
| 5 | **autoload** | singleton name from the target project's `[autoload]` block | certain |
| 4 | **type** | a `class_name` used as a type hint or constructor | high |
| 3 | **group** | one file `add_to_group("x")`, another queries `"x"` | medium |
| 2.5 | **signal** | `signal died` in one file, `_on_died` / `.connect` in another | convention |

Weights are relative, not absolute. Inheritance is the strongest coupling a file can
have; a shared group string is real but loose. Repeat references raise an edge's weight
with diminishing returns — forty uses is not forty times the coupling of one.

Engine types are excluded by prefix. Without that, `Node2D` couples everything to
everything and the map says nothing.

### 10.2 Reach

"Reach" is a file grabbing outside itself: `get_parent()`, `owner.`, `/root/...`,
`$"../.."`, `find_child()`, `get_tree().root`. It is scored **per file, not as an edge**,
because the target usually can't be resolved statically — but it's worth surfacing,
since it's the coupling that hurts most and the only kind the language doesn't mark.
Shown in the HUD and on the Map card.

### 10.3 What this catches that nothing else does

Group and signal rules find files that **never mention each other**. In the test
fixture, `health_bar.gd` couples to `player.gd` purely through
`get_first_node_in_group("player")` and `damaged.connect(...)` — two strings, no import,
invisible to any dependency tool that follows references.

### 10.4 Limits — honestly

- **Dynamic paths are invisible.** `load("res://" + name + ".gd")` cannot be resolved.
- **Duck typing is invisible.** `body.take_damage(...)` names no type; any file with
  that method might be the target, so we don't guess.
- **Signal pairing is a convention, not a fact.** Two unrelated files can both use
  `died`. It is the lowest weight for that reason.
- **`class_name` is required** for the type rule. Scripts without one are only reachable
  by preload path.
- **Scene wiring is entirely absent**, because `.tscn` is out of scope (§9). Editor-made
  signal connections and node references will never appear.

### 10.5 Adopting

`G` / `Shift+G` cycles the detected couplings for the focused file, strongest first; the
candidate is highlighted with its evidence. `A` opens the twine dialog with both ends
filled in and the evidence as a starting description — accept it or rewrite it in your
own words. That is the automation: the machine proposes the *that*, you supply the *why*.

**Cycling moves the camera, not focus.** Each press frames both ends of the coupling,
zooming out only as far as the pair needs — so you see the relationship rather than
hunting for it. Focus deliberately stays put: the candidate list is derived from the
focused file, so moving focus would rebuild the list on every press and the thing you
were cycling through would change under you. `Esc` stops framing and returns to the
focused card at the zoom you were reading at.

---

## Theme

Dark. The card is still a sheet of letter paper in shape and behaviour — it's dark
stock with light ink. Every colour lives in `scripts/palette.gd`; nothing else reads a
literal colour, so a light theme is that one file's values.

The window is **95% opaque**, so the desktop shows faintly through the gutters between
cards. Cards stay fully opaque — this is atmosphere, not a readability tax.

Under GL Compatibility a transparent viewport clears alpha to **zero** regardless of
the clear colour's alpha, which would make the window fully see-through. The backdrop
is therefore painted explicitly on a layer beneath everything, at the opacity we
actually want. Requires `per_pixel_transparency/allowed` in project settings.

---

## Implementation status

Built and verified against a fixture project:

- §2.1–2.2 scan, rows/columns, alphabetical order, depth indent + gutter, exclusions
- §2.3 letter-paper card, 90%-of-viewport zoom definition, no scrollbars, line-range
  readout, edge fades, fading hairline tick
- §2.4 clip-don't-wrap, with the `›` marker on clipped lines
- §3.1 scroll stays in the focused card, clamps, never chains
- §3.2 `H`/`L`, `Shift+J/K`, `Shift+Wheel`, click-to-focus
- §3.3 per-row column memory
- §3.4 always-centred eased camera, dimmed unfocused cards
- §3.5 first open at Read zoom, first file of the root row
- §3.8 navigation history on `Alt+←/→`; discrete jumps push, `H`/`L` stepping doesn't
- §3.7 fuzzy find on `Ctrl+P` — subsequence match, ranked
- §3.6 peek — hold `Space` for the row, keep holding for the whole project; arrows or
  mouse move the selection, release lands there, a tap does nothing
- §4 all three breakpoints — Read (full source), Skim (signature table of contents),
  Map (titled node) — on `Ctrl+Wheel`, `+`/`-`, `0` to reset, eased between levels
- Shortcut legend on `?` / `F1`, listing only bindings that are actually wired up
- §5.1 all four anchor states — exact, clamped above/below with chevron, whole-file
  dock, broken — plus off-screen stubs angled at their target
- §5.2 drag to create, one panel resolving both ends, source preselected from the
  func under the drag, description optional
- §5.3 red user twine and blue inferred edges (preload/load), both live
- §5.4 catenary sag, midpoint labels, dimming for twine that misses focus, `Ctrl+E`
  to reveal every inferred edge
- §5.5 `Tab`/`Shift+Tab` cycles the focused file's twine, `Enter` flies to the far end
  and scrolls the anchored line into view
- §6 `.gdreader/links.json` in the target project; `user://` holds the session
- §6.2 refresh holds scroll by line number (`R`); focus-gain trigger not yet wired
- §7 line scanner: symbols with lines, `extends`, `class_name`, preload/load ref sites

The symbol index is built for **every** file at open, separately from card text
loading. Anchors have to resolve for files that are off-screen and unloaded, which is
the normal case for a twine's far end.

Skim and Map render from the symbol index, not from file text, so they cost nothing
for cards that were never loaded — and zooming out of Read releases every card's text.

Text in Skim and Map is sized to a target **pixel** height and converted back to world
units. Zooming out therefore shows less detail at a readable size, rather than the same
detail shrunk into illegibility. Twine weight, labels and chevrons compensate the same
way, so string holds its apparent thickness at Map zoom where it is the whole point.

**Deviation from §4:** the focused card stays centred while zooming rather than fixed
under the cursor. Cursor-anchored zoom fights the rule that the camera is derived from
focus (§1); centring keeps one focal point and never loses your place either.

Peek reuses the zoom machinery rather than duplicating it: it drives the same
`zoom_level` goal, so the breakpoints apply during a peek and a long hold over a wide
row genuinely lands in Map. Fitting a short row can stay in Read — the fit is computed
from the row's real extent, not assumed.

Fuzzy ranking scores each candidate **twice** — once against the path, once against
the filename alone, with a bonus on the latter. A query matching only the folder
otherwise ties every file inside it, so "play" under `player/` would rank its three
siblings equal to `player.gd`. The `res://` prefix is stripped before matching, or a
query scores on the shared prefix instead of on anything meaningful.

- §3.9 find-in-card on `Ctrl+F`, with match highlighting, a counter, `Enter` /
  `Shift+Enter` stepping, and `Esc` restoring the prior scroll position
- §5.6 Loose Ends panel on `Ctrl+L` — unlabelled and broken twine in one list, with
  jump, label-in-place and discard
- §8 `Alt`-drag text selection and `Ctrl+C`, in exact (line, column) space
- §10 coupling analysis: six rules, weighted rendering, per-file reach, and `G`/`A`
  to adopt a detected coupling as twine, with the camera framing each pair
- `Ctrl+O` project switching, recents, and per-project session restore

- §3.2a toolbar, context pill and `M` overview; `Esc` backs out instead of quitting
- §5.7 connections panel, with pointed-at / this-file / all line modes on `Ctrl+E`

Fixed along the way: `Ctrl+L` never opened Loose ends — the plain `L` (next file) arm
matched first. Chords are now handled before plain keys. Back / Forward now record
both ends of every jump, so Back after a single jump returns where you came from.

The spec is now fully implemented.

`tests/smoke_test.gd` covers the parser's line numbers, all five anchor states, and
`links.json` round-tripping:

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path gd-reader --script res://tests/smoke_test.gd
```

Known gap: row labels are drawn in world space and scroll away with the canvas — §2.2
calls for them to stick to the left edge of the viewport. The toolbar's folder
breadcrumb covers it for now. Labels are capped to the gap above their row, so at Map
zoom they no longer print over the previous row's cards.

Dev harness:

```bash
/Applications/Godot.app/Contents/MacOS/Godot --path gd-reader -- /path/to/project
```

`--focus ROW,COL` opens on a given cell, `--zoom N` opens at a zoom level,
`--all-inferred` / `--file-lines` start in those line modes, `--hover N` points at the
Nth coupling row, `--twine N` selects the focused file's Nth twine, `--overview` opens in overview, `--no-connections` hides the panel, `--peek row|map` captures a
peek in progress, `--legend` opens the shortcut legend, `--find QUERY` opens the finder
on a query, and `--shot out.png` captures a frame and exits — which is how each state above was verified.

---

## Open Questions

Both resolve by building, not by deciding.

1. **Empty state.** A project with no twine at first open — any onboarding affordance, or
   does the blue inferred web (§5.3) carry it on its own? Likely the latter: first open
   is never actually an empty canvas.
2. **Live-text budget.** Under GL Compatibility, how many cards can render real
   highlighted text at once before off-focus cards need cached textures? §2.3 implies
   3–5 live at Read zoom; Skim and Map need a cheaper representation regardless.
