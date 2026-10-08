# 55 - Web Content Management: first implementation

This archive is a repository-ready first implementation for the **SolidGroundUX Management Console Modules** product.

It deliberately follows existing MCM ownership and layout conventions:

- `55-web-content-management.sh` is the console module.
- `manage-web-content.sh` owns all user interaction, state, progress, and reporting.
- `webcontent/` is a non-interactive Python package containing the reusable engine.
- `sgnd-manage-web-content` is the standard SolidGroundUX management wrapper.
- `sgnd-webcontent` is a thin non-interactive CLI adapter for development, automation, and testing.

## Initial capabilities

- Validate a website source repository.
- Generate static HTML from strongly named Markdown content.
- Read `site.cfg` and `navigation.cfg`.
- Render `home`, `page`, `article`, and `listing` templates.
- Render shared sidebar/footer/language-selector partials.
- Generate language-prefixed variants for non-default languages.
- Generate automatic listing pages.
- Generate home-page featured article cards.
- Copy CSS and image assets.
- Validate Markdown `td-*` presentation classes against site CSS.
- Support paragraphs, H2/H3, bold, italic, lists, links, images, blockquotes, fenced code, tables, horizontal rules, and `:::` styled blocks.
- Prepare social-media drafts using platform templates when article metadata opts in.

No third-party Python packages are required.

## Deliberately not included yet

- Nginx publication/deployment.
- Automated content polling/watchers.
- Atomic production release switching.
- Social-media API publishing.
- RSS/sitemap/search generation.

Those can be added around the proven content engine later.

## Direct engine smoke test

With the website starter repository from the design discussion:

```bash
PYTHONPATH=target-root/usr/local/lib/solidgroundux/py \
python3 -m webcontent.cli validate \
    --source /path/to/Testadura-WWW

PYTHONPATH=target-root/usr/local/lib/solidgroundux/py \
python3 -m webcontent.cli generate \
    --source /path/to/Testadura-WWW \
    --output /tmp/testadura-www \
    --language ALL
```
