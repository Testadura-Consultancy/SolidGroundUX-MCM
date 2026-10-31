# ==================================================================================
# SolidGroundUX Management Console Modules - Role Managers
# ----------------------------------------------------------------------------------
# Metadata:
#   Version     : 2.1
#   Build       : 2627700
#   Checksum    : ef0c330ea808bf3dc2d8a22e6b003c1d4e18b353a976d8f471ae537814d7bf11
#   Source      : mcm-role-managers_preface.sh
#   Type        : documentation
#   Group       : Role Managers
#   Purpose     : Group preface
#
# Attribution:
#   Developers  : Mark Fieten
#   Company     : Testadura Consultancy
#   Client      : -
#   Copyright   : © 2025 - 2026 Testadura Consultancy
#   License     : Licensed under the Testadura Non-Commercial License (TD-NC) v1.1.
# ==================================================================================
# - Role Managers -------------------------------------------------------------------
#
# > Role managers are the operational layer behind the Management Console. They contain
# > subject-specific actions for computer identity, storage, Active Directory, Samba,
# > web serving, SQL Server, Docker, Framework management, and related administration.
#
# > Console modules call these executables to perform work, but the executables are not
# > coupled to the console host. They can be exercised directly, which keeps operational
# > behavior testable and reusable outside the menu layer.
#
# -- Responsibilities ---------------------------------------------------------------
#
# > A role manager should own the actual system-management contract for its subject:
# > validation, state inspection, requested changes, dry-run behavior, and meaningful
# > return status. Console modules should not duplicate that implementation merely to
# > expose it through a menu.
#
# > Shared behavior used by multiple role managers belongs in an appropriately owned
# > common library rather than being copied between executables.
#
# -- Output and Interaction ---------------------------------------------------------
#
# > Program-generated messages must use the SolidGroundUX logging/output primitives so
# > console and file logging remain consistent. Raw `printf`/`echo` output is reserved for
# > genuine bootstrap cases before the Framework is available and for low-level
# > prompt/input mechanics where direct terminal control is required.
#
# > Failures should use the normal failure primitives and return useful status codes.
# > Interactive instructions, confirmations, and selection dialogs should use the shared
# > UI/input helpers rather than reimplementing a private interaction model.
#
# -- DRYRUN and Safety ---------------------------------------------------------------
#
# > Mutating actions must honor the Framework DRYRUN contract. A role manager invoked
# > from a dry-run console session must not make persistent changes simply because work
# > crossed an executable boundary.
#
# > Validation and status actions should remain useful in both direct and console-driven
# > execution so an operator can inspect the target before or after a change.
#
# -- Relationship to Module Registration -------------------------------------------
#
# > The intended split is:
# >
# >     Module Registration
# >         operator-facing page, grouping, menu actions, orchestration
# >
# >     Role Managers
# >         independently executable operational behavior
# >
# >     Framework libraries
# >         reusable bootstrap, UI, logging, configuration/state, and common APIs
#
# > That boundary is what lets the Management Console remain a management interface
# > rather than becoming the only place where server-management behavior can run.
