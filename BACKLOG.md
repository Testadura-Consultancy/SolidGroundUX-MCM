# SolidGroundUX Management Console Modules — Backlog

Last reviewed: 2026-10-29

Outstanding work is tracked here; completed implementation is recorded in [CHANGELOG.md](CHANGELOG.md). The PostgreSQL and MariaDB servers are working, Create Workspace is tested in the SDK, and WCM metadata-field removal is implemented.

## Before the next release

- [ ] **Review transferred documentation diagrams:** assess `mcm-documentation-generation.png`, `mcm-documentation-system.png` and `mcm-documentation-process.png` against the current MCM bundle/Markdown and WCM HTML/publishing pipeline. Artwork was moved unchanged from SDK and is deliberately not embedded in published documentation until reviewed.
- [ ] **Consolidated regression:** test management flows, Nginx site listing and internal HTTPS fallback, standard post-action dialogs, WCM metadata removal, and documentation website generation/publication alongside the Framework and SDK.
- [ ] **GitHub Pages end-to-end verification:** exercise the implemented `main/docs` publishing flow against an appropriate test repository. The presence of code alone is not an end-to-end test.

## Deferred / later release

- [ ] **Additional writable AD domain controller:** live-test joining an existing domain, DNS/resolver transition, replication convergence and failed-join recovery **only when there is a use case**. Deferred; not a 2.1 blocker.
- [ ] **WCM link repair on rename/move:** update affected internal links automatically when moving or renaming content. Deferred enhancement.
- [ ] **Automatic translations (3.0):** generate and maintain translated content across configured languages.
