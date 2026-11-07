# Changelog

All notable changes to SolidGroundUX Management Console Modules are documented in this file.

The format is inspired by *Keep a Changelog* while remaining focused on practical framework development.

## Unreleased

Changes prepared for SolidGroundUX 2.2 R2.

### Added
- Added **Generate documentation from installed products** to SolidGroundUX Documentation in Web Content Management.
- Added on-demand Markdown generation with optional HTML output for selected installed products, using installed release manifests to keep Framework, MCM and SDK documentation sources separate.
- Added output-path safeguards and checks to keep generated documentation accessible to the console user.

### Changed
- Standardized console menu registration waits to **30 seconds** for actions without their own completion or auto-continue dialog across the MCM modules.
- Preserved zero-second menu waits for actions that handle their own completion, and retained the existing 35-second Samba status display.
- Updated Web Server and Web Content publishing defaults to use the current generated-documentation locations rather than the obsolete `solidgroundux-codex` path.

### Preserved
- Kept existing saved documentation bundles, explicit publishing, and the existing Markdown generator and WCM HTML rendering pipeline. PDF generation remains outside the 2.2 R2 scope.

## Pre Release 2.2.2630700
[CHANGELOG-History](CHANGELOG-History.md)
