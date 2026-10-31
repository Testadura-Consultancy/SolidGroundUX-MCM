# ==================================================================================
# SolidGroundUX MCM - Documentation Bundles and Markdown Generation
# ----------------------------------------------------------------------------------
# Metadata:
#   Version     : 2.1
#   Build       : 2627700
#   Checksum    : a2fd443bfa308d802e9a389e882d4e6f052f3c5d865af1f591b70faf11194f1e
#   Source      : mcm-documentation_preface.sh
#   Type        : documentation
#   Group       : Role Managers
#   Subgroup    : Web Content Management
#   Purpose     : Subgroup preface
#
# Attribution:
#   Developers  : Mark Fieten
#   Company     : Testadura Consultancy
#   Client      : -
#   Copyright   : © 2025 - 2026 Testadura Consultancy
#   License     : Licensed under the Testadura Non-Commercial License (TD-NC) v1.1.
# ==================================================================================
# - Documentation Bundles and Markdown Generation ------------------------------------
#
# > The Management Console Modules (MCM) own documentation bundle management and
# > source-comment-to-Markdown generation. These tools are not part of the SDK's
# > workspace utilities. The SDK supplies authoring samples and workspace support;
# > MCM maintains saved bundles and generates the documentation tree.
#
# > A bundle is a named, persistent collection of one or more source repositories.
# > Each repository has a chapter title and a source directory. Their ordering is
# > explicit and remains stable between generation runs. A bundle also records its
# > output directory, overwrite policy, and optional bundle-level documents.
#
# -- Bundle Management --------------------------------------------------------------
#
# > The `manage-bundles.sh` menu lets you create, select, configure, validate and
# > delete bundles. Its source-management menu adds, edits, reorders and removes
# > product chapters without changing their underlying repositories.
#
# > Bundle configuration is persisted as JSON beneath
# > `~/.config/solidgroundux/documentation-bundles/`. The Python bundle manager
# > (`sgnd_doc_bundles.py`) validates identifiers and paths, and writes changes
# > atomically. Validation checks that chapter sources exist and the output directory
# > is absolute and outside the source repositories.
#
# > A bundle can contain introductory and closing documents, either automatically
# > discovered by naming convention or explicitly selected from any source
# > repository. Bundle-specific `bundle-id_preface` / `bundle-id_epilogue`
# > sources take precedence over generic `bundle_preface` / `bundle_epilogue`
# > files. Explicit lists take precedence over automatic discovery, including when
# > intentionally empty. Bundle prefaces appear before product chapters; bundle
# > epilogues appear after the products and before appendices.
# >
# > Ordinary `.md` source files are copied unchanged when explicitly selected.
# > Their navigation placement is stored separately, without editing their
# > front matter. Each source document appears only once in the bundle.
# > Older saved Chapter 0 selections remain readable and are mapped back to the
# > source preface on generation when possible.
#
# -- Markdown Generation ------------------------------------------------------------
#
# > The `sgnd_doc_markdown.py` generator scans each source repository for structured
# > documentation comments, reads module metadata, and writes a navigable Markdown
# > tree. The bundle is the top level; configured products form ordered chapters;
# > source directories, groups, sections and documented functions occupy subordinate
# > levels. Empty or purely administrative sections are suppressed where possible.
#
# > Function documentation is read from `# fn:` and template declarations from
# > `# fn$`, with `# . Purpose`, `# . Arguments`, `# . Returns`, and other structured
# > field headings. Native Markdown, including fenced code blocks, is preserved.
# > The generator also processes documentation-only prefaces and epilogues.
#
# > Documentation images, templates and styles are taken from the configured
# > documentation resources and from the participating product source trees. Asset
# > filenames must not collide with different contents across products.
#
# > Markdown generation is a distinct operation from website generation. The WCM
# > converts Markdown content to a static HTML website and handles publishing,
# > including remote website synchronization and GitHub Pages. A generated Markdown
# > bundle is therefore not itself a finished HTML website.
#
# -- Module Headers -----------------------------------------------------------------
#
# > Documentation begins with the module header.
#
# > The Metadata section describes the module itself. Common fields include Version,
# > Build, Checksum, Source, Type, Group, Subgroup, and Purpose.
#
# > Version and Build identify the documented module version. Checksum can be used
# > for integrity tracking. Source identifies the original source file. Type
# > classifies the module, Group determines its primary documentation area, Subgroup
# > optionally introduces one additional grouping level, and Purpose provides a short
# > description of why the module exists.
#
# > The Attribution section describes ownership and licensing information. Common
# > fields include Developers, Company, Client, Copyright, and License.
#
# > These fields are used to generate attribution and integrity appendices, and help
# > keep generated documentation traceable back to the source files.
#
# -- Documentation Labels -----------------------------------------------------------
#
# > Structured documentation lines use a small set of labels to identify the type
# > of content being documented.
#
# > The primary labels are:
#
# >     fn:  <> Function or method documentation
# >     var: <> Variable documentation
# >     cls: <> Class documentation
# >     doc: <> General documentation
#
# > Each label can be followed by either a colon or a dollar sign.
#
# > A colon indicates a normal documentation item:
#
# >     fn:  <> Normal function or method documentation
# >     var: <> Normal variable documentation
# >     cls: <> Normal class documentation
# >     doc: <> Normal general documentation
#
# > A dollar sign indicates a template documentation item:
#
# >     fn$  <> Template function documentation
# >     var$ <> Template variable documentation
# >     cls$ <> Template class documentation
# >     doc$ <> Template general documentation
#
# > Template items are primarily intended for reusable examples and template files.
# > The renderer can treat them differently from normal framework items, depending
# > on the group or context in which they appear.
#
# > The documentation dialect is language-neutral where the host language supports the
# > same comment marker. Bash and Python both use # comments, so fn:, var:, cls:, and
# > doc: use the same syntax in both languages. Python functions and class methods both
# > use fn:; the containing cls: item supplies the class context.
# >
# > The SDK's `doc-sample.sh` illustrates these source-comment conventions and is
# > a useful authoring reference. MCM performs the actual Markdown generation.
#
# -- Sections and Structure ---------------------------------------------------------
#
# > Documentation comments can define product, module, section, subsection, and item
# > content.
#
# > Structural headings use a hyphenated hierarchy. The number of hyphens immediately
# > following the comment marker determines the heading level:
# >
# >     # - Heading      Level 1 <> primary/top-level section
# >     # -- Section     Level 2 <> section within the current level 1 heading
# >     # --- Subsection Level 3 <> subsection or paragraph-level grouping
# >
# > The hierarchy is semantic, not decorative. Peer headings at the same structural
# > level should use the same number of hyphens. In particular, top-level source
# > sections must use `# -` and should not be written as `# --` or `# ---` merely for
# > visual emphasis.
#
# > Section headers are used to group related functions, variables, configuration
# > values, or explanatory text.
#
# > This allows generated documentation to be organized as a navigable hierarchy
# > instead of a flat list of extracted comments.
#
# > Good sectioning is especially important in larger modules, where a long list of
# > functions would otherwise become difficult to read.
#
# -- Markdown Authoring -------------------------------------------------------------
#
# > Content beneath `# fn:`, `# fn$` and other documentation declarations uses
# > Markdown. Write `# . Purpose`, `# . Arguments`, `# . Returns` and `# . Usage`
# > as field headers when a function needs them. The generator turns these headers
# > into corresponding Markdown headings.
#
# > Usage samples should be fenced so the generated site can apply syntax highlighting
# > and preserve shell indentation:
# >
# >     # . Usage
# >     #   ```bash
# >     #   sgnd-doc-example --help
# >     #   ```
#
# > Write ordinary Markdown tables with pipe-separated cells, not the historical
# > `::`-separated renderer table dialect. Markdown links, images and lists work in
# > both documentation-only sources and function comments. The previous intermediate
# > HTML renderer's style-hint tokens and alignment markers are not part of the
# > current Markdown bundle generator's contract.
#
# -- Images -------------------------------------------------------------------------
#
# > Source comments can reference images in Markdown or image declarations. Assets
# > are copied from the participating product's `doc-sources/assets` directory and
# > other configured documentation resources. The output tree retains paths needed
# > by the Markdown references, and the generator checks for missing image targets.
#
# > Repositories contributing different files with the same destination filename
# > must resolve the collision before generation. The generator must not silently
# > pick one image and discard the other.
#
# -- Generated Output ---------------------------------------------------------------
#
# > The bundle generator writes Markdown pages, chapter and section indexes,
# > navigation metadata and referenced assets beneath the configured output root.
# > It also incorporates available product reference documents such as release notes,
# > README, license and changelog into appendix content.
#
# > The generated Markdown can be inspected locally or passed to the WCM static-site
# > generator. HTML layout, theme rendering and website deployment are WCM concerns;
# > they do not belong to the bundle-managing Python CLI.
#
# -- Prefaces and Epilogues ---------------------------------------------------------
#
# > Documentation-only sources can provide introductory or closing content for a
# > product, group, or subgroup. Prefaces and epilogues intentionally behave
# > differently in the generated hierarchy.
#
# > A preface supplies the content of the hierarchy node itself. Selecting the product,
# > group, or subgroup therefore opens its introductory page directly instead of first
# > navigating to a separate child named "Preface". This makes authored introduction
# > material act as the landing page for the section it explains.
#
# > An epilogue remains a trailing child page beneath the corresponding hierarchy node.
# > It is emitted after the normal children and is appropriate for closing notes,
# > consolidated reference material, migration guidance, or other content that genuinely
# > belongs at the end of a section.
#
# > The role is primarily selected by the Metadata Purpose value:
#
# >     Product preface    <> Product-node content
# >     Product epilogue   <> Final child beneath the product
# >     Group preface      <> Group-node content
# >     Group epilogue     <> Final child beneath the named Group
# >     Subgroup preface   <> Subgroup-node content
# >     Subgroup epilogue  <> Final child beneath the named Subgroup
#
# > Group and Subgroup metadata determine where group- and subgroup-level sources
# > belong. Product-level sources belong directly to their product. Prefaces therefore
# > affect the parent node's content reference; epilogues affect child ordering.
#
# > Filename recognition is also supported as a compatibility fallback. The generator
# > recognizes conventional names based on the product, group, or subgroup name followed
# > by a preface or epilogue suffix. Names are normalized for matching, so hyphens, spaces,
# > and underscores in the logical name do not define the hierarchy themselves.
#
# > New documentation sources should make the role explicit through Purpose rather than
# > relying on filename inference. This keeps placement independent of the physical
# > doc-sources filename and leaves Group and Subgroup metadata as the authoritative
# > description of where the content belongs.
#
# > Add prefaces and epilogues only when they improve the reader's path. A preface is
# > useful when a section needs context, boundaries, a mental model, or a short guide to
# > its children. An epilogue is useful when material is more valuable after those
# > children have been read. Neither should be added merely to increase page count.
#
# > Example group preface metadata:
#
# >     Group       : Deployment
# >     Purpose     : Group preface
#
# > Example subgroup epilogue metadata:
#
# >     Group       : Web Content Manager
# >     Subgroup    : Documentation Generator
# >     Purpose     : Subgroup epilogue
#
# -- Documentation Conventions ------------------------------------------------------
#
# > Documentation comments should be written as part of normal development, not as
# > an afterthought at release time.
#
# > Module headers should be kept complete and current.
#
# > Public functions should include enough information for another developer to
# > understand their purpose, expected inputs, output, return behavior, and typical
# > usage.
#
# > Internal helpers may use shorter documentation, but should still explain intent
# > when the behavior is not obvious.
#
# > Empty documentation separator lines should use a plain comment line rather than
# > a quoted documentation line, to avoid stray quote markers in rendered output.
#
# -- Why Source-Based Documentation -------------------------------------------------
#
# > Script-heavy projects are especially vulnerable to documentation drift. Bash and
# > Python source files are easy to change quickly, and separate documentation is easy
# > to forget.
#
# > SolidGroundUX avoids this by treating source comments as the primary
# > documentation source.
#
# > This does not remove the need for prose, examples, or architectural explanation,
# > but it does make the reference documentation much more likely to stay close to
# > the implementation.
