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
