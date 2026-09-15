# Installing SolidGroundUX Management Console Modules

SolidGroundUX Management Console Modules are distributed as a separate product
from the SolidGroundUX framework.

The modules require an installed SolidGroundUX framework. They use the
SolidGroundUX Management Console, runtime, shared libraries, Release Manager,
and other framework services, but are versioned and released independently.

## Installation options

Management Console Modules can be installed in two ways:

1. As part of a **bundled SolidGroundUX release**.
2. As a **separate Management Console Modules release** through the
   SolidGroundUX Release Manager.

Both methods install the same Management Console Modules product.

## Bundled with SolidGroundUX

A SolidGroundUX release may bundle a compatible release of:

```text
SolidGroundUX Management Console Modules
```

The bundled modules release is the **current Management Console Modules version
selected when that SolidGroundUX release is prepared**.

It is therefore the module version shipped with that particular framework
release; it is not a promise that the bundle will remain the newest
Management Console Modules release published later.

Installing the bundle installs both products using their own product identity
and release history. After installation, Management Console Modules can be
updated independently when a newer compatible module release is published.

Bundling provides the normal starting combination for a SolidGroundUX release
while preserving the separate lifecycle of the modules product.

## Installing the modules separately

When SolidGroundUX is already installed, Management Console Modules can be
installed from their own release package using the SolidGroundUX Release
Manager.

Start the installed Release Manager:

```bash
sudo /var/lib/solidgroundux/release-manager.sh
```

Select:

```text
SolidGroundUX Management Console Modules
```

as the product/package to manage.

The Release Manager can then acquire and install a published or locally
available Management Console Modules release using the same validation,
installation, update, rollback, reinstallation, and removal lifecycle used for
other SolidGroundUX-managed products.

The modules package does not carry its own Release Manager. Release management
is provided by the installed SolidGroundUX framework.

## Releases

Management Console Modules are independently versioned.

A release package uses the product name in its release artifacts, for example:

```text
SolidGroundUX-Management-Console-Modules-<version>-release.zip
```

The exact version and build are determined when the product release is
prepared.

Because the product has its own release lifecycle, a newer Management Console
Modules release can be published without requiring a new SolidGroundUX
framework release.

Likewise, a later SolidGroundUX release can bundle whichever current compatible
Management Console Modules version was selected at the time that framework
release was prepared.

## Release Manager state

SolidGroundUX keeps its own release state directly below:

```text
/var/lib/solidgroundux/
```

Management Console Modules use project-specific Release Manager state below:

```text
/var/lib/solidgroundux/projects/solidground-management-console-modules/
```

This keeps the module product's available releases, installed release history,
repository settings, and other release-management state separate from the
SolidGroundUX framework itself.

The installed files still use the normal SolidGroundUX filesystem layout. The
separate state directory represents product ownership and release history, not
a separate runtime environment.

## Installed files

Console modules are installed below:

```text
/usr/local/libexec/solidgroundux/console-modules/
```

Management-specific executables are installed in the appropriate SolidGroundUX
runtime locations, primarily below:

```text
/usr/local/libexec/solidgroundux/
```

Project-owned supporting libraries and definitions are installed in their
corresponding SolidGroundUX library locations.

Although these files run inside the SolidGroundUX environment, they are owned
and released by the **SolidGroundUX Management Console Modules** product rather
than by the framework repository.

## Updating

To check for or install a newer Management Console Modules release, start the
Release Manager and select the Management Console Modules product.

A module update does not require reinstalling SolidGroundUX merely because the
modules are a separate release.

The Release Manager maintains the product's release history independently,
allowing the installed module version to move forward separately from the
framework version.

## Rollback and reinstallation

Previously installed Management Console Modules releases are retained in the
product-specific Release Manager archive.

The Release Manager can therefore reinstall the current release or roll the
modules product back to an available archived release without rolling back the
SolidGroundUX framework itself.

As with any framework/module combination, the selected versions should be
compatible.

## Removal

Management Console Modules can be removed independently through the Release
Manager.

Removing the product removes files owned by the selected Management Console
Modules release while leaving the SolidGroundUX framework installed.

Release packages and history are managed by the Release Manager so the product
can subsequently be reinstalled if required.

## Development installations

The repository mirrors the installed filesystem beneath its `target-root`.

For development and testing, workspace deployment can be used to transfer the
development tree to an alternate or target system without creating formal
installed release history.

That development workflow is intentionally separate from release installation.

Formal installations should use a prepared release package and the
SolidGroundUX Release Manager.

## Repository ownership

All standard SolidGroundUX Management Console modules are maintained in the
**SolidGroundUX Management Console Modules** repository.

The SolidGroundUX framework repository owns the framework runtime, Management
Console engine, shared framework libraries, generic framework utilities,
canonical templates, and release infrastructure.

This repository owns the Management Console modules, management-specific
executables, and project-owned supporting code.

The separation allows both products to evolve and be released independently
while still allowing a tested Management Console Modules release to be bundled
with a SolidGroundUX framework release.
