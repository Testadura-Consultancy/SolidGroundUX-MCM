# ==================================================================================
# SolidGroundUX Management Console Modules - Module Registration
# ----------------------------------------------------------------------------------
# Metadata:
#   Version     : 2.2
#   Build       : 2630700
#   Checksum    : 760417477781b94973909f74e582d45e5970ffebc31bdff7acedaa8568e956bb
#   Source      : mcm-modules_preface.sh
#   Type        : documentation
#   Group       : Modules
#   Purpose     : Group preface
#
# Attribution:
#   Developers  : Mark Fieten
#   Company     : Testadura Consultancy
#   Client      : -
#   Copyright   : © 2025 - 2026 Testadura Consultancy
#   License     : Licensed under the Testadura Non-Commercial License (TD-NC) v1.1.
# ==================================================================================
# - Modules -------------------------------------------------------------------------
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
# > Each functional subsection contains both its console registration page and the
# > corresponding operational role managers. The console host documentation describes
# > navigation, paging, visibility and lifecycle rules common to all modules.
