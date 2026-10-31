# Testadura website authoring

Normal website content is Markdown. Authors should not need to write HTML for
ordinary pages or common layouts. This guide describes **authoring a website
source**, not source-repository documentation extraction or publication of HTML.

The WebContent renderer supports standard Markdown plus a small Testadura
component extension. Component blocks start with `::: <class>` and end with
`:::`. Blocks may be nested.

## Website source and publication stages

A regular WWW website uses **Generate Website → Publish Website**. A documentation
website first runs **Assemble Markdown** using MCM Documentation Bundles; that
produces the website Markdown source consumed by the same generator. Both kinds
of website use the same HTML publisher. Publishing never reads the original
source repositories.

A website source has `config/site.cfg`, a `content/` tree, and the assets,
templates and stylesheets used by the generator. The homepage is supplied by a
root-level `*_Index_XX.md` file for the configured default language, for example
`content/Site_Index_NL.md`; the filename stem is site-specific. Section landing
pages use `index_NL.md` (and optional other language variants). Both contain
ordinary Markdown with YAML front matter. To omit a subtree from discovery,
place a `.ignore` file in that directory.

For the operator workflow (HTML source directory, destination server, website
selection, Update/Mirror, HTTPS and certificate export), see
[PUBLISHING.md](PUBLISHING.md).

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

De zijbalk wordt opgebouwd uit directories en de `title`-metadata van Markdown-pagina’s. Een `index_NL.md` of `index_EN.md` is optioneel; zonder index kan een directory een uitklapbare groep zijn. Klik op het pijltje om uit te klappen en op een bestaande indexpaginatitel om te navigeren. De actieve route wordt uitgeklapt. `nav_order` (met `order` als terugval) sorteert de navigatie. Hoofdsecties
worden uit sectie-indexen afgeleid; `config/navigation.cfg` stuurt die
navigatie in de huidige generator niet aan.

`hidden: true` op een gewone pagina verbergt alleen die pagina in de navigatie; op een sectie-index (`index_NL.md` of `index_EN.md`) verbergt het de **hele sectie inclusief onderliggende menu-items**. Met `?ShowHidden` in de URL worden verborgen pagina’s en complete verborgen secties tijdelijk zichtbaar in de navigatie. De pagina’s blijven ook zonder deze optie via hun URL bereikbaar; dit is geen toegangsbeveiliging. `private: true` geeft aan dat server-side bescherming vereist is. De generator weigert publicatie van een `private` pagina buiten de in `config/site.cfg` ingestelde `protected_prefixes`. Die instelling beschermt zelf niets: configureer en test authenticatie op de daadwerkelijke webserver. `draft: true` blijft los daarvan buiten de publieke generatie.

## Sectie-indexen en expliciete inhoudsoverzichten

Een sectie is een map met een `index_NL.md` (of andere taalvariant). De
sectie-index gebruikt `template: page`, net als een gewone inhoudspagina.
De generator voegt **niet automatisch** een overzicht van onderliggende
pagina’s toe. Plaats de index expliciet op de gewenste plek:

```markdown
::: td-index
:::
```

`td-index` toont de direct onderliggende gepubliceerde pagina's. Met
`type=cards`, `type=list` of `type=articles` kies je de presentatie;
`sort=newest` sorteert op publicatiedatum (nieuwste eerst). Standaard
kiest de generator kaarten voor maximaal vier items en anders een lijst.
Concepten worden in de publieke generatie niet opgenomen.

```markdown
::: td-index type=articles sort=newest
:::
```

Voor een gewone pagina zonder indexblok verschijnt geen automatische lijst.
Het oude `listing`-template is vervallen; bestaande sectie-indexen worden
`template: page` met een expliciet `td-index`-blok.

## Afbeelding naast tekst, featured-fit en uitklappen

Met `td-image-text` plaats je een afbeelding naast gewone Markdown.
Geef het afbeeldingspad direct op in de openingsregel. Standaard staat
het plaatje links; voeg `right` toe voor rechts. Op smalle schermen komt
het plaatje boven de tekst. Het hele plaatje blijft zichtbaar.

```markdown
::: td-image-text /images/testadura-logo.png
### Een verhaal

Tekst naast de afbeelding, inclusief **Markdown** en meer alinea's.
:::

::: td-image-text /images/testadura-logo.png right
Ook rechts is mogelijk.
:::
```

Een featured-kaart kan per pagina de volledige afbeelding tonen in plaats
van uitsnijden: frontmatter `featured_image_fit: contain` (standaard `cover`).

`td-details` is een toegankelijk uitklapblok op basis van HTML `details`;
de inhoud is gewone Markdown. Schrijf `::: td-details Toelichting` en sluit
af met `:::`. Gebruik `::: td-details open Toelichting` voor standaard open.


### Afmetingen van afbeeldingen

Bij gewone Markdown-afbeeldingen (ook binnen `td-grid`, `td-tile`, `td-gallery` en `td-slider`) kun je optioneel pixelafmetingen toevoegen:

```markdown
![Logo](/images/testadura-logo.png){width=200}
![Diagram](/images/diagram.png){width=400 height=240}
```

Bij een afbeelding naast tekst gebruik je dezelfde parameters in de openingsregel:

```markdown
::: td-image-text /images/testadura-logo.png width=200
Tekst naast het logo.
:::

::: td-image-text /images/testadura-logo.png right width=200 height=150
Tekst links van het logo.
:::
```

Afmetingen zijn positieve pixels (`1` tot `10000`). Zonder parameters blijft de standaardopmaak behouden. Met één afmeting blijft de beeldverhouding behouden; met twee afmetingen past de afbeelding zonder bijsnijden in het opgegeven vlak. De breedte wordt begrensd door de beschikbare schermruimte. Bij galerijen en sliders blijft de containerlay-out gehandhaafd; afmetingen gelden voor de afbeelding, niet voor de kaart of de schuifpositie. Featured-afbeeldingen behouden afzonderlijk `featured_image_fit: cover|contain`.

## Documentation bundle composition

The Documentation Bundles manager in MCM assembles source documentation into a WCM
Markdown site. Bundle introductions and closing material are no longer part of a
special Chapter 0. The output order is:

1. Bundle prefaces (**Introduction**)
2. Product chapters, each with its own prefaces, ordinary pages and epilogues
3. Bundle epilogues (**Closing Remarks**)
4. Appendices

The **Manage bundle documents** action accepts three roles: `preface`, `epilogue`,
and `page`. Preface and epilogue lists can be set independently to **auto**,
**manual** or **none**. An explicit list, including an empty one, takes precedence
over automatic discovery. `page` entries are always explicitly selected and are
assigned to a target product, and optionally a group and subgroup. An ordinary
page can be positioned as a section preface or epilogue when adding it.

Automatic discovery searches the participating products' `doc-sources`
directories for `.md`, `.sh` and `.py` sources. For bundle ID `solidgroundux-full`:

- `solidgroundux-full_preface.md` and `solidgroundux-full_architecture_preface.sh`
  take precedence over generic `bundle_preface.md` and
  `bundle_architecture_preface.sh`.
- The same independent convention applies to `*_epilogue` files.
- When no bundle-specific files exist, generic `bundle_*_preface` or
  `bundle_*_epilogue` files are used.
- Automatic files are ordered by optional `nav_order` metadata, then by
  filename. Explicit lists use their saved order.

The source filename is unrestricted for **explicit** selections. A selected
source may come from any repository, including the source repository for another
bundle. A file is identified by its full source path, not merely its basename.
The same source file cannot appear twice in a generated bundle.

Structured `.sh`/`.py` documentation is converted from its comment markers.
Explicitly selected `.md` files are **copied byte-for-byte**, preserving authored
front matter and prose. Navigation order and inferred titles are recorded or
resolved at generation time; the generator never injects YAML into the Markdown
source. Generated websites use `config/doc-nav-orders.json` to preserve the
configured navigation order without modifying those copied files.

Saved bundles with a legacy `chapter0` value remain readable: the generator
resolves the previously selected introduction to its original source when
possible, emits that source as a bundle preface, and excludes it from its product
chapter. Selecting new bundle prefaces supersedes the legacy setting.
