# ==================================================================================
# SolidGroundUX Management Console Modules - Console Modules Introduction
# ----------------------------------------------------------------------------------
# Metadata:
#   Version     : 2.1
#   Build       : 2625813
#   Checksum    : -
#   Source      : management-console-modules_preface.sh
#   Type        : documentation template
#   Group       : SolidGroundUX Management Console Modules
#   Purpose     : Documentation preface/epilogue template for SolidGroundUX framework.
#
# Attribution:
#   Developers  : Mark Fieten
#   Company     : Testadura Consultancy
#   Client      : -
#   Copyright   : © 2025 - 2026 Testadura Consultancy
#   License     : Licensed under the Testadura Non-Commercial License (TD-NC) v1.1.
# ==================================================================================

# - SolidGroundUX Management Console Modules ----------------------------------------
# . Images
#   mcm.png :: SolidGround Management Console, the host application.
#
# > SolidGroundUX began with a practical goal: 
# ~    make configuring and managing Linux servers consistent, repeatable and considerably less tedious. 
# >
# > As the framework matured, the management functionality built on top of it grew into 
# > something substantial in its own right. As of version 2.1 of the framework, that 
# > functionality became a separate product: SolidGroundUX Management Console Modules.
# > The separation is architectural rather than merely organizational. SolidGroundUX provides the runtime, 
# > conventions, APIs, console infrastructure and reusable framework services. 
# > The Management Console Modules are designed to run through the framework executable sgnd-console. They 
# > began as a way to showcase the SolidGroundUX Management Console....
# > 
# > The Management Console Modules have evolved into a collection of shell scripts covering a broad range 
# > of practical server-management tasks. They have been tested extensively on Ubuntu 24.04 LTS and 25.04.
# >
# > In practice they have demonstrated that configuring a Samba AD domain controller, a Samba file server, 
# > a SQL Server host and an Nginx web server can be reduced from hours of repetitive configuration 
# > to a largely guided and repeatable process.
# >
# : A little bragging
# > During end-to-end testing, configuring a Samba AD domain controller, Samba file server,
# > SQL Server host and Nginx web server took little over half an hour, including basic user and share configuration.
# >
# -- Architecture
# > The Management Console Modules are implemented as a collection of shell scripts, that all reside in a directory.
# > sgnd-console is the host application which takes a paramaeter to load a module or all modules in a directory.
# > This directory defaults to usr/local/libexec/solidgroundux/console-modules.
# > The actual module scripts are named with a two-digit prefix to control the order in which they are loaded, the 
# > consist mostly of menuregistration calls, and mayube a little local helper. These menu registrations call a separate
# > executable, that handles the actual work.
# > The 'action' scripts are selfcontained executables and leverage SolidGroundUX and could be called outside sgnd-console
# . Images
#   mcm-architecture.png :: SolidGround Management Console Modules Architecture.
# >
# . Table
# ! Module :: Executable :: Common
#   10-computer-setup.sh :: set-identity.sh ::
#   15-storage.sh :: manage-storage.sh ::
#   20-active-directory-server.sh :: manage-active-directory-server.sh :: active-directory-management.sh
#   25-active-directory-client.sh :: manage-active-directory-client.sh :: active-directory-management.sh
#   27-active-directory-management.sh :: manage-active-directory.sh :: active-directory-management.sh
#   30-samba-file-server.sh :: manage-samba-file-server.sh ::
#   30-samba-file-server.sh :: manage-samba-shares.sh ::
#   40-solidgroundux.sh :: manage-solidgroundux.sh ::
#   45-solidground-framework-test.sh :: framework-smoketest.sh ::
#   50-web-server.sh :: manage-web-server.sh ::
#   50-web-server.sh :: publish-web-content.sh ::
#   60-sqlserver.sh :: manage-sqlserver.sh ::
#   70-docker-server.sh :: manage-docker-server.sh ::
#   70-docker-server.sh :: manage-docker-containers.sh ::
#   90-development.sh :: ::
# . EndTable
