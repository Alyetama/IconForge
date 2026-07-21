# IconForge

IconForge turns a sentence about an app into a finished macOS icon.

You type a name and what the app does. IconForge writes the image prompt, hands it to the `agy` CLI, and then does the part that usually gets skipped: it masks the artwork into the Big Sur squircle, drops a soft shadow under it, and builds every size Apple asks for. You get an `.icns` you can drop straight into a bundle.

<img src="docs/mockup.svg" alt="IconForge window showing an icon preview on light and dark backgrounds" width="100%">

## What you need

- macOS 14 or later
- `agy` installed and runnable from your shell. Check with `which agy`.
- Xcode command line tools, for `swift` and `iconutil`. Run `xcode-select --install` if `iconutil` is missing.

`sips` and `iconutil` ship with macOS, so there is nothing else to install.

## Install

```bash
./install.sh
```

That builds a release binary, wraps it in `IconForge.app`, ad-hoc signs it, and copies it to `/Applications`. Launch it from Spotlight afterwards.

If you would rather not install it, `./build_app.sh && open build/IconForge.app` runs the same bundle out of `build/`.

There is no Homebrew formula because this repo is not published anywhere. The install script is the one command.

## Using it

Fill in the name and a short description. Everything else is optional:

- **Subject** is the object the icon shows. Leave it blank and IconForge asks the model to pick one, then writes its answer back into the field so you can edit it and reroll.
- **Palette** opens a grid of 192 trending [Coolors](https://coolors.co/palettes/trending) palettes. Pick one and its hex values go into the prompt verbatim, or ignore the grid and type a direction like "sea glass to deep teal" in the field below it. To swap the library for a different export, run `python3 Tools/generate_palettes.py your-palettes.json` and rebuild.
- **Style** nudges the render toward Standard, Playful, Minimal, or Glossy.
- **Model** lists what `agy models` reports, minus the Claude entries. Refresh it with the button next to the picker. To change what gets filtered out, edit `excludedModelPrefixes` in `Sources/IconForge/AgyRunner.swift`.

- **Icons per run** generates up to four at once, each with its own subject and its own art direction. They appear as a row under the preview and clicking one makes it the active icon for Export, Reveal and the agent prompt.

Press Generate. One icon takes roughly fifteen to thirty seconds on the low-effort Gemini models; four run in parallel and take about as long as the slowest.

Reroll deliberately changes the idea, not just the pixels. A subject IconForge picked for you is thrown away and re-derived, steering clear of the last dozen it used, so a second press gives you a different object rather than the same one drawn again. Type your own subject and it sticks: only the art direction varies. The strip along the bottom keeps every past run, and clicking one loads its icon and inputs back into the window.

## Where the files go

Every run gets its own folder under `~/IconForge`, so nothing overwrites anything:

```
~/IconForge/
  tidepool-20260714-101322/
    prompt.txt          # the exact prompt sent to agy
    source_raw.png      # what agy returned, untouched
    icon_1024.png       # the masked 1024 icon
    AppIcon.iconset/    # all ten sizes Apple requires
    AppIcon.icns        # the macOS icon
    AppIcon.ico         # Windows fallback
    meta.json           # inputs and model, for the gallery
```

Change the folder in Settings, or use the Export button to copy a finished set somewhere else. Clear empties the window without touching anything on disk.

**Copy as agent prompt** puts an instruction on the clipboard that points a coding agent at these exact files and tells it to install the icon on whatever app you have open in that session, then rebuild and reinstall. Paste it and let the agent do the wiring.

## How the icon is built

1. The raw artwork is centre-cropped and redrawn at 1024x1024, whatever size `agy` returned.
2. A squircle path is clipped out of it. The body is 824x824 on the 1024 canvas, with continuous corners built from a superellipse rather than circular arcs, so the curve meets each edge without a visible seam.
3. The masked body is composited onto a transparent canvas with a soft shadow beneath it. The surrounding margin stays transparent, which is what makes the icon sit correctly in the Dock.
4. Every required size is rendered from the 1024 master, and `iconutil` packs the `.iconset` into an `.icns`.
5. A `.ico` is written alongside it with PNG entries from 16 to 256 pixels.

The prompt tells the model not to draw a rounded square, because step 2 applies the real one. Change one and you should change the other.

### Tuning the shape

The geometry lives at the top of [`Sources/IconForge/IconPipeline.swift`](Sources/IconForge/IconPipeline.swift):

```swift
static let canvas: CGFloat = 1024
static let bodySize: CGFloat = 824
static let cornerRadiusRatio: CGFloat = 0.2237
static let squircleExponent: CGFloat = 5
static let shadowBlur: CGFloat = 22
static let shadowOffsetDown: CGFloat = 10
static let shadowOpacity: CGFloat = 0.28
```

Raise `squircleExponent` for squarer corners, lower it toward 2 for a plain rounded rectangle. Rebuild and the change shows up in the next preview, including the placeholder outline.

## When something breaks

**Could not find the agy command** usually means `agy` is somewhere the app cannot see. Apps launched from Finder get a bare `PATH`, so a binary in `~/.local/bin` is invisible to them even though it works in Terminal. IconForge checks the usual install directories and asks your login shell, but if it still comes up empty, paste the output of `which agy` into Settings.

**An unknown model** shows up as a non-zero exit from agy with its own message attached. Refresh the model list in Settings and pick again.

**No image appeared** means agy finished without writing a file, which normally happens when the model refused the prompt. Reroll and it usually goes through.

## Project layout

A plain Swift Package, no Xcode project:

```
Package.swift
Info.plist                 # copied into the bundle by build_app.sh
build_app.sh               # compile and assemble IconForge.app
install.sh                 # build_app.sh, then copy to /Applications
Resources/AppIcon.icns     # the app's own icon, made with IconForge
Sources/IconForge/
  IconForgeApp.swift       # @main scene
  ContentView.swift        # window, preview, gallery, settings
  GeneratorModel.swift     # run state, history, file layout
  AgyRunner.swift          # finding and driving the agy binary
  PromptBuilder.swift      # the prompt template and style variants
  IconPipeline.swift       # squircle, shadow, iconset, icns
  ICOWriter.swift          # Windows .ico container
```

`swift build` works on its own if you only want the binary, but the app needs the bundle to behave like a normal window app, so use `build_app.sh`.
