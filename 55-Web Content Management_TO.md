# 55 - Web Content Management

## Technical Design

## 1. Purpose

The **55 - Web Content Management** module provides a generic way to generate and publish static websites from a repository containing configuration files, Markdown content, HTML templates, CSS, and static assets.

The first implementation target is the Testadura Consultancy website, but the implementation must not contain Testadura-specific logic.

The module is integrated into the SolidGroundUX Management Console. All user interaction is handled by the SolidGroundUX Bash layer; the underlying Python component acts as a non-interactive, reusable content engine.

The complete implementation belongs to the **SolidGroundUX Management Console Modules (MCM)** product. The Python engine remains reusable by design, but reusability does not imply SDK ownership.

---

## 2. Design Principles

### 2.1 Separation of Responsibilities

```text
Markdown
    content + metadata + optional presentation hints

HTML templates
    page and document structure

CSS
    presentation

Python content engine
    parsing + validation + rendering
```

SolidGroundUX surrounds this with the user interface and publishing workflow:

```text
SolidGroundUX Management Console
            |
            v
content-management.sh
            |
            v
WebContent CLI
            |
            v
Python WebContent package
```

### 2.2 Bash Owns the User Interface

`content-management.sh` contains all user interaction and workflow coordination:

- menus and prompts;
- site/repository selection;
- language and action selection;
- defaults and state;
- confirmations;
- progress reporting;
- logging;
- presentation of errors and results;
- publishing and deployment steps.

All program-generated messages from the Bash layer use the existing SolidGroundUX logging and output primitives.

### 2.3 Python Is the Engine

The Python component:

- contains no interactive prompts;
- contains no menus;
- never asks the user for input;
- contains no SolidGroundUX-specific UI logic;
- returns results, errors, and exit codes in a predictable manner.

The Python component is designed as a library with a thin CLI wrapper. This allows the same engine to be called directly from other Python code and, if useful later, to serve as the design basis for a C# class library implementation.

### 2.4 No Built-In Theme

The content engine does not determine how a website looks.

Each site owns its own:

- HTML templates;
- CSS;
- navigation configuration;
- images;
- other static assets.

No external theme framework is required.

---

## 3. Website Repository

WWW content does not require a SolidGroundUX `target-root`.

A possible repository structure is:

```text
Testadura-WWW/
├── config/
│   ├── site.cfg
│   └── navigation.cfg
├── content/
│   ├── pages/
│   ├── tales/
│   └── reflections/
├── templates/
│   ├── base.html
│   ├── home.html
│   ├── page.html
│   ├── article.html
│   ├── listing.html
│   └── partials/
│       ├── sidebar.html
│       ├── footer.html
│       └── language-selector.html
├── css/
│   ├── base.css
│   ├── layout.css
│   └── components.css
└── images/
```

The exact repository structure may be refined later, but the separation between configuration, content, templates, styling, and assets remains fundamental.

---

## 4. Content Files

### 4.1 Format

Actual content is stored in Markdown files (`.md`). Each file starts with a metadata section followed by the content.

```markdown
---
title: Why IT Is Afraid of Users
date: 2026-10-07
summary: How distance between IT and users can unnecessarily obstruct projects.
tags:
  - software
  - projects
featured: true
draft: false
---

Most software is ultimately not used by the person who built it.

## The Problem

Content starts here.
```

### 4.2 Strongly Named Files

The file name contains both a fixed content ID and a language code:

```text
why-it-fears-users_NL.md
why-it-fears-users_EN.md
why-it-fears-users_DE.md
why-it-fears-users_IT.md
```

This yields:

```text
content-id = why-it-fears-users
language   = NL / EN / DE / IT
```

Files with the same basename and a different language code are treated as translations of the same content. Dutch is initially the primary language.

### 4.3 Metadata

Minimum supported metadata:

```text
title
date
summary
tags
featured
draft
```

Additional metadata fields can be added later without fundamentally changing the content model.

---

## 5. Markdown Support

The renderer intentionally supports a limited and predictable Markdown subset:

- normal paragraphs;
- `## H2`;
- `### H3`;
- `**bold**`;
- `*italic*`;
- unordered lists;
- ordered lists;
- links;
- images;
- blockquotes;
- fenced code blocks with an optional language;
- tables;
- horizontal rules.

The page title (`<h1>`) is normally derived from the metadata `title`, so article content does not need to start with `#`.

### 5.1 Tables

Markdown tables are supported, including alignment where practical.

```markdown
| Name | Count | Amount |
|:---|---:|---:|
| One | 12 | € 1,250 |
| Two | 7 | € 850 |
```

CSS determines the final presentation.

---

## 6. Limited Theme Awareness in Markdown

Content may optionally contain presentation hints by explicitly referencing CSS classes.

A reserved prefix is used for this:

```text
td-
```

Examples:

```markdown
[this text is green]{.td-green}
```

```markdown
::: td-callout
An important observation.
:::
```

Possible CSS:

```css
.td-green { ... }
.td-red { ... }
.td-yellow { ... }
.td-blue { ... }

.td-note { ... }
.td-warning { ... }
.td-technical { ... }
.td-muted { ... }
```

### 6.1 CSS as the Source of Truth

The generator may derive available `td-*` classes directly from the CSS files.

```text
Markdown uses td-green
CSS contains .td-green
✓ valid
```

```text
Markdown uses td-purple
CSS does not contain .td-purple
✗ unknown content style
```

Semantic classes such as `td-note` and `td-warning` are preferred over purely visual classes where appropriate. The four Testadura colors may still be exposed explicitly as part of the visual identity.

---

## 7. HTML Templates

Page structure and layout are defined by site-owned HTML templates.

Minimum set:

```text
base.html
home.html
page.html
article.html
listing.html
```

Shared fragments are stored as partials:

```text
sidebar.html
footer.html
language-selector.html
```

Possible page types include:

- home page;
- regular content page;
- article page;
- listing/index page;
- optionally specialized product pages later.

---

## 8. CSS

CSS is fully owned by the website and is not determined by the generator.

### `base.css`

Contains, among other things:

- CSS variables;
- colors;
- typography;
- headings;
- links;
- standard lists;
- tables;
- code;
- blockquotes;
- generic HTML elements.

### `layout.css`

Contains, among other things:

- sidebar;
- main content area;
- grids;
- maximum widths;
- spacing;
- responsive behavior;
- mobile layout.

### `components.css`

Contains, among other things:

- IMSD panels;
- article cards;
- product cards;
- buttons;
- callouts;
- language selector;
- timelines;
- site-specific components.

The content engine does not know Testadura color values or component styling.

---

## 9. Python Architecture

The Python implementation is designed as a package, not as a monolithic script.

Possible structure:

```text
webcontent/
├── __init__.py
├── generator.py
├── content.py
├── markdown.py
├── templates.py
├── social.py
├── validation.py
└── cli.py
```

The library exposes functions/classes that can be used independently from the CLI.

Conceptually:

```python
result = generate_site(
    source=source_path,
    output=output_path,
    languages=["NL", "EN"]
)
```

The CLI wrapper translates command-line arguments into library calls.

This allows the engine to be:

- called from other Python software;
- used from CI/CD;
- invoked through a command-line contract from Bash or C#;
- used as the design basis for a future C# class library implementation.

---

## 10. Generator Responsibilities

The generator is responsible for at least:

```text
1. read site configuration
2. read navigation configuration
3. scan content directories
4. derive content ID and language from file names
5. parse and validate metadata
6. convert Markdown to HTML
7. validate td-* styles against available CSS
8. link language variants
9. select the correct HTML template
10. render pages
11. generate listings/content indexes
12. determine featured content
13. include static assets
14. prepare social-media output
15. write the complete output tree
```

Important design principle:

> The generator does not invent content, styling, or navigation structure.

Everything generated originates from configuration, content, templates, CSS, and assets.

---

## 11. Automatic Listings

Content groups such as:

```text
content/tales/
content/reflections/
```

can automatically receive listing pages.

The generator uses metadata from the underlying content files. Adding a new article therefore only requires adding a new content file; no HTML index needs to be maintained manually.

---

## 12. Multilingual Content

The combination of basename and language code determines translation relationships.

```text
article_NL.md
article_EN.md
```

Possible URL structure:

```text
/tales/article/        -> Dutch
/en/tales/article/     -> English
/de/tales/article/     -> German
/it/tales/article/     -> Italian
```

A language selector is only shown for variants that actually exist.

---

## 13. Social Media Output

The generator supports a generic **Prepare Social Media** capability.

LinkedIn is the first platform, but the architecture is platform-independent.

```text
article.md
   |
   +--> website HTML
   |
   +--> social output
        ├── LinkedIn
        ├── Mastodon
        ├── Bluesky
        └── future platforms
```

### 13.1 Social Templates

Each platform uses its own template:

```text
templates/
└── social/
    ├── linkedin.txt
    ├── mastodon.txt
    └── bluesky.txt
```

A platform template may use values such as:

```text
title
summary
canonical_url
tags / hashtags
social intro
```

### 13.2 Social Metadata

Content can specify which platforms should receive prepared output.

```yaml
social:
  linkedin: draft
  mastodon: false
  bluesky: false
```

Or in a more explicit form:

```yaml
social:
  linkedin:
    enabled: true
    intro: >
      Nine women cannot make a baby in one month.
      Yet IT projects sometimes seem to try.
```

If no explicit social intro is provided, the renderer may fall back to metadata such as `summary`.

### 13.3 Prepare Versus Publish

The initial implementation generates **social drafts only**.

Automatic publication to external platforms is a separate responsibility and is not part of the first generator implementation.

This preserves human review before publication.

---

## 14. SolidGroundUX Integration

The Management Console module is **55 - Web Content Management**.

The Bash layer (`content-management.sh`) is responsible for:

- selecting the site/repository;
- selecting an action;
- collecting source and target paths;
- selecting languages;
- generate/validate/publish/social choices;
- confirmations;
- state and defaults;
- progress reporting;
- logging;
- presenting results;
- deployment/publication.

Conceptual menu:

```text
Web Content Management

  Generate website
  Validate website
  Publish website
  Prepare social media posts
  Show status
```

The exact menu structure is determined during implementation.

### 14.1 CLI Contract

The Bash layer calls the Python CLI non-interactively.

```bash
webcontent generate     --source "$source"     --output "$output"     --language "$language"
```

```bash
webcontent prepare-social     --source "$source"     --platform linkedin
```

The Python CLI returns a predictable exit code and preferably machine-readable results.

```json
{
  "success": true,
  "pages_generated": 12,
  "articles_generated": 7,
  "warnings": 1,
  "social_drafts": 2
}
```

The Bash module translates these results into the standard SolidGroundUX UX.

---

## 15. Publishing

The generator writes to a specified output location.

The same repository can therefore be generated for different targets:

```text
development
staging
production
```

A later production workflow may look like:

```text
build
  ↓
validate
  ↓
staging
  ↓
atomic switch to new release
```

Polling, automatic pickup of new content, and other deployment automation are built as workflows around the generator and are not hidden inside the content engine itself.

---

## 16. Development Model

For local development, a generated site can be served very simply:

```bash
cd public
python3 -m http.server 8080
```

A helper script may combine build and local serving, but that is not a responsibility of the content engine itself.

---

## 17. Future Extensions

Possible extensions that do not require a fundamental redesign:

- RSS feeds;
- sitemap generation;
- richer metadata;
- additional content types;
- additional languages;
- search index;
- content status/workflow;
- automated staging;
- automatic publication triggers;
- social-media publishing;
- additional social-media platforms;
- CI/CD integration;
- content linting;
- link validation;
- image processing;
- future C# implementation of the engine.

These are added only when a concrete need exists.

---

## 18. Summary

```text
Repository
│
├── Config
├── Markdown content
├── HTML templates
├── CSS
└── Assets
         │
         ▼
Python WebContent engine
         │
         ├── HTML website
         └── Social media drafts
                 │
                 ▼
SolidGroundUX Web Content Management
         │
         ├── user interaction
         ├── validation/workflow
         └── publishing
```

Core principles:

1. Content remains simple, readable Markdown.
2. Templates define structure.
3. CSS defines appearance.
4. The Python package is a reusable, non-interactive engine.
5. Bash provides all SolidGroundUX user interaction and workflow.
6. Social-media output reuses the same content through separate templates.
7. The generator remains generic; Testadura.nl is only the first user.
8. New functionality is added only when there is a concrete need.
