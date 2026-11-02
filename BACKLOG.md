# SolidGroundUX Management Console Modules — Backlog

Last reviewed: 2026-11-02

Outstanding work is tracked here; completed implementation is recorded in [CHANGELOG.md](CHANGELOG.md). The documentation structure, source-comment review and architectural illustration review are complete. PostgreSQL and MariaDB have been validated as working servers; full 2.1 regression is still pending.

## Before the next release

- [ ] **Consolidated management regression:** test console/module flows, database managers where safe, Nginx website discovery and unmatched-host HTTPS fallback, post-action dialogs, WCM metadata-field removal, and website generation/publication with the current Framework and SDK.
- [ ] **Documentation output smoke test:** check bundle/product/section preface and epilogue ordering, navigation/breadcrumbs, figure numbering and anchors, Figure Index table layout, percentage-sized images, broken-image warnings and shared MCM CSS across the generated Markdown and published website.
- [ ] **Retire the direct GitHub Pages menu action:** `55-web-content-management.sh` in the 2026-11-02 snapshot still registers **Push to GitHub Pages**. Remove or hide that obsolete menu path to match the chosen **Generate Website → Publish Website** workflow; if the direct path is intentionally retained, explicitly decide ownership and test it rather than assuming verification is complete.
- [ ] **Workflow-status regression:** after successful documentation generation verify website-generation/publication warnings; after standalone website generation verify publication warning; cancellation, failure and menu redraws must not misreport completion.

## Deferred / later release

- [ ] **Additional writable AD domain controller:** live-test joining an existing domain, DNS/resolver transition, replication convergence and failed-join recovery **only when there is a use case**. Deferred; not a 2.1 blocker.
- [ ] **WCM link repair on rename/move:** update affected internal links automatically when moving or renaming content. Deferred enhancement.
- [ ] **Explicit product-specific documentation CSS:** add optional, chapter-scoped overrides only when needed; MCM’s shared bundle stylesheet remains the default and must not be silently overwritten.
- [ ] **Automatic translations (3.0):** generate and maintain translated content across configured languages.
