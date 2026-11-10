# ==================================================================================
# SolidGroundUX - Web Content Manager Authoring
# ----------------------------------------------------------------------------------
# Metadata:
#   Version     : 2.2
#   Build       : 2631102
#   Checksum    : 1fa593cc8aec378726259aa9ad0196bd731d7c46b72386f26ca0a0a28357922b
#   Source      : web-content-manager_preface.sh
#   Type        : documentation
#   Title       : Markdown Repository to Website
#   Group       : Modules
#   Subgroup    : Web Content Management
#   Purpose     : Page preface
#
# Attribution:
#   Developers  : Mark Fieten
#   Company     : Testadura Consultancy
#   Client      : -
#   Copyright   : © 2025 - 2026 Testadura Consultancy
#   License     : Licensed under the Testadura Non-Commercial License (TD-NC) v1.1.
# ==================================================================================
# -- From Markdown repository to published website -----------------------------------
#
# The Web Content Manager turns a **configured Markdown website repository** into
# a complete **static HTML website**. It accepts an authored site, with or without
# incoming material, or the Markdown repository produced by the documentation
# bundle generator. Generating HTML and deploying it are deliberately separate
# operations; the published website does not run Python.
#
# ![Markdown Repository to Website - An authored website or generated documentation repository is converted into static HTML, with optional publication through SSH and rsync.](/assets/mcm-markdown-to-html.png)
#
# `OR` is intentional: the documentation generator does **not** inject its
# Markdown into an existing authored website. Select whichever repository
# should become the website source, or curate a combined source explicitly.
#
# -- The website source and incoming-content boundary --------------------------------
#
# A WCM source repository typically contains `content/`, `config/`, `templates/`,
# `css/` and `images/`, with `incoming/` for optional staged submissions.
# `webcontent/content.py` discovers pages and site configuration, while
# `incoming_*.py` and `ingestion.py` handle review, conflict checks and archival.
# Incoming files are **not published directly**. After review and ingestion they
# become canonical content in the selected repository. Pages may also be edited
# directly; an Incoming transfer is not required to generate a website.
#
# -- Validation, generation and review ------------------------------------------------
#
# The Management Console uses `manage-web-content.sh` to invoke the Python
# `webcontent/cli.py` commands. Validation checks source structure and links.
# `generator.py` discovers navigable content, `markdown.py` renders Markdown and
# supported `td-` components, and `templates.py` composes the HTML page templates.
# The output includes HTML, navigation and static assets; public builds also
# produce `sitemap.xml` and `robots.txt`, with RSS when enabled.
#
# Preview builds may include unpublished pages, and belong in an independently
# protected output directory. Public generation omits draft/preview-only pages.
# Both outputs can be inspected locally **without publishing**. Generation never
# copies files to a remote web server and never commits source changes to Git.
#
# -- Publishing profiles and serving -----------------------------------------------
#
# **Publish website** deploys an already generated *public HTML directory*. The
# Markdown source is never copied to hosting. **Manage publishing profiles**
# allows multiple websites, each with multiple named destinations. The chosen
# destination is independent from the current generation configuration.
# The **Manage publishing profiles** menu shows the selected profile and website
# as yellow Framework labeled values between the title bar and View group,
# restored from saved selection on entry and refreshed after each action.
# **List profiles** provides a read-only summary of all websites and destinations,
# including each destination's last successful publication date. **View profile**
# displays the individual settings without changing the selected destination.
# The profile manager uses the standard Framework menu renderer, with consecutive
# selections: **View** (1-3: list, view, test), **Manage** (4-7: select, create,
# modify, delete), and **Preview** (8-9: start/stop local server). Its screen
# is cleared and redrawn after each action. Each completed menu action returns
# after one interruptible auto-continue dialog; no extra Enter prompt or
# numeric Exit item is shown (Q = Back).
# **Test connection** and **Delete** operate on the selected profile; deletion
# still requires explicit confirmation. Viewing another profile does not select it.
# **Test connection** checks local source/target access, SSH authentication plus
# rsync and remote directory permissions, or FTP/FTPS/SFTP directory listing.
# This is a read-only connection check: it does not upload files, create remote
# directories, start a local server or provision Nginx/DNS. SSH tests require a
# previously trusted host key and batch-mode authentication; FTP/SFTP testing
# requires the hosting account to permit directory listing.
#
# Available publication methods:
#
# | Method | Destination | Web server management |
# | --- | --- | --- |
# | Local preview | Local directory synchronized with rsync | No; optional Python HTTP server |
# | SSH / rsync | Remote directory, optionally an existing Nginx document root | Optional Nginx/DNS management |
# | FTP / FTPS | External hosting account with credentials in `~/.netrc` | None |
# | SFTP | External hosting via SSH credentials | None |
#
# **Update** transfers additions and changes; **Mirror** also removes files
# absent from the generated output and requires interactive confirmation.
# External FTP/FTPS/SFTP publishing uses Update only. A publishing dry-run
# reviews the planned rsync changes without transferring files. Only successful
# real publication updates that destination's last-publication timestamp.
#
# After local publication, WCM optionally offers **Start local webserver**. The
# preview server binds to `127.0.0.1`, tries port 8080 by default and continues
# with 8081, 8082, etc. until a free port is found. WCM displays the resulting
# `http://localhost:<port>/` address. A WCM-owned server can be reused or
# stopped from profile management without terminating unrelated processes.
# **Start local preview** can also launch the HTTP server separately for an
# already published local-preview destination, without copying any website files.
#
# Non-interactive publication uses a selected profile, or an explicit one:
#
# ```bash
# manage-web-content.sh --action manage-publishing-profiles
# manage-web-content.sh --action publish --profile Testadura-HQ
# manage-web-content.sh --action publish --profile Development --auto
# manage-web-content.sh --action publish --profile Development --dryrun
# ```
#
# Framework stores structured, versioned WCM profile data in the user's
# `~/.config/solidgroundux/deployment-profiles/wcm.json`. Existing ordinary
# release 2.2.2631102 publishing settings are imported once; obsolete Base64
# publishing profiles are not imported. Passwords are not stored in profiles.
#
# `publish-web-content.sh` also provides server-site publishing operations.
# Generating static HTML, transferring that HTML, and provisioning a web server
# remain distinct actions. Nginx serves the final result on managed hosts;
# the Python renderer never runs per normal website HTTP request.
#
# -- Responsibilities by component ---------------------------------------------------
#
# | Component | Responsibility | Output / hand-off |
# | --- | --- | --- |
# | Markdown site repository | Canonical `content/`, `config/`, templates and assets | Input to WCM |
# | Incoming / ingestion | Stage, review, validate and archive submitted changes | Updated canonical Markdown source |
# | `webcontent/content.py` | Discover content and site configuration | Navigable page model |
# | `webcontent/markdown.py` | Render Markdown and supported `td-` components | HTML fragments |
# | `webcontent/templates.py` | Apply the site page templates | Complete HTML pages |
# | `webcontent/generator.py` | Coordinate HTML/site-asset generation | Public or preview output directory |
# | `manage-web-content.sh` | Provide the MCM operator workflow | Validation and generation actions |
# | `manage-web-content.sh` | Select a publishing profile and deploy built HTML | Local or hosted static website |
# | Nginx | Serve generated HTML and assets | Browser response |
#
# -- Markdown authoring components ---------------------------------------------------
#
# WCM extends standard Markdown with explicit `td-` components, used only when
# ordinary Markdown is insufficient. Component blocks start with `:::` and end
# with a matching `:::`. The short reference below precedes working examples.
#
# | Construct | Function | Example |
# | --- | --- | --- |
# | `td-grid`, `td-tile` | Responsive groups of content tiles | `::: td-grid` |
# | `td-gallery` | Horizontally sliding image gallery | `::: td-gallery` |
# | `td-gallery-compact` | Smaller gallery items, useful in reference pages | `::: td-gallery td-gallery-compact` |
# | `td-note` | Informational callout | `::: td-note` |
# | `td-warning` | Warning callout | `::: td-warning` |
# | `td-technical` | Technical explanation | `::: td-technical` |
# | `.td-image-product` | Product image presentation | `![Image](/assets/mcm-overview.png){.td-image-product}` |
# | `{download}` | Request a browser download for a linked resource | `[Template](...){download}` |
#
# -- Tiles in a Responsive Grid -----------------------------------------------------
#
# Use `td-grid` to arrange related tiles responsively. Each child `td-tile` becomes
# an individual tile. The grid places tiles next to one another when there is room
# and stacks them on narrow screens.
#
#     ::: td-grid
#     ::: td-tile
#     ### SolidGroundUX
#
#     Linux/Bash framework for consistent management and provisioning workflows.
#     :::
#
#     ::: td-tile
#     ### SolidGround IV
#
#     Application and integration framework.
#     :::
#     :::
#
# -- Sliding Image Gallery ----------------------------------------------------------
#
# Use `td-gallery` for a horizontally sliding image gallery. The gallery uses
# native horizontal scrolling and scroll snapping, so it works with a mouse,
# trackpad, or touch without requiring JavaScript. Add `td-gallery-compact`
# for a smaller example (ordinary galleries retain their regular width).
#
# ::: td-gallery td-gallery-compact
# ![First image](/assets/mcm-overview.png)
#
# ![Second image](/assets/mcm-architecture.png)
#
# ![Third image](/assets/mcm-module-lifecycle.png)
# :::
#
# -- Callouts -----------------------------------------------------------------------
#
# The renderer provides several callout components for content that needs visual
# emphasis without leaving Markdown authoring.
#
#     ::: td-note
#     A normal note.
#     :::
#
#     ::: td-warning
#     Something requiring attention.
#     :::
#
#     ::: td-technical
#     Technical detail.
#     :::
#
# -- Inline and Image Classes -------------------------------------------------------
#
# Existing `td-` classes can be applied directly where the Markdown syntax supports
# attributes.
#
#     [Identify]{.td-green}
#
#     ![Product image](/assets/mcm-new-console-module.png){.td-image-product}
#
# Keep custom component names under the configured `td-` prefix. Validation reports
# a referenced `td-` class that does not exist in the site CSS.
#
# -- Featured Content ---------------------------------------------------------------
#
# The homepage Featured slider is driven by Markdown front matter when the
# legacy `www/config/featured.cfg` is absent:
#
#     ---
#     title: SolidGround IV
#     featured: true
#     featured_order: 10
#     featured_image: /images/solidgroundiv-logo.png
#     ---
#
# `featured: true` includes a page; `featured: false` (or omission) excludes it.
# Pages with `featured_order` appear first, ascending by number. Unnumbered
# featured pages follow alphabetically by title; ties are alphabetical too.
# `nav_order` is independent and controls navigation, not Featured ordering.
# The slider's `autoplay_interval` is configured in `featured-slider.cfg`.
# Legacy `featured.cfg`, when present, remains authoritative; remove it to use
# front-matter selection.
#
# ==================================================================================

# -- Publishing: drafts, previews, SEO, feeds ---------------------------------------
#
# Public is the default: only published pages are generated. Preview builds
# include `status: draft` and `status: preview` pages and must be written to a
# separate, access-controlled output directory. `noindex` is not access control.
# Use `status: published` or omit status for public pages. Legacy `draft: true`
# remains accepted. The public component showcase stays published; authors can
# set `status: preview` for material meant only for private preview builds.
#
#     python3 -m webcontent.cli generate --source ./www --output ./public
#     python3 -m webcontent.cli generate --source ./www --output ./private-preview --mode preview
#     python3 -m webcontent.cli generate --source ./www --output ./public --rss
#
# `published: YYYY-MM-DD` determines article date and chronological sorting;
# legacy `date:` remains a fallback. A filesystem creation date is not stable
# across Git clones and ingestion, so there is no automatic creation-date fallback.
#
# Public builds generate sitemap.xml and robots.txt from published routes only,
# plus canonical, Open Graph and social-card metadata. `description` overrides
# the summary for SEO. A hero image is used for sharing previews when present.
# Optional RSS produces rss.xml from dated, published articles only.
# The generation result includes skipped_pages, broken_links, sitemap_generated,
# rss_generated and non-fatal local link warnings.

# -- Authoring workflows: source and publication ------------------------------------
#
# The website source is the configured repository root (the directory containing
# `content/`, `config/`, `templates/`, `css/` and `images/`). It is not the
# generated public directory. MCM changes files in that source tree; it never
# performs a Git commit or automatically posts to a social network.
#
# Daily authoring sequence:
#
#     Write Markdown -> Incoming -> Review & Ingest Incoming -> Generate website
#         -> Preview/review -> Publish -> Commit to Git when ready
#
# Keep an offline or Git-backed copy of the source before bulk operations.
# Use NL/EN filename suffixes consistently, e.g. `voorbeeld_NL.md`.
#
# -- How to add an article -----------------------------------------------------------
#
# 1. Start from the downloadable article template under **Schrijven voor deze site**,
#    or create a Markdown file with `---` front matter.
# 2. Supply a title, target parent section, route slug and language. For example:
#
#     ---
#     title: "Een praktijkverhaal"
#     summary: "Een korte omschrijving voor overzichten"
#     teaser: "Een prikkelende introductie voor sociale media"
#     kind: article
#     parent: /tales-from-the-trenches/
#     slug: een-praktijkverhaal
#     language: NL
#     draft: true
#     featured: false
#     ---
#
#     # Een praktijkverhaal
#
#     De tekst van het verhaal begint hier.
#
# 3. Upload Markdown or a ZIP package into Incoming, or use **Retrieve Incoming**
#    / **Import local files to Incoming**. Choose **Review and ingest Incoming
#    package**, inspect the proposed destinations and confirm. The target
#    section must already exist, or the package must contain its section index.
# 4. Successful ingest places the canonical content under `content/` and moves
#    the processed package into `incoming/archive/`. Conflicting or failed
#    packages remain in Incoming. Ingest does not generate or publish the site.
# 5. Generate a preview, inspect the page, and publish only when ready.
#
# `kind`, `parent`, `slug` and `language` are placement hints for Incoming;
# the canonical file uses its location and filename instead of retaining them.
# For an existing article, edit its source directly or use **Edit page metadata**
# for a front-matter-only change. Ingest refuses to overwrite existing pages.
#
# -- How to add a section ------------------------------------------------------------
#
# A section is a directory with a language-specific `index_NL.md` or `index_EN.md`.
# Create it through Incoming by setting `kind: section` and choosing an existing
# parent section, for example:
#
#     ---
#     title: "Een nieuwe rubriek"
#     summary: "Waarover deze rubriek gaat"
#     kind: section
#     parent: /
#     slug: nieuwe-rubriek
#     language: NL
#     draft: true
#     ---
#
#     # Een nieuwe rubriek
#
#     Introductie van de rubriek.
#
# Ingest creates `content/nieuwe-rubriek/index_NL.md` after validation.
# Create an EN variant separately if required. Creating a section does not
# automatically add it to the sidebar navigation: update `config/navigation.cfg`
# if it should have its own navigation entry. Validate the links afterwards.
#
# -- How to edit, move or remove content ---------------------------------------------
#
# **Edit page metadata**: browse to a page and stage one or more changes.
# Select an existing field to edit, add a new field, or choose **Remove metadata
# field** to delete an explicitly stored key so its default applies again.
# Enter accepts the current value; `:clear` sets a text field to an empty string
# but does **not** remove it. Choose **Save all staged changes** to write the
# batch atomically, or discard it. The Markdown body remains untouched.
#
# **Move / rename page**: select a non-index page, choose an existing destination
# section and a new slug, then confirm. The current implementation moves one
# language variant at a time and does not rewrite incoming links. Regenerate
# and run link validation; update any links to its previous URL manually.
#
# **Delete page**: choose the MCM delete action and select the target page or
# section. Review the impact preview carefully, including child pages and
# translations, then confirm. Deleted sources are archived for recovery.
# To remove a section, use the section deletion choice; inspect descendants and
# language variants before confirming. Remove obsolete sidebar navigation entries
# manually from `config/navigation.cfg`, then regenerate and validate.
#
# -- Publication, Featured and social-media preparation ------------------------------
#
# Keep `draft: true` while writing; preview builds can show unpublished content.
# Switch to `draft: false` (or an equivalent supported published status) before
# generating the public site. The renderer supports metadata such as `title`,
# `summary`, `featured`, `featured_image`, and `teaser`.
#
# Use `featured: true` and optional `featured_order` in the page front matter.
# Numbered featured pages sort first, then unnumbered pages alphabetically.
# A legacy `featured.cfg`, if present, still overrides the Markdown selection.
# The Featured carousel's autoplay interval is a slider setting, not metadata.
#
# **Prepare social media drafts** selects one existing published article from
# the repository and writes an editable file to the configured social output
# directory, outside the Git checkout. The text preference is `teaser`, then
# `summary`, then a plain-text excerpt (default 150 characters) from the body.
# Review and publish to the external platform yourself; no automatic posting.
#
# -- Downloads and authoring reference -----------------------------------------------
#
# The website's **Schrijven voor deze site** section provides NL/EN article,
# product and section templates, the authoring guide and the component showcase.
# Add `{download}` immediately after a normal Markdown link to request a browser
# download instead of navigation:
#
#     [Download artikeltemplate](/assets/templates/artikel_NL.md){download}
#
# For every new Markdown token or authoring component, update the repository's
# `AUTHORING.md`, both website-language authoring guides and the component
# showcase with a working source example in the same change.
# ==================================================================================
