<table>
<tr>
<td width="170" align="center" valign="middle">
  <img width="96" height="96" alt="SolidGroundUX logo" src="target-root/usr/local/assets/SolidGround UX.png" />
</td>
<td valign="middle">
  <big><big><big><strong>SolidGroundUX: Management Console Modules</strong></big></big></big>
</td>
</tr>
</table>

------------------------------------------------------------------------

## About this project

The **SolidGroundUX Management Console Modules** provide
system-management functionality for the SolidGroundUX Management
Console.

These modules were originally distributed as part of the standard
SolidGroundUX release. They are now maintained as a separate project so
that management functionality can evolve independently from the
SolidGroundUX framework itself.

SolidGroundUX provides the framework, runtime, console engine and shared
utilities. This project provides the modules and management-specific
executables that use that framework.

## Architecture

Management Console modules are primarily **presentation and
orchestration components**.

A console module may:

-   register menu groups and menu items;
-   determine availability and display status;
-   provide lightweight read-only status or validation functions;
-   orchestrate other registered actions;
-   dispatch work to framework or management executables.

Persistent or reusable system-changing functionality should normally be
implemented in a separate executable rather than directly inside a
console module.

Conceptually:

``` text
Management Console
        │
        ▼
Console module
  menu registration
  presentation
  status / orchestration
        │
        ▼
Management executable
        │
        ▼
System changes
```

Executables created specifically to implement management functionality
belong to this project. Generic SolidGroundUX utilities remain part of
the SolidGroundUX framework project, even when a Management Console
module provides a menu entry for them.

For example, the Development module may expose framework utilities such
as workspace creation, deployment or release preparation without taking
ownership of those utilities.

## DRYRUN contract

All persistent actions exposed through the Management Console must
respect the SolidGroundUX **DRYRUN** contract.

When DRYRUN is active, an action may inspect the system and report what
it would do, but it must not make persistent changes. This includes
changes to:

-   files and directories;
-   system or application configuration;
-   SolidGroundUX configuration or state;
-   services;
-   users and groups;
-   repositories;
-   remote systems.

Console modules must propagate DRYRUN to delegated executables. A
delegated action must not silently escape DRYRUN semantics.

DRYRUN output should describe intended actions using **Would ...** while the
preview is running, with enough detail to identify the relevant target, value,
file, service, user, repository, or remote system where practical. A mutating
action should finish its DRYRUN path with an explicit retrospective confirmation,
for example: **DRYRUN complete. The changes shown above would have been applied;
no changes were written.**

## Menu presentation

Modules and management executables that present menus should follow the
standard SolidGroundUX console layout.

Menu sections should use `sgnd_print_sectionheader` rather than ad-hoc
`Option: ...` headings or separators. The menu should have the standard
separator above the option section and an empty line after the final
menu option.

This keeps submenus visually consistent with the rest of the
SolidGroundUX Management Console.

## Project layout

Console modules are installed below the SolidGroundUX console-module
directory:

``` text
target-root/
└── usr/
    └── local/
        ├── lib/
        │   └── solidgroundux/
        │       └── common/
        │           └── active-directory-management.sh
        └── libexec/
            └── solidgroundux/
                ├── console-modules/
                │   ├── 10-computer-setup.sh
                │   ├── 15-storage.sh
                │   ├── 20-active-directory-server.sh
                │   ├── 25-active-directory-client.sh
                │   ├── 27-active-directory-management.sh
                │   ├── 30-samba-file-server.sh
                │   ├── 40-solidgroundux.sh
                │   ├── 45-solidground-framework-test.sh
                │   ├── 50-web-server.sh
                │   ├── 60-sqlserver.sh
                │   ├── 70-docker-server.sh
                │   └── 90-development.sh
                ├── framework-smoketest.sh
                ├── manage-active-directory-client.sh
                ├── manage-active-directory-server.sh
                ├── manage-active-directory.sh
                ├── manage-docker-containers.sh
                ├── manage-docker-server.sh
                ├── manage-samba-file-server.sh
                ├── manage-samba-shares.sh
                ├── manage-solidgroundux.sh
                ├── manage-sqlserver.sh
                ├── manage-storage.sh
                ├── manage-web-server.sh
                ├── publish-web-content.sh
                └── set-identity.sh
```

Management-specific executables may live alongside the SolidGroundUX
executable tooling outside the `console-modules` directory. They remain
part of this project when their primary purpose is to implement
functionality owned by a Management Console module.

## Canonical starter templates

A workspace created by `sgnd-create-workspace` contains copies of the
SolidGroundUX canonical starter templates.

These copies are included deliberately so that development can begin
directly from the canonical executable, library, module and wrapper
patterns without locating or copying templates from another
installation.

The copies in this repository are **reference/starter copies only**.
They are not project-owned variants of the SolidGroundUX canon and
should not be modified here. Changes to canonical templates belong in
the SolidGroundUX framework project.

Future workspace creation may mark these copied files explicitly as
workspace copies to make this distinction clear.

## Development principle

The boundary for this project is intentionally simple:

> **Console modules register and present functionality; executables
> implement functionality.**

Small presentation-only and read-only helpers may remain inside a module
where extracting them provides no practical benefit. Persistent
system-changing operations should live behind the module boundary in an
appropriate executable.

This separation keeps the Management Console modules small, makes
management actions independently testable, and provides a consistent
place to enforce framework conventions such as DRYRUN.
