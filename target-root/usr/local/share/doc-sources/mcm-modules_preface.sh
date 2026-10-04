# ==================================================================================
# SolidGroundUX Management Console Modules - Module Registration
# ----------------------------------------------------------------------------------
# Metadata:
#   Version     : 2.1
#   Build       : 2627700
#   Checksum    : 1097c01140043aee179ddf7677fce60b7e0445fcb2aaad4cce852ca70e1966ae
#   Source      : mcm-modules_preface.sh
#   Type        : documentation
#   Group       : Module Registration
#   Purpose     : Group preface
#
# Attribution:
#   Developers  : Mark Fieten
#   Company     : Testadura Consultancy
#   Client      : -
#   Copyright   : © 2025 - 2026 Testadura Consultancy
#   License     : Licensed under the Testadura Non-Commercial License (TD-NC) v1.1.
# ==================================================================================
# - Module Registration -------------------------------------------------------------
#
# > Management Console modules define the guided pages shown by `sgnd-console`. They are
# > orchestration and registration units: each module describes its page, groups, menu
# > items, validation entry points, and the actions that should be invoked for its subject.
#
# > A console module is not the preferred home for reusable system-management logic.
# > Persistent operational work belongs in the corresponding role manager or shared
# > library so the same operation can be tested and invoked outside the console host.
#
# -- Lazy Loading -------------------------------------------------------------------
#
# > The console discovers module metadata without sourcing every implementation. A module
# > is sourced only when its page is opened and remains loaded for the life of that
# > console process.
#
# > Modules must therefore be self-contained at load time. They must not rely on another
# > page having been opened first, and cross-module helpers belong in a commonly owned
# > library rather than in one of the participating module files.
#
# -- Registration Contract ----------------------------------------------------------
#
# > Once loaded, a module registers its groups and menu items through the Framework-owned
# > menu API. Functions referenced by registrations must already be defined, and the
# > normal source-only/library guard keeps repeated sourcing harmless.
#
# > Numeric filename prefixes determine page ordering. Group/item ordering is local to the
# > module and expresses the operator-facing workflow for that page.
#
# -- Action Boundary ----------------------------------------------------------------
#
# > Menu actions may perform lightweight orchestration directly, but system-changing work
# > should normally delegate to a role manager. The module is responsible for passing the
# > relevant execution context, including DRYRUN, and for presenting completion/status in
# > the standard console interaction model.
#
# > This split keeps the UI declarative and the operational code independently reusable.
#
# -- Documentation ------------------------------------------------------------------
#
# > The generated reference beneath this group documents the individual module pages and
# > their registration contracts. The Console documentation describes host behavior,
# > navigation, paging, visibility, and lifecycle rules shared by all modules.
