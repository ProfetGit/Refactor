# Refactor

Quality of life for World of Warcraft. Small features, each one explained in a line, each one
switchable per character. Built for Retail 12.1.0 first; WoW Forever support follows once that
client can be probed.

## Install

1. Download the release zip.
2. Extract it into `_retail_/Interface/AddOns/` so the folder is `AddOns/Refactor`.
3. If the build predates the current patch, tick **Load out of date AddOns** on the character
   selection screen.

## Use

- The minimap button opens the window. Right click prints recorded errors, drag moves it.
- `/refactor` opens the window. `/rf` works too unless another addon claimed it.
- `/refactor errors` prints anything Refactor's error boundaries caught.
- Blizzard Settings has a Refactor category with an Open button.

On first login Refactor asks once for a starting point: Minimal, Standard, Full, or nothing.
That choice is account wide, so a new character inherits it without a click.

Account defaults apply to every character. A character can override any feature with Inherit,
On or Off. The pause modifier (Ctrl by default) skips the next automatic action while held.

## Features in this build

| Feature | What it does |
|---|---|
| Fast loot | Collects loot when your auto-loot preference is active |
| Sell grey junk | Sells up to 12 grey stacks per merchant visit, never-sell list first |
| Repair with own money | Repairs within a gold cap, your own funds only |
| Vendor summary | One chat line with what was actually sold and repaired |
| Mail take-all | Manual, cancellable, rate-limited inbox collection |
| Fill DELETE confirmation | Types DELETE for you. You still click Yes |
| Auto stand | Unavailable on Retail: standing is a protected action |

## Development

```
make check     # luacheck, project rules, busted specs, API symbol check
make package   # deterministic zip in .release/
make api-index # regenerate Data/api-retail.json from a wow-ui-source checkout
```

`make dev-setup` installs busted, luacheck and dkjson into a local `.tools` tree.
Every API symbol a module uses is declared in its `requires` list and verified against
`Data/api-retail.json`, which is generated from Blizzard's own interface source for the
installed build. Bench numbers are published here once `/refactor bench` exists (roadmap M4).
