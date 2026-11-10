---
name: diagrams
description: >-
  Use this skill whenever you are about to author, edit, or review a diagram —
  in a doc, a README, a ticket, or anywhere else. It decides
  Mermaid vs. D2 for you and carries the D2 authoring pitfalls that are in no
  tutorial. Load it BEFORE writing any diagram source, not after the layout
  comes out wrong.
  Triggers: diagram, mermaid, d2, D2, sequence diagram, flowchart, architecture
  diagram, block diagram, box diagram, draw a diagram, add a diagram, chart the
  flow, visualize the architecture, layout, grid, "diagram source", .d2, graph
  TD, flowchart LR.
---

# Diagrams

## First, check that the diagram is worth adding

Add a diagram only when it lets the reader understand something faster than the text around it, such as a sequence of calls between several services or how components are arranged. If the text already explains it clearly, leave the diagram out. When two diagrams would overlap, combine them, unless the combined diagram would be too cluttered to read.

## Making a Mermaid diagram readable

- **Keep labels short,** ideally one or two words. A label names something that the text explains; don't put the explanation in the diagram.
- **Use styling to show what belongs together:** colors, line styles, boxes around groups, notes, and `alt` blocks in sequence diagrams. In a busy diagram, this tells the reader where to look.
- **Pick the diagram type that fits.** Sequence diagrams are not the only option: state, ER, flowchart and gantt diagrams each suit different content.

## Pick the tool by asking: is the layout a decision?

| | **Flow diagrams** | **Structural diagrams** |
|---|---|---|
| **Tool** | **Mermaid** | **D2** |
| Examples | sequence, state, gantt, ER, simple flowcharts | cache topologies, service maps, architectures, anything with lanes/layers/nesting |
| Why | Geometry follows from the content — participants and message order fully determine it. There is nothing to arrange, so a layout engine cannot get it wrong. | *Where a box sits* is part of what the diagram says: "these three are peers," "this is nested in that," "this layer is above that one." |
| Rendering | Native `mermaid` code block in GitHub, Notion and most doc tools. | Most doc tools can't render it. Render to SVG or PNG with the `d2` CLI and embed the image, keeping the source next to it. |

**The test:** if a reader is meant to see structure in *where things sit*, you need to be able to state the arrangement. Mermaid cannot. That is the whole reason D2 exists in our toolkit.

Do not reach for D2 out of habit. A sequence diagram in Mermaid is one code block and zero infrastructure; the same diagram in D2 is a render step, an upload, and a PNG. Use the cheap thing when it works.

## Why Mermaid cannot do structural diagrams

Not "does it badly" — **has no vocabulary for it.** Mermaid's flowchart is a *graph description language*: you declare topology and dagre picks the geometry. There is no way to say "put these three in a row."

Two consequences that will waste your afternoon if you don't know them:

**Every layout "fix" in Mermaid is a trick against the ranking algorithm** — invisible links, reversed edge declarations, anchoring arrows at inner nodes. **Those tricks do not survive a renderer change.** Markup that renders correctly under `mermaid-cli` locally comes out as unreadable spaghetti in Notion's Mermaid renderer, which runs a different version. You are not specifying a layout; you are hoping for one.

**Mermaid discards a container's `direction` whenever an edge crosses the container boundary.** So "boxes in a row inside a box, boxes stacked in rows" — the shape of most real architecture diagrams — is *structurally unreachable*, not merely awkward. No amount of styling fixes it. If you find yourself fighting this, stop and switch to D2.

## Writing D2

### Reach for a grid when the arrangement carries meaning

`grid-rows` / `grid-columns` are **constraints the engine must honor**. A free-form layout is a *suggestion*. The auto-layout isn't broken — it produces a valid drawing — it just optimizes for its own objective (short edges, few crossings), which frequently isn't the arrangement a reader finds intuitive.

**Default: if the reader is meant to see structure in where things sit — peers in a row, layers, lanes, nesting — declare it with a grid.**

Free-form (no grid) is genuinely right when the *topology* is the content and position isn't:

- A dependency or call graph, where "what connects to what" is the point and any readable arrangement will do.
- A tree or flow with one obvious direction, where `direction: down` gets you exactly what you want.
- Anything sparse enough that you don't care where the boxes land.

Forcing a grid onto those makes the source noisier for no benefit. And a grid you have to *fight* — spacers, invented empty cells — is a sign the shape isn't grid-shaped.

**The tell that you should have used a grid: you are nudging the engine.** Reversing edge declarations, adding invisible links, reordering statements to coax boxes into position — stop and state the arrangement instead.

### Grid columns are scoped to their container

Two sibling grids do **not** share a column axis. A `grid-columns: 3` row and another `grid-columns: 3` row below it each size their columns to *their own* content, and drift out of alignment.

**Fix: make each column a container** holding a vertical stack of what belongs in that column.

```d2
grid-columns: 3

col_a: "" {
  grid-rows: 2
  style: { fill: transparent; stroke: transparent }
  entry: "Cache entry A" { ... }   # top row
  job:   "Job A"         { ... }   # bottom row — shares the column BY CONSTRUCTION
}
col_b: "" { grid-rows: 2 ... }
col_c: "" { grid-rows: 2 ... }
```

The two rows now align because they are literally the same grid cell. It cannot drift, no matter how the labels change.

### There is no colspan, and no way to offset a row

You cannot make a bottom row's boxes sit *between* the boxes above them (the `X X X` / `X X` stagger). A 2-cell row and a 3-cell row don't share an axis — the 2-cell row's cells land at 25%/75%, not at the 33%/67% gutters.

The only way to force it is hand-tuned pixel spacers, and those **silently break the moment a label or a box changes width.** Don't. Take the plain alignment; it's honest and it can't rot.

### Never set `width:` / `height:` to fix a layout

Pixel sizing pins geometry to today's content. Change a label and it drifts, with nothing to tell you. If you're reaching for `width:` to nudge something into place, the layout is wrong — restructure it (usually into a grid) instead.

**`grid-gap` is safe** — it's spacing, not positioning, the same category as CSS `gap`. Raise it freely.

Note a nested grid has *two* gaps doing different jobs: the root's gap is horizontal space between columns; each column container's gap is vertical space within it. They're independent.

### Grid fill order is column-major

A `grid-columns: 2` grid fills *down* the first column before moving to the second. Four items `a b c d` render as `a c / b d`, **not** `a b / c d`. If order matters (a pipeline, a sequence), use `grid-rows: 1` to force a single row.

### Edge labels collide between the same pair of nodes

D2's grid router draws every edge center-to-center and drops its label at the **midpoint**. Two labelled edges between the same two boxes land their labels on the *same coordinate*.

If a relationship is bidirectional, say so with **one bidirectional edge**:

```d2
cache <-> job: read / write     # not two opposing arrows
```

Two arrows between the same pair also render stacked on top of each other and read as a rendering artifact, not a design.

If you need several distinct edges labelled, give them distinct endpoints, or move the key into a legend node and let line style (solid/dashed) carry the meaning.

### Reserved keywords

`top`, `bottom`, `left`, `right`, `near`, `width`, `height`, `style`, `label`, `shape`, `icon`, `direction`, `class`, and the `grid-*` family are reserved. Naming a node `top` fails to compile with a confusing error. Prefix it (`row_top`) or pick another name.

## Don't buy TALA

D2's paid layout engine looks like the answer to every layout problem above. **It is not, and the reason is structural.**

D2 branches on diagram type *before* layout runs. A grid diagram takes `d2grid.Layout()` and **never calls `coreLayout()` at all**. TALA is a third implementation of `coreLayout`. On a grid diagram it is code that never executes — a pure grid renders byte-identically under dagre and ELK, which is only possible if neither is running.

Its gated features (`NEAR_OBJECT` — object-relative `near:` — plus `CONTAINER_DIMENSIONS`, `TOP_LEFT`, `DESCENDANT_EDGES`, `ROUTES_EDGES`) are all free-form-layout features, on the wrong side of that branch.

**On the diagrams where you most want better layout, the fix is a grid — and a grid is what makes TALA inert.** TALA could only help a free-form diagram, which is the case where you'd already decided the arrangement doesn't matter much. The money never lands where the pain is.

(One practical note that follows: object-relative `near: some_node` is TALA-only. `dagre` and `elk` reject it with an explicit error. Use a grid.)

## Working practice

**Render and look at it. Every single time.** Most of the failures above are invisible in the source and obvious in the picture. Do not reason about what the layout will do — look.

```bash
d2 my-diagram.d2 /tmp/preview.png
```

This is also how you decide whether auto-layout was good enough: start free-form, look, and reach for a grid only if the engine's arrangement obscures the structure you're trying to show.

**Verify Mermaid in the destination's renderer, not only locally.** Renderers differ (GitHub, Notion and the Mermaid CLI don't lay out identically). For D2, rasterizing to PNG locally means what you previewed is what the reader sees.

**Comment the structure in the D2 source itself** — especially the invariants. "These are columns so the rows align by construction; don't replace this with two sibling grids." That's the knowledge that otherwise gets rediscovered painfully. Keep the source alongside the image, so the next editor will read it.

