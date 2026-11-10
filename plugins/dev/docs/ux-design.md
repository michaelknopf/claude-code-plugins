# UX design principles

These principles decide what goes on a screen and how it's laid out. Follow them for all UI work. That includes internal tools, dashboards, product screens, and the mockups and HTML artifacts you build. This doc is the UI counterpart of `voice-principles.md`. Follow `voice-principles.md` for how to word text.

In short:

- Use few words.
- Put one thing per line.
- Show little.
- Put details behind a click.

If a generic or aesthetic design skill, such as `frontend-design`, conflicts with these principles on content density, wording or layout, follow these principles. Visual style, such as palette and type, is out of scope for this doc.

## Show less

### Lead with the one result the page exists for

Decide which single question the page answers, and put the answer first. Everything else is secondary or a click away.

Example: on a model evaluation report, the result is which configuration was chosen, how well it did, and where it's weak.

### Show only what people need at a glance

People glance at a page. They don't analyze it. Internal pages are summaries, not workbenches for analysts. Every detail you show has a cognitive cost. A page that shows too much overwhelms people and stops being useful.

- Leave out a detail when people don't need it at a glance. It's fine not to show every detail.
- Don't add intervals, gap columns, tiers or statistics just because the data has them.
- Don't build pivot or compare views. People who need deep analysis ask Claude.

### Put details behind a click

When you think "someone might want this detail", put it behind a click instead of on the main view. Use one of these:

- An expandable row
- A detail page
- A tooltip

### Show at most three headline numbers

When a page has several metrics, show only the ones that matter most, big, side by side, each with its name under it. Up to three. The task declares which metrics are headlines, so a task with a binary outcome can lead with precision and recall, and others with a single score. Leave out the other metrics, or put them behind a click.

### Rank by what matters

Sort and highlight items by how much they matter to the result, not by what's easiest to count.

- Bad: a "most common mistakes" list sorted by count. It puts near-misses like a 4-star vs 5-star rating at the top, even though they barely cost any score.
- Good: the same list sorted by points lost under the task's score.

## Lay things out vertically

### Put one thing per line

When you show a list or a sequence of things, stack the items vertically. Don't string them across a line. People want to focus on one thing per line.

Don't try to save space. Whitespace is fine. Spreading items horizontally is just an attempt to fill the empty space on the right.

This rule covers:

- Lists
- Sequences of facts
- Rows of chips, pills or stats

The rule applies inside a panel, not to the page layout. A dashboard can put panels side by side in a grid, for example the score panel beside the configuration panel.

A few headline numbers are also fine side by side, each a big number with its name directly under it. They read at a glance as separate stats, which is what the rule protects. Long labels, sentences and lists of more than a few items still go one per line.

Tables are fine for tabular data, meaning rows of the same kind of thing with the same attributes. If you're unsure whether something is tabular, put one thing per line.

### Show one fact per value

Each value, cell or pill shows one fact. Don't join several facts with commas or "by".

Bad:

```
Reviewed  421, by Alex
```

Good:

```
Reviewed  421
Reviewer  Alex
```

### Label things where they are

Put each label on or next to the thing it describes, not in a legend.

- Put the overall value "92.5" directly above the dashed reference line drawn over the bars. Don't put it in a legend row "All items — 92.5" below the chart.
- Put bucket names and counts on the segments of a stacked bar. Don't put them in a row of labels under the bar.

## Use few words

### Write labels, not sentences

UI text is labels. Put explanations in tooltips or docs.

- Bad: a tier label that reads "Can't be told apart from it".
- Bad: a scope control written as the sentence "Scored on holdout using all labels".
- Good: the same scope control as two labeled dropdowns, `Split [Holdout]` and `Labels [All]`.

### Say each thing once

Don't repeat information that appears elsewhere on the screen. Don't use two labels that mean the same thing.

- Bad: `To review   44 open queue`. "To review" and "open queue" say the same thing.
- Good: `To review  44`

### Name columns plainly

Head columns with short, familiar words instead of marking every row with an icon.

- Bad: columns headed "Expected" and "Said".
- Bad: a green check and a red cross beside every label in a list of mistakes. The list is already all mistakes, so the marks repeat the same fact on every row.
- Good: columns headed "Label" and "Prediction".

## Design for the data that exists

Before you choose a format, look at the shape of the real data.

Example: a runs list showed only dates. The real data had 15 launches and 136 runs in one 3-hour window, so the list needed times and needed to group runs by launch.

Don't design around information the system can't provide. Example: an earlier eval design assumed a "production configuration", but the eval system has no way to know which configuration is in production.

## Review checklist

Check each UI against these questions before you finish:

- Does the page lead with the one result it exists for?
- Are there at most three headline numbers?
- Could any detail move behind a click?
- Inside each panel, are lists, sequences and stats one per line, not strung across a line?
- Does each value show one fact?
- Is each label on the thing it describes, not in a legend?
- Is the text labels, with explanations in tooltips or docs?
- Is anything shown twice, or named two different ways?
- Are items ranked by what matters, not by raw count?
- Does the design fit the real data, and use only information the system actually has?
