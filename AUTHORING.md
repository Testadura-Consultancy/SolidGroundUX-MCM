# Testadura website authoring

Normal website content is Markdown. Authors should not need to write HTML for
ordinary pages or common layouts.

The WebContent renderer supports standard Markdown plus a small Testadura
component extension. Component blocks start with `::: <class>` and end with
`:::`. Blocks may be nested.

## Tiles in a responsive grid

```md
::: td-grid
::: td-tile
### SolidGroundUX

Linux/Bash framework for consistent management and provisioning workflows.
:::

::: td-tile
### SolidGround IV

Application and integration framework.
:::
:::
```

The grid automatically places tiles next to one another when there is room and
stacks them on narrow screens.

## Sliding image gallery

```md
::: td-gallery
![First image](/images/example-one.png)

![Second image](/images/example-two.png)

![Third image](/images/example-three.png)
:::
```

The gallery uses native horizontal scrolling and scroll snapping, so it works
with a mouse/trackpad and touch without requiring JavaScript.

## Existing callouts

```md
::: td-note
A normal note.
:::

::: td-warning
Something requiring attention.
:::

::: td-technical
Technical detail.
:::
```

## Inline and image classes

The existing `td-` classes can still be applied directly where supported:

```md
[Identify]{.td-green}

![Product image](/images/product.png){.td-image-product}
```

Keep custom component names under the configured `td-` prefix. Validation will
report a referenced `td-` class that does not exist in the site CSS.

## Homepage and Featured cards

Set `hide_title: true` in front matter to suppress the compact context/title bar (most useful on home pages).
The regular title bar remains the default. The home page illustration is inserted as a standard Markdown image; use a wide image with its entire embedded composition preserved.

The homepage Featured slider selects pages using `featured: true` in their Markdown front matter. `featured: false` (or omitting the field) excludes the page. `featured_order` optionally controls the slider order: numbered items come first in ascending order, followed by unnumbered items alphabetically by title. Equal numbers are resolved alphabetically by title. This is separate from `nav_order`, which controls navigation.

```yaml
---
title: SolidGround IV
featured: true
featured_order: 10
featured_image: /images/solidgroundiv-logo.png
---
```

The optional `featured_image` overrides `image` or `index_image`, followed by section-specific defaults when applicable. `config/featured-slider.cfg` controls presentation (such as `autoplay_interval`), not item selection or ordering. Legacy `config/featured.cfg`, if present, still takes precedence in the current generator and should be removed when using front-matter selection.

## Download links

Use `{download}` immediately after a Markdown link when the browser should save
the linked file rather than navigate to it:

```md
[Download article template](/images/templates/artikel_NL.md){download}
```

This generates an HTML anchor with the `download` attribute. Use a same-origin
file URL for predictable browser behavior. A normal `[label](url)` link still
navigates to the target. No inline HTML is required.

## Documentation rule for new authoring syntax

Whenever a Markdown token, extension, or authoring syntax is introduced or
changed, update **all three** in the same change: this `AUTHORING.md`, the
**Schrijven voor deze site → Schrijven en publiceren** guide, and the
**Componenten-showcase** with a working example and its Markdown source.
Keep the Dutch and English authoring guide versions aligned.

## Social-media drafts

The optional `teaser` front-matter field is the preferred text for **Prepare Social Media**.
If it is absent or blank, `summary` is used; if both are absent, the first 150
characters of readable article text are used (cut at a word boundary).

Use MCM **Prepare Social Media** to select one published article from the
repository. This creates `post.txt`, `source.txt`, and (where provided locally)
`image.*` under the configured Social Media Output directory, outside Git.
Review and post the text yourself. The tool never publishes to social networks.
Existing drafts are not overwritten; remove or rename an older draft to regenerate.

```yaml
teaser: "A short, compelling introduction for social media."
```

## Recursieve navigatie en private content

De zijbalk wordt opgebouwd uit directories en de `title`-metadata van Markdown-pagina’s. Een `index_NL.md` of `index_EN.md` is optioneel; zonder index kan een directory een uitklapbare groep zijn. Klik op het pijltje om uit te klappen en op een bestaande indexpaginatitel om te navigeren. De actieve route wordt uitgeklapt. `order` sorteert siblings en `config/navigation.cfg` ordent de hoofdsecties.

`hidden: true` op een gewone pagina verbergt alleen die pagina in de navigatie; op een sectie-index (`index_NL.md` of `index_EN.md`) verbergt het de **hele sectie inclusief onderliggende menu-items**. Met `?ShowHidden` in de URL worden verborgen pagina’s en complete verborgen secties tijdelijk zichtbaar in de navigatie. De pagina’s blijven ook zonder deze optie via hun URL bereikbaar; dit is geen toegangsbeveiliging. `private: true` geeft aan dat server-side bescherming vereist is. De generator weigert publicatie van een `private` pagina buiten de in `config/site.cfg` ingestelde `protected_prefixes`. Die instelling beschermt zelf niets: configureer en test authenticatie op de daadwerkelijke webserver. `draft: true` blijft los daarvan buiten de publieke generatie.
