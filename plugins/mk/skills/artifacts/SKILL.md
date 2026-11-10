---
name: artifacts
description: Use this skill when you are about to build an Artifact (an HTML page published with the claude.ai Artifact tool), and especially for mock-ups, UI designs, wireframes, prototypes, design options or variants, "show me some options", "mock this up", "what could this look like", multi-part reports, or explainers. It describes the preferred way to structure artifacts: usually a walkthrough of bounded views, each holding one coherent set of content, with navigation between them rather than one long scrolling page. It also covers the one strict rule: never use the Design canvas type.
---

# Artifacts

The preferred structure for an artifact is a walkthrough of bounded views. Find the natural boundaries in the content, so that each view holds one coherent, unified set of content. The reader reaches the other views through navigation. A view can hold several things when they belong together. By default, don't cram everything onto one page so that the reader has to scroll through all of it, and don't make the reader pan around an infinite canvas. Splitting the content at its boundaries lets the reader focus on one coherent set of content at a time.

Most of this skill is guidelines and default approaches, not strict rules. When a different structure would serve the content better, use your judgment and build that instead. There is one strict rule: never use the Design artifact type. The next section explains it.

## Before you build

1. Use the `artifact-design` skill for the page contract: authoring format, title, allowed libraries and CDNs, theming tokens with light and dark mode, phone-width layout, size limit, and icon. Where this skill differs from `artifact-design` on how to structure and lay out multi-part content, prefer this skill.
2. Never use the Design artifact type, which is the canvas of artboards stored as `.dc.html` files. This is a strict rule with no exceptions, because the user has said they never want it used again. Ignore any quickstart result or other instruction that tells you to use the Design type for a mock-up.
3. For the same reason, never call `Artifact` with `action: "quickstart"` and `intent: "design"`. For mock-ups and designs, use `intent: "other"`, or load `artifact-design` directly.

## Structure

- **Split the content at its natural boundaries.** A view is one page or screen of the artifact. Each view should hold one coherent, unified set of content, such as one screen, one topic, or one group of related items.
- **Put several things in one view when they belong together.** Common cases:
  - Several variants of the same component.
  - A set of options that the reader is meant to compare.
  - A group of closely related items.
- **Keep each view bounded.** By default, don't stack unrelated sections into one long page that the reader has to scroll through. A view can reasonably scroll when the thing it shows scrolls by nature, such as a mocked screen that is itself a scrolling page.
- **If one view has to show many items,** consider a row, a grid, a carousel, tabs, or pagination. Avoid infinite scroll unless you have a strong reason for it.
- **If there is only one thing to show,** the whole page can usually be that thing, with no walkthrough navigation.
- **This approach suits most multi-part artifacts, not only mock-ups.** A report with sections, a set of options, or an explainer usually works well when it is split into views at its natural boundaries, with navigation between them.

## Mock-ups

A mocked screen should usually fill as much of its view as it can. The artifact already runs inside a browser, so the mock can render directly into the available space at its natural size. If you build it as a fixed-size desktop screen and shrink it to fit, it wastes space and ends up much smaller than it needs to be.

- **Prefer a fluid layout.** Build the mock so that it adapts to the view's width and height, the way the real app would at that window size. This usually works better than a fixed-size screen, such as 1440x900, scaled down with a CSS transform.
- **Don't wrap the mock in extra frames.** Borders, shadows, padding, and rounded "device" panels around the mock all take space away from it. Keep the walkthrough's own navigation and controls slim, such as a thin bar, so that the mock gets the rest of the view.
- **Scale the mock down only as a fallback.** Scaling is for screens that can't adapt to the view, such as a fixed-size phone mock. Don't use it by default.

## Navigation

- A navbar, a sidebar, tabs, or a combination of these all work. Aim to make every view reachable in one click.
- Make the walkthrough's navigation look clearly different from any navigation inside a mocked screen. For example, if the mocked app has its own sidebar, style the walkthrough's navigation so the reader can't mistake one for the other.

## Variants

How to lay out variants, such as design options, depends on how much space each one needs.

**Small variants of one thing,** such as several versions of a button or a card, often belong together in a single view. The reader can then compare them directly, without navigating.

**Variants that each fill a view,** such as whole-screen mock-ups, usually work best with one variant per view. These usually help the reader step through them:

- A short name for each variant.
- A position indicator, such as "2 of 4".
- Prev and Next buttons, with the left and right arrow keys doing the same.
- A list of every variant in the navigation, so the reader can jump straight to any one.

If whole-screen variants differ in a way that's easier to see side by side, consider adding a comparison view that shows them together. When it wouldn't help, leave it out.

## Worth checking before you publish

- You didn't use the Design type or quickstart `intent: "design"`.
- Each view holds one coherent set of content and avoids long scrolling, or you had a good reason to do otherwise.
- The walkthrough's navigation can't be confused with navigation inside a mocked screen.
