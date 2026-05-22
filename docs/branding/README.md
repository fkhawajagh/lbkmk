---
title: Diwan — Branding Concepts
status: Concept sketches v0.1
date: 2026-05-22
---

> **Document Version: 0.1** | 2026-05-22
>
> Initial concept sketches for the **Diwan** application codename. These are SVG-vector concept drafts, not finished logos — they exist to establish a direction. A designer (ideally one fluent in Arabic calligraphy) should take any of these much further before they're used in production surfaces.

## Why "Diwan"

`diwan` (Arabic ديوان) historically meant the chancery / accounting department of the Islamic state — the office that kept track of revenue and expenditure across an empire. It also means a collection of poetry, lending a literary connotation. The codename was chosen because:

1. **Functional fit:** the system is exactly a diwan — a ledger for itemized revenue across multiple channels feeding into one accounting destination.
2. **Cultural fit:** LBK produces Islamic content, and `diwan` is a word the audience already knows.
3. **A gift in the name:** **Diwani is itself an Arabic calligraphic style**, developed by Ottoman court scribes specifically for documents from the diwan. The most natural visual treatment for the brand is calligraphy made by the diwan, for the diwan.

## The three concept directions

### 1. Arabic calligraphic wordmark — `diwan-wordmark-arabic.svg`

The word ديوان in a calligraphic-style Arabic typeface, paired with `DIWAN` in Latin beneath. Maximum cultural authenticity; leans into the heritage. Best for landing pages, about pages, formal documents.

**Caveat:** the SVG relies on a font fallback chain (`Aref Ruqaa, Reem Kufi, Amiri, Scheherazade New, serif`). If none of these are installed on the viewer's system, the browser substitutes a default Arabic face — readable, but not calligraphic. **For production use, the Arabic text should be converted to SVG paths** (so the form is preserved regardless of installed fonts) — that conversion is best done by a designer in vector software, or by exporting from a system that has Aref Ruqaa installed.

### 2. Khatam mark + wordmark — `diwan-khatam.svg` and `diwan-khatam-mark-only.svg`

An 8-point khatam star formed by two overlapping squares (one axis-aligned, one rotated 45°) — one of the most recognizable forms in Islamic geometric design. Paired with the Latin wordmark in `diwan-khatam.svg`; standalone in `diwan-khatam-mark-only.svg` for use as a favicon / app icon / small mark.

The metaphor: many points converging on one center. Accurate to what the application does (four channels, one accounting destination, all corresponded). Reads as both heritage and tool.

### 3. Minimal wordmark — `diwan-minimal.svg`

Just `Diwan` in a refined serif, with a small rhombus accent replacing the dot on the 'i' — the rhombus is a single point of the khatam, a quiet recurring visual hook. Designed for places where the brand needs to be present but not loud: dashboard chrome, email footers, document headers.

## Color and treatment

- **Primary color:** `#1a3a5c` (deep ink-navy). Chosen to feel trustworthy (the system handles money) and warm enough not to feel sterile.
- **All concepts work in monochrome** — black on transparent, white on dark. Test before locking the palette.
- **All concepts are stroke-and-fill only** — no gradients, no shadows. They scale to any size and reproduce cleanly in print.

## Viewing the SVGs

The files are plain SVG. To preview:

```bash
# macOS — opens in your default browser
open docs/branding/diwan-wordmark-arabic.svg
open docs/branding/diwan-khatam.svg
open docs/branding/diwan-khatam-mark-only.svg
open docs/branding/diwan-minimal.svg
```

Or drop them into any browser tab.

## Recommended next steps

1. **Pick a direction.** Three concepts are deliberately distinct so the choice is between *kinds* of mark, not slight variants. Decide whether you want Arabic-forward, geometric-forward, or restrained.
2. **Hand off to a designer.** Whichever direction wins, the next mile is real type tuning (kerning the Latin wordmark, converting the Arabic to paths, deciding on the right Diwani-script weight) — work that benefits from a designer with Arabic typography experience.
3. **Test at small sizes.** Whichever mark survives the favicon-size test (16×16, 32×32) is the right one. Open `diwan-khatam-mark-only.svg` in a browser and zoom out — if it still reads, that's a viable mark.
4. **Decide on a tagline (optional).** "DIWAN — Little Big Kids" or "DIWAN — Reckoning, reconciled" — only land this if it adds something. The wordmark alone is often enough.

## What's not here yet

- A full brand system (typography pairing, color tokens, voice guidelines). That work belongs after a direction is locked.
- Variants: light-on-dark, monochrome, square / round / wide adapter shapes for app store, social, etc.
- Print-ready assets (PDF, AI, EPS). SVG is the source format here; production exports can be derived from it.

These are tasks for whoever takes the chosen direction the rest of the way.
