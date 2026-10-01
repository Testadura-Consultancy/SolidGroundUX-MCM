# Changelog

All notable changes to SolidGroundUX Management Console Modules are documented in this file.

The format is inspired by *Keep a Changelog* while remaining focused on
practical framework development.

## Backlog

### AD Server module
- Provision domain doesn't report the underlying menu actions as done or errored.
- Add functionality to configure a second domain controller (after detecting one is present).

### AD Management
- Group and User management should enable selecting multiple users or groups and applying actions to them.

### AD Client module
- Leaving a domain currently requires two passes before client status reliably reports that the machine is no longer joined; investigate leave/reconciliation/state refresh.

### Samba file server
- Review the directory-management workflow so the active/selected directory set is always obvious, for example through path/tree context and clearer selection highlighting.
- Re-test multi-directory rights application and multi-group access assignment after the workflow cleanup; current E2E results indicate the configuration works overall, but these multi-selection flows remain unclear.

### SQL Server module
- Report finish to main menu.
- 12 Show server status: show mount points, not devices.

### Docker module
- Test container management once you know what you are doing.

### Management Console
- Make lazy module loading transactional so registrations made by a module are rolled back when metadata validation or module loading fails, preventing duplicate registrations on a later retry.

## Unreleased

### Management Console
- Made lazy module loading transactional so registrations created during a failed module load are rolled back before returning, preventing duplicate groups/items when the module is retried.
- Added a loaded-module registry view under **SolidGroundUX -> Framework Diagnostics**, showing module Shortname, Title, Type, Version, Build, load timestamp, and source, with selectable detailed metadata including Description.
- Expanded the loaded-module registry schema and registration flow to retain canonical header identity for modules loaded during the current console session.
- Changed console navigation so `Esc` is the canonical return/exit key: `Esc` returns from a module page to the main index and, on the main index, asks for confirmation before exiting.
- Removed `Q/q` as a Management Console exit shortcut and made the footer/help text context-aware (`Esc Previous menu` on module pages and `Esc Exit` on the main index).
- Standardized end-of-action behavior across console modules so actions that immediately return/redraw do not add a redundant completion wait.

### Storage module
- Corrected the indentation of the **Unmount storage** and **Expand storage** menu entries.

### Samba file server
- Added dedicated `manage-samba-users.sh` ownership for standalone Samba user/group administration, separating identity management from share/directory management.
- Added a single **Manage users and groups** entry beneath Samba Shares and removed standalone identity CRUD from the share manager.
- Added a comprehensive standalone Samba identity overview including user group memberships.
- Fixed **Add user(s) to local group** so the second selector lists Samba users rather than local groups.
- Added the required datatable dependency to the standalone Samba user/group manager.
- Verified fresh Active Directory mode end-to-end, including AD join, Samba preparation, share publication, access configuration, validation, and Windows client access.
- Verified fresh standalone mode end-to-end and verified both standalone -> AD and AD -> standalone authentication-mode transitions.

### Docker module
- Fixed the malformed first line in `manage-docker-server.sh` so the script has a valid shebang/header boundary.


### Storage module
- Added recovery for restored or reattached `SGND_STORAGE` volumes whose filesystem UUID no longer matches the SolidGroundUX-managed `/etc/fstab` entry; persistence reconciliation can identify an unambiguous managed volume, confirm the repair, update persistent configuration, and remount it without reprovisioning.
- Added completion-status propagation for composite storage configuration so completed storage subtasks are reflected by their Management Console status icons.

### AD Client module
- Added tracked subtask reporting for the composite domain-join workflow so completed, failed, warning, and unexecuted join steps are reflected correctly in Management Console status.
- Changed an already-joined domain preflight result from failure to warning, preventing an existing membership from being presented as an error.
- Added host Kerberos keytab validation to AD client join and validation.
- Expanded AD client reconciliation to detect and repair a missing or invalid `/etc/krb5.keytab` before restarting SSSD, allowing an existing valid realm membership to be repaired without a leave/rejoin cycle.

### Samba file server
- Simplified Samba authentication preparation so the server derives its mode from host Active Directory membership: AD members are configured for ADS integration and non-members for standalone operation, leaving domain membership ownership with the AD Client module.
- Completed Samba ADS integration and validation around Samba machine trust, Winbind domain state, NETLOGON connectivity, SSSD-backed host membership, and DNS verification.
- Improved Samba share-root preparation and validation so managed share paths remain traversable by authorized identities.
- Expanded **Show shares** into the consolidated share/access overview, including authentication mode, backing path and directory state, path traversal, explicit group access, and access-configuration state; removed the now-redundant **Show access** action.
- Added multiple-selection support for Active Directory groups when granting share access, applying the selected access level to every selected group and share.
- Improved share creation so the managed share root is displayed, the backing directory defaults to the share name but can be overridden with a relative path, and an existing suitable backing directory is reused rather than treated as an error.
- Added optional immediate access configuration after creating a share and kept new shares secure until explicit access is assigned.
- Added standalone Samba identity management for local Samba users and groups while keeping those actions unavailable in Active Directory mode.
- Added access-identity reconciliation support for managed shares.
- Fixed share-root traversal permissions that could allow Samba share discovery while filesystem traversal still denied authorized AD users.
- Fixed multi-group access assignment where only one selected Active Directory group could receive the requested rights.
- Fixed composite Samba preparation so completed child actions report their status to the Management Console.
- Added dedicated Samba directory management, separating filesystem directory lifecycle and ACL management from Samba share management, with share-root protection, multi-directory selection, explicit/default ACL inspection, and independently selectable Read, Write, and Traverse permissions.
- Added stateful default share access group and access level, with authentication-mode-aware group selection and support for clearing the saved default.
- Improved standalone local-group selection by excluding `nogroup` and user-private primary groups while retaining deliberate Samba access groups.
- Fixed share access reconciliation to use the authentication-aware single-group selector and correctly propagate Samba access synchronization failures.
- Improved Samba authentication reconfiguration with visible current/target mode reporting and progress through the transition steps.
- Fixed standalone-to-AD Samba transitions where Winbind retained stale machine-account credentials by synchronizing Samba machine-account data from the valid host AD membership before trust validation.

### Webserver module
- Added completion status reporting for web-server preparation steps, including separate status for Nginx installation and web-service startup.
- Standardized web-server action endings and removed redundant menu wait times for actions that handle their own continuation dialogs.
- Improved web-content and SolidGroundUX documentation publishing to resolve and validate the actual source web root, preventing nested publication directories that could result in HTTP 403 responses.
- Added site document-root management, allowing the document root of an existing Nginx site to be changed.

## Release 2.1.2626712

### Changed
- Samba share creation now selects a storage location immediately below the configured SolidGroundUX storage root before asking for the share name; the share path is derived from that location and existing backing directories can be reused.
- Standardized Management Console public management wrappers on the current canonical wrapper template rather than direct fixed `/usr/local/libexec` execution.

### Removed
- Removed remaining references to the superseded `sgnd-framework-smoketest` command and stale `framework-smoketest.sh` implementation; Framework testing uses the Framework-owned `sgnd-smoketest` command.

### Fixed
- Fixed Active Directory shared management code so it invokes the canonical identity-management executable directly instead of depending on the Management Console's private module-script runner.
- Fixed Active Directory server provisioning so resolver handoff waits for IPv4 DNS port 53 to become available before starting Samba, preventing intermittent DNS-listener failures during fresh domain-controller provisioning.
- Fixed Active Directory Management module metadata formatting that caused lazy-load metadata validation to fail and subsequent retries to produce duplicate menu registrations.
- Fixed Samba managed-share discovery and validation so shares can reside beneath selected top-level storage locations rather than being restricted to `/srv/storage/shares`.

### Verified
- Verified fresh Active Directory Domain Controller provisioning end-to-end on Ubuntu 24.04, with all provisioning, DNS, Kerberos, LDAP, registration, validation and status steps completing successfully.
- Verified Active Directory Client workflow on a fresh Ubuntu system joining an existing known-good Active Directory domain.

## Release 2.1.2626523

### Added

- Added the canonical per-module validation contract: `validate_module_<module-id-with-hyphens-replaced-by-underscores>`, `SGND_MODULE_VALIDATION_MESSAGE`, and standard Passed/Failed/Warning/Skipped return states.
- Added Framework Test orchestration that combines Framework-owned smoke/installation tests with Management Console-owned registration and module validation.
- Added metadata discovery from canonical module headers so the console can show ID, Version/Build, Description, Visibility and Source without sourcing modules.
- Added explicit development-context reporting for the console host and console application when either runs from a non-production root.

### Changed

- Completed ownership of the SolidGround Management Console host (`management-console.sh`) and public `sgnd-console` command in this product. The reusable runtime and `sgnd-menu` API remain Framework-owned.
- Framework smoke-test ownership moved to the SolidGroundUX Framework; Management Console Modules invokes the public `sgnd-smoketest` command rather than shipping a duplicate smoke-test executable.
- Module applicability is determined by each module's canonical validator; the Framework Test runner no longer hardcodes server-role knowledge.
- The Management Console module template is owned by this product; generic executable/library/documentation/wrapper templates are no longer treated as MCM-owned.
- Standardized corrected module/action presentation around SolidGroundUX section headers, spacing, current-state display and return-flow conventions.
- Continued the module/executable split so console modules remain presentation/orchestration layers and persistent operations are delegated to management executables.
- Development-root console execution now consumes the installed Framework when no local Framework is present, while application-local MCM executables and modules continue to resolve from the MCM development tree.

### Removed

- Removed the former Management Console-owned `framework-smoketest.sh` and `sgnd-framework-smoketest` wrapper; these are superseded by Framework-owned `sgnd-smoketest`.
- Removed duplicated runtime Version/Description module metadata in favor of canonical comment-header metadata.

### Fixed

- Fixed framework/module test integration after the product split, including console registration validation, module validator dispatch, smoke-test menu behavior and public-command execution.
- Fixed cross-module helper ownership exposed by lazy loading by moving shared helpers to their appropriate Framework or subject-specific libraries.
- Fixed Active Directory, Storage, Samba, Web Server, SQL Server and Docker module validation/presentation issues found during the 2.1 correction pass.
- Fixed Management Console development startup against an installed Framework after the repository split, including Framework bootstrap, UI style/palette and license resolution.
- Fixed duplicate/development module registration issues encountered while separating the SDK tooling from the Management Console product.

## Release 1.2.2626021

### Changed

- Moved all existing console management modules and their dependencies to a separate repository, to be released as a separate product.
- Defined Management Console Modules as an independently versioned and distributable product, while allowing tested compatible module releases to be bundled with full SolidGroundUX framework releases.
- Kept `90-development.sh` as a thin integration module over the existing public `sgnd-*` development commands, with no additional management executable required.
- Refactored console modules toward a presentation-and-orchestration role, moving persistent management operations into dedicated management executables.
- Refactored `40-solidgroundux.sh` to separate Management Console presentation and orchestration from persistent framework-management operations.
- Preserved runtime-sensitive framework state operations within the console module, with local DRYRUN protection.
- Propagated console DRYRUN mode to delegated management executables and release-management actions.
- Refactored SolidGroundUX framework testing into a thin console orchestration module, preparing framework-owned smoke testing and Management Console-owned registration/module validation to be separated cleanly.
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
- Added the Framework Test console page and the initial validation/smoke-test orchestration used during the product split.
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

