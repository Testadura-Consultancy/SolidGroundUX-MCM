# Changelog

All notable changes to SolidGroundUX Management Console Modules are documented in this file.

The format is inspired by *Keep a Changelog* while remaining focused on
practical framework development.

## Unreleased

### Changed

- Moved all existing console management modules and their dependencies to a separate repository, to be released as a separate product.
- Defined Management Console Modules as an independently versioned and distributable product, while allowing tested compatible module releases to be bundled with full SolidGroundUX framework releases.
- Kept `90-development.sh` as a thin integration module over the existing public `sgnd-*` development commands, with no additional management executable required.
- Refactored console modules toward a presentation-and-orchestration role, moving persistent management operations into dedicated management executables.
- Refactored `40-solidgroundux.sh` to separate Management Console presentation and orchestration from persistent framework-management operations.
- Preserved runtime-sensitive framework state operations within the console module, with local DRYRUN protection.
- Propagated console DRYRUN mode to delegated management executables and release-management actions.
- Refactored SolidGroundUX framework testing into a thin console module backed by the standalone `sgnd-framework-smoketest` executable.
- Refactored `30-samba-file-server.sh` to separate Samba File Server presentation and orchestration from persistent Samba management operations.
- Refactored `15-storage.sh` to separate Storage console presentation and orchestration from persistent storage-management operations.
- Standardized DRYRUN reporting for management actions, using `DRYRUN: Would ...` during previews and an explicit retrospective completion message.
- Improved Samba selection-dialog presentation with caller-owned section headers, spacing, and option layout.
- Refactored Active Directory Server, Client, and Directory Management modules into thin console presentation and orchestration modules backed by dedicated management executables.
- Consolidated shared Active Directory discovery, validation, addressing, and domain-state helpers into `active-directory-management.sh`.
- Refactored `50-web-server.sh` into a thin console module backed by dedicated web-server management and publishing executables.
- Separated Nginx server/site configuration from web-content publishing, keeping web-server management responsible for how content is served and publishing responsible for how content is deployed.
- Generalized web-content publishing so ordinary Nginx sites can be published from local directories, remote machines, or Git repositories; SolidGroundUX documentation remains a specialized publishing workflow.
- Refactored `60-sqlserver.sh` into a thin console module backed by `manage-sqlserver.sh`, preserving the existing SQL Server host-management scope.
- Added the initial `70-docker-server.sh` console module with separate Docker host and container-management executables.

### Added

- Added `manage-solidgroundux.sh` for persistent framework configuration management and logfile rotation.
- Added consistent DRYRUN handling to SolidGroundUX management actions, including detailed previews of intended persistent changes.
- Added standalone framework smoke-test execution with smoke, installation, console, module, and combined test suites.
- Added `manage-samba-file-server.sh` for Samba File Server installation, preparation, service management, validation, and status operations.
- Added dedicated Samba share-management support for creating, removing, structuring, validating, and assigning access to managed shares.
- Added `manage-storage.sh` for persistent storage provisioning, mounting, expansion, access management, validation, and status operations.
- Added storage configuration reconciliation to detect an existing `SGND_STORAGE` volume and repair stale SolidGroundUX `storage.cfg` state without reprovisioning the volume.
- Added storage persistence reconciliation to detect and remove stale SolidGroundUX-managed `/etc/fstab` entries while preserving the active storage volume.
- Added reconciliation checks to storage provisioning validation, including configured-versus-detected storage state and managed `fstab` consistency.
- Added `manage-active-directory-server.sh` for Active Directory Domain Controller provisioning, preparation, validation, and status operations.
- Added `manage-active-directory-client.sh` for Active Directory client joining, reconciliation, validation, status, and leave operations.
- Added `manage-active-directory.sh` for Active Directory user, group, and computer management.
- Added Active Directory client reconciliation for repairing DNS, machine identity, SSSD state, and client DNS registration without silently rejoining the domain.
- Expanded Active Directory validation to cover domain membership, Kerberos and LDAP discovery, SSSD, DNS configuration and registration, and directory enumeration.
- Added `manage-web-server.sh` for Nginx installation, content-root configuration, site lifecycle, service and firewall management, documentation-site configuration, validation, and status.
- Added `publish-web-content.sh` for generic Nginx content publishing from local directories, remote machines, and Git repositories.
- Added reusable Git repository publishing with branch/tag and repository-subdirectory selection for ordinary web sites.
- Preserved SolidGroundUX documentation publishing as a specialized workflow using installed documentation, local or remote sources, or a Git repository.
- Added `manage-sqlserver.sh` for SQL Server repository setup, engine and tools installation, storage, network, memory, service, firewall, validation, and status operations.
- Added `manage-docker-server.sh` for Docker Engine installation, host storage configuration, service management, validation, and status.
- Added `manage-docker-containers.sh` for basic container and image lifecycle operations, including create, start, stop, restart, remove, inspect, logs, image listing, and image pulls.

### Fixed

- Fixed delegated executable argument parsing so framework built-in options such as `--dryrun` are parsed correctly.
- Fixed Samba File Server management action declaration so enum action values are correctly registered with the SolidGroundUX argument parser.
- Fixed framework smoke-test validation to load all console modules before validating registered console handlers.
- Fixed storage recovery when an existing `SGND_STORAGE` volume is valid but `storage.cfg` points to a stale mount point.
- Fixed validation coverage for stale SolidGroundUX-managed `/etc/fstab` storage entries.
- Fixed Samba management dependence on stale storage configuration by consistently consuming the reconciled SolidGroundUX storage configuration.
- Fixed Active Directory shared-library loading so application-owned AD helpers resolve correctly from the Management Modules development or production tree.
- Fixed stale private Active Directory helper references introduced during the module/executable split and restored client context collection using the shared AD helpers.
- Fixed web publishing DRYRUN behavior so publishing state, SSH setup, Git checkout activity, and destination content are not persistently changed during preview.
- Fixed malformed enum argument specifications in `framework-smoketest.sh`, `manage-solidgroundux.sh`, and `set-identity.sh` so allowed values are registered correctly.
- Fixed a stray token in `framework-smoketest.sh` that prevented the script from parsing.

