# ==================================================================================
# SolidGroundUX - Web Content Manager Authoring
# ----------------------------------------------------------------------------------
# Metadata:
#   Version     : 2.1
#   Build       : 2628700
#   Checksum    : 8d8bc05bce81119cbf956b9d88c4a560bd44b657dfa95b808975c2327734916a
#   Source      : web-content-manager_preface.sh
#   Type        : documentation
#   Group       : Web Content Manager
#   Purpose     : Group preface
#
# Attribution:
#   Developers  : Mark Fieten
#   Company     : Testadura Consultancy
#   Client      : -
#   Copyright   : © 2025 - 2026 Testadura Consultancy
#   License     : Licensed under the Testadura Non-Commercial License (TD-NC) v1.1.
# ==================================================================================
# - Web Content Manager Authoring ---------------------------------------------------
#
# > Normal website content is written in Markdown. Authors should not need to write
# > HTML for ordinary pages or common layouts.
#
# > The Web Content Manager renderer supports standard Markdown plus a small
# > Testadura component extension. Component blocks start with `::: <class>` and end
# > with `:::`. Component blocks may be nested.
#
# -- Tiles in a Responsive Grid -----------------------------------------------------
#
# > Use `td-grid` to arrange related tiles responsively. Each child `td-tile` becomes
# > an individual tile. The grid places tiles next to one another when there is room
# > and stacks them on narrow screens.
#
# >     ::: td-grid
# >     ::: td-tile
# >     ### SolidGroundUX
# >
# >     Linux/Bash framework for consistent management and provisioning workflows.
# >     :::
# >
# >     ::: td-tile
# >     ### SolidGround IV
# >
# >     Application and integration framework.
# >     :::
# >     :::
#
# -- Sliding Image Gallery ----------------------------------------------------------
#
# > Use `td-gallery` for a horizontally sliding image gallery. The gallery uses
# > native horizontal scrolling and scroll snapping, so it works with a mouse,
# > trackpad, or touch without requiring JavaScript.
#
# >     ::: td-gallery
# >     ![First image](/images/example-one.png)
# >
# >     ![Second image](/images/example-two.png)
# >
# >     ![Third image](/images/example-three.png)
# >     :::
#
# -- Callouts -----------------------------------------------------------------------
#
# > The renderer provides several callout components for content that needs visual
# > emphasis without leaving Markdown authoring.
#
# >     ::: td-note
# >     A normal note.
# >     :::
#
# >     ::: td-warning
# >     Something requiring attention.
# >     :::
#
# >     ::: td-technical
# >     Technical detail.
# >     :::
#
# -- Inline and Image Classes -------------------------------------------------------
#
# > Existing `td-` classes can be applied directly where the Markdown syntax supports
# > attributes.
#
# >     [Identify]{.td-green}
#
# >     ![Product image](/images/product.png){.td-image-product}
#
# > Keep custom component names under the configured `td-` prefix. Validation reports
# > a referenced `td-` class that does not exist in the site CSS.
#
# -- Featured Content ---------------------------------------------------------------
#
# > The home-page Featured slider is configured in `www/config/featured.cfg` when
# > that file exists; its entries are authoritative. Without it, pages marked
# > `featured: true` in front matter are selected. Titles and summaries come from
# > the page metadata, not duplicated in the slider configuration.
#
# >     [solidgroundux]
# >     order = 10
# >     route = /solidgroundux/
# >     image = /images/solidgroundux-logo.png
#
# > Add, remove, or reorder entries to change the configured slider. Routes are language-neutral.
# > When a configured page has no translation in the language being generated, that
# > Featured tile is omitted for that language until the translation exists.
# ==================================================================================

# -- Publishing: drafts, previews, SEO, feeds ---------------------------------------
#
# > Public is the default: only published pages are generated. Preview builds
# > include `status: draft` and `status: preview` pages and must be written to a
# > separate, access-controlled output directory. `noindex` is not access control.
# > Use `status: published` or omit status for public pages. Legacy `draft: true`
# > remains accepted. The public component showcase stays published; authors can
# > set `status: preview` for material meant only for private preview builds.
# >
# >     python3 -m webcontent.cli generate --source ./www --output ./public
# >     python3 -m webcontent.cli generate --source ./www --output ./private-preview --mode preview
# >     python3 -m webcontent.cli generate --source ./www --output ./public --rss
# >
# > `published: YYYY-MM-DD` determines article date and chronological sorting;
# > legacy `date:` remains a fallback. A filesystem creation date is not stable
# > across Git clones and ingestion, so there is no automatic creation-date fallback.
# >
# > Public builds generate sitemap.xml and robots.txt from published routes only,
# > plus canonical, Open Graph and social-card metadata. `description` overrides
# > the summary for SEO. A hero image is used for sharing previews when present.
# > Optional RSS produces rss.xml from dated, published articles only.
# > The generation result includes skipped_pages, broken_links, sitemap_generated,
# > rss_generated and non-fatal local link warnings.

# -- Authoring workflows: source and publication ------------------------------------
#
# > The website source is the configured repository root (the directory containing
# > `content/`, `config/`, `templates/`, `css/` and `images/`). It is not the
# > generated public directory. MCM changes files in that source tree; it never
# > performs a Git commit or automatically posts to a social network.
# >
# > Daily authoring sequence:
# >
# >     Write Markdown -> Incoming -> Ingest Markdown -> Generate website
# >         -> Preview/review -> Publish -> Commit to Git when ready
# >
# > Keep an offline or Git-backed copy of the source before bulk operations.
# > Use NL/EN filename suffixes consistently, e.g. `voorbeeld_NL.md`.
#
# -- How to add an article -----------------------------------------------------------
#
# > 1. Start from the downloadable article template under **Schrijven voor deze site**,
# >    or create a Markdown file with `---` front matter.
# > 2. Supply a title, target parent section, route slug and language. For example:
# >
# >     ---
# >     title: "Een praktijkverhaal"
# >     summary: "Een korte omschrijving voor overzichten"
# >     teaser: "Een prikkelende introductie voor sociale media"
# >     kind: article
# >     parent: /tales-from-the-trenches/
# >     slug: een-praktijkverhaal
# >     language: NL
# >     draft: true
# >     featured: false
# >     ---
# >
# >     # Een praktijkverhaal
# >
# >     De tekst van het verhaal begint hier.
# >
# > 3. Save the file in the configured Incoming directory, then choose **Ingest
# >    Markdown** in Web Content Management. Inspect and confirm the detected
# >    section, language and filename. The target section must already exist.
# > 4. Successful ingest places the canonical Markdown in `content/` and archives
# >    the incoming original. It does not generate or publish the website.
# > 5. Generate a preview, inspect the page, and publish only when ready.
# >
# > `kind`, `parent`, `slug` and `language` are placement hints for Incoming;
# > the canonical file uses its location and filename instead of retaining them.
# > For an existing article, edit its source directly or use **Edit page metadata**
# > for a front-matter-only change. Ingest refuses to overwrite existing pages.
#
# -- How to add a section ------------------------------------------------------------
#
# > A section is a directory with a language-specific `index_NL.md` or `index_EN.md`.
# > Create it through Incoming by setting `kind: section` and choosing an existing
# > parent section, for example:
# >
# >     ---
# >     title: "Een nieuwe rubriek"
# >     summary: "Waarover deze rubriek gaat"
# >     kind: section
# >     parent: /
# >     slug: nieuwe-rubriek
# >     language: NL
# >     draft: true
# >     ---
# >
# >     # Een nieuwe rubriek
# >
# >     Introductie van de rubriek.
# >
# > Ingest creates `content/nieuwe-rubriek/index_NL.md` after validation.
# > Create an EN variant separately if required. Creating a section does not
# > automatically add it to the sidebar navigation: update `config/navigation.cfg`
# > if it should have its own navigation entry. Validate the links afterwards.
#
# -- How to edit, move or remove content ---------------------------------------------
#
# > **Edit page metadata**: browse to a page, select the field, change its value,
# > and finish editing. Enter accepts the current value; use `:clear` to empty a
# > supported text field. This action leaves the Markdown body untouched.
# >
# > **Move / rename page**: select a non-index page, choose an existing destination
# > section and a new slug, then confirm. The current implementation moves one
# > language variant at a time and does not rewrite incoming links. Regenerate
# > and run link validation; update any links to its previous URL manually.
# >
# > **Delete page**: choose the MCM delete action and select the target page or
# > section. Review the impact preview carefully, including child pages and
# > translations, then confirm. Deleted sources are archived for recovery.
# > To remove a section, use the section deletion choice; inspect descendants and
# > language variants before confirming. Remove obsolete sidebar navigation entries
# > manually from `config/navigation.cfg`, then regenerate and validate.
#
# -- Publication, Featured and social-media preparation ------------------------------
#
# > Keep `draft: true` while writing; preview builds can show unpublished content.
# > Switch to `draft: false` (or an equivalent supported published status) before
# > generating the public site. The renderer supports metadata such as `title`,
# > `summary`, `featured`, `featured_image`, and `teaser`.
# >
# > Featured selection depends on site configuration: `featured.cfg` takes priority
# > when present; otherwise `featured: true` is used. The Featured carousel's
# > autoplay interval is a slider setting, not article metadata.
# >
# > **Prepare social media drafts** selects one existing published article from
# > the repository and writes an editable file to the configured social output
# > directory, outside the Git checkout. The text preference is `teaser`, then
# > `summary`, then a plain-text excerpt (default 150 characters) from the body.
# > Review and publish to the external platform yourself; no automatic posting.
#
# -- Downloads and authoring reference -----------------------------------------------
#
# > The website's **Schrijven voor deze site** section provides NL/EN article,
# > product and section templates, the authoring guide and the component showcase.
# > Add `{download}` immediately after a normal Markdown link to request a browser
# > download instead of navigation:
# >
# >     [Download artikeltemplate](/images/templates/artikel_NL.md){download}
# >
# > For every new Markdown token or authoring component, update the repository's
# > `AUTHORING.md`, both website-language authoring guides and the component
# > showcase with a working source example in the same change.
# ==================================================================================
