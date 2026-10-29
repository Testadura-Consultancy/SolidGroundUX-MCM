# ==================================================================================
# SolidGroundUX SDK - Documentation Generator Overview
# ----------------------------------------------------------------------------------
# Metadata:
#   Version     : 2.1
#   Build       : 2627700
#   Checksum    : a2fd443bfa308d802e9a389e882d4e6f052f3c5d865af1f591b70faf11194f1e
#   Source      : sdk-documentation_preface.sh
#   Type        : documentation
#   Group       : Web Content Manager
#   Subgroup    : Documentation Generator
#   Purpose     : Subgroup preface
#
# Attribution:
#   Developers  : Mark Fieten
#   Company     : Testadura Consultancy
#   Client      : -
#   Copyright   : © 2025 - 2026 Testadura Consultancy
#   License     : Licensed under the Testadura Non-Commercial License (TD-NC) v1.1.
# ==================================================================================
# - Documentation Generator ---------------------------------------------------------------
#
# > Documentation-only sources may live in the canonical
# > `usr/local/share/solidgroundux/doc-sources` directory of any product. Full recursive
# > generation discovers them like other supported source files; their Product, Group, and
# > Subgroup metadata controls logical placement rather than their physical directory.
# > Product-prefixed basenames are recommended because module identity is basename-based.
# >
# > The Documentation Generator subgroup contains the tools used to extract, process, render,
# > and generate SolidGroundUX documentation.
#
# > The documentation system is built around the idea that documentation should live
# > close to the code it describes. Instead of maintaining a separate manual by hand,
# > source files contain structured comment blocks that can be converted into a
# > navigable HTML documentation set.
#
# > The file doc-sample.sh demonstrates the supported documentation conventions and
# > should be treated as the practical reference for writing documentation comments.
#
# -- Documentation Workflow ---------------------------------------------------------
#
# > The generator coordinates product discovery, source collection, parsing, cached
# > documentation data, rendering, and final output. One documentation collection can
# > contain one or more selected products. A primary product is selected as the lead
# > product and is processed first; the remaining products retain deterministic order.
#
# . Images
#   sdk-documentation-generation.png :: Documentation generation pipeline
#
# > For each selected product, the generator resolves its source root and applies the
# > configured source file masks. A per-product documentation ignore file is resolved
# > from user configuration first and system configuration second. Ignored files are
# > excluded before parsing, and duplicate module basenames are skipped with a warning.
#
# > The processor reads the selected source files and extracts module metadata, sections,
# > items, documentation lines, attribution data, and integrity information into
# > normalized tables. These tables are persisted as documentation cache data and form
# > the input to the renderer.
#
# > The renderer turns the normalized data into HTML pages, navigation, appendices,
# > glossary entries, branding, and supporting assets. Each selected product may also
# > contribute documentation assets from its canonical usr/local/assets directory.
#
# > Four generation modes are available:
# >
# >     1 <> Full            <> Reparse all matching source files for the selected products
# >     2 <> Selected        <> Reparse only explicitly selected matching files
# >     3 <> Changed         <> Reparse matching Git changes relative to HEAD, plus untracked files
# >     4 <> Render existing <> Rebuild HTML from the persisted renderer data only
# >
# > Creating a new collection in Full mode starts with a clean output directory. A Full
# > update of an existing collection instead loads the existing cache and refreshes the
# > selected products without clearing the collection. Selected and Changed modes also
# > load the existing cache and replace or remove only the affected modules.
# >
# > Successful parse modes pass the normalized data to the renderer and persist the data
# > required for later incremental or render-only runs. Render existing mode bypasses
# > source parsing completely and regenerates renderer-owned output from cached data.
# > The generated site can optionally be copied to the primary product repository's docs
# > directory after rendering.
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
# > The file doc-sample.sh demonstrates the supported labels and should be treated
# > as the practical reference for the documentation syntax.
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
# -- Style Hints --------------------------------------------------------------------
#
# > Documentation lines may include an optional leading marker that either identifies
# > plain documentation content or assigns a renderer style hint.
#
# > The plain documentation marker is:
#
# >     >           Plain documentation line
# >     >           When used without text, emits an intentional blank line
#
# > Style hints are presentation hints layered on top of the structural content type.
# > The renderer reads the exported stylehint value for each documentation line.
# > When the style hint is normal, no additional style class is added. When another
# > value is supplied, the renderer adds a corresponding sh-<stylehint> CSS class.
#
# > The currently supported style hints are:
#
# >     normal      <> Standard rendered text
# >     label       <> (:) Label or small subheader text
# >     highlight   <> (.) Highlighted text
# >     emphasis    <> (!) Emphasized text
# >     underline   <> (_) Underlined text
# >     quote       <> (~) Quoted or aside text
# >     listitem    <> (-) Bullet-style list item
# >     indent      <> Reserved indentation style
#
# > Marker characters are only interpreted when they are the first token after the
# > comment marker. Leading whitespace after "# " is preserved as author layout and
# > prevents marker interpretation.
#
# > These symbols are intended as visual cues and make it easier to identify the
# > purpose of a line while scanning a page.
#
# > Style hints should be used for presentation only. They do not replace content
# > labels such as fn:, fn$, var:, var$, doc:, or doc$.
#
# > The file doc-sample.sh should be treated as the practical reference for the
# > supported documentation syntax.
#
# -- Aligned Documentation ----------------------------------------------------------
#
# > The renderer recognizes @ <> as an alignment token in ordinary documentation content.
# > Consecutive lines containing @ <> form one aligned block. Corresponding fields share
# > the same browser-calculated column width, so proportional fonts remain correctly aligned.
# > The token is removed from rendered output.
# > 
# >     # > fn:  <> Function or method documentation
# >     # > var: <> Variable documentation
# >     # > cls: <> Class documentation
# >     # > doc: <> General documentation
# >
# > More than two columns are allowed by using @ <> more than once on each line. Alignment
# > ends when the next rendered documentation line does not contain @ <>. The processor
# > preserves the token as content; alignment is intentionally renderer-owned.
#
# -- Tables -------------------------------------------------------------------------
#
# > Documentation can embed tabular data directly in structured source comments. A
# > table begins with a highlighted Table marker. The following documentation lines are
# > collected as table rows until a blank documentation line ends the table.
# >
# > Table cells are separated by a double colon (::). The first table row is always the
# > semantic header row and is rendered using <thead> and <th>; following rows are rendered
# > using <tbody> and <td>. Column widths are left to the browser and stylesheet.
# >
# >     # . Table
# >     # ! Name :: Description :: Status
# >     # Framework :: Core SolidGroundUX framework :: Active
# >     # Console :: Management console modules :: Active
# >     #
# >
# > The first row may use the emphasis marker (!) as a visual style hint. This does not
# > change its table semantics: the first row remains the header. Following rows use normal
# > documentation lines so they remain part of the table. The processor preserves the ::
# > separators as content; table recognition, cell splitting, and HTML semantics belong to
# > the renderer.
#
# -- Images -------------------------------------------------------------------------
#
# > Documentation can embed one image or a group of images directly from structured
# > source comments. An image block begins with a label or highlight line whose content
# > is exactly Image or Images, followed by one or more normal documentation lines.
# > A blank documentation line ends the image block.
# >
# > The common construction is:
# >
# >     # : Images
# >     # File name.png
# >     # Another image.png :: Optional caption
# >     #
# >
# > Singular Image is also accepted:
# >
# >     # : Image
# >     # Architecture.png :: Framework architecture
# >     #
# >
# > The marker may use either the label (:) or highlight (.) style hint. Image entries
# > themselves must remain normal documentation lines. The optional caption is separated
# > from the filename or source by a double colon (::). When no caption is supplied, the
# > renderer derives alternative text from the filename.
# >
# > Relative filenames are resolved beneath the generated assets/images directory.
# > Each selected documentation product may provide documentation assets beneath:
# >
# >     <product-source-root>/usr/local/assets
# >
# > The generator supplies these product asset directories to the renderer. Their flat
# > contents are merged into the generated documentation assets/images directory without
# > renaming files, so asset filenames are expected to be globally unique across products.
# > Sources beginning with assets/ are resolved relative to the generated documentation
# > asset root. Absolute paths, http/https URLs, and data URLs are also accepted by the
# > renderer.
# >
# > Consecutive image entries are rendered as one responsive image group. The renderer
# > selects layouts for one, two, three, or four-column groups automatically; larger
# > groups continue using the four-column layout.
#
# -- Generated Output ---------------------------------------------------------------
#
# > The generated documentation consists of an HTML index, content pages, stylesheet
# > assets, images, appendices, glossary pages, integrity information, and renderer-owned
# > site branding. Documented SolidGroundUX style modules can also receive generated
# > semantic theme specimens derived from their actual style and palette assignments.
# >
# > Project-level appendices are supplied from repository/project sources such as the
# > canonical architecture/conventions document, CHANGELOG, INSTALL guide, and license.
# > These prose sources should be maintained alongside the project and regenerated into
# > the HTML set rather than editing generated appendix pages directly.
#
# > The output is intentionally static HTML so it can be viewed in any browser
# > without requiring a web server, database, or application runtime.
#
# > This makes the documentation easy to publish, archive, review, and distribute
# > together with a release package.
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
# > Filename recognition is also supported as a compatibility fallback. The renderer
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
# >     Group       : SDK
# >     Subgroup    : Documentation Generator
# >     Purpose     : Subgroup epilogue
#
# . Images
#   sdk-documentation-system.png :: Documentation System overview
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
