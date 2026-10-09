# ==================================================================================
# SolidGroundUX - Web Content Manager Authoring
# ----------------------------------------------------------------------------------
# Metadata:
#   Version     : 2.1
#   Build       : 0
#   Checksum    : -
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
# > The home-page Featured slider is curated in `www/config/featured.cfg`. Authors do
# > not duplicate titles or summaries there; the generator reads those from the target
# > page metadata in the active language.
#
# >     [solidgroundux]
# >     order = 10
# >     route = /solidgroundux/
# >     image = /images/solidgroundux-logo.png
#
# > Add, remove, or reorder sections to change the slider. Routes are language-neutral.
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
