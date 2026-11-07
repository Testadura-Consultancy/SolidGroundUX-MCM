# ==================================================================================
# SolidGroundUX MCM - Python Modules
# ----------------------------------------------------------------------------------
# Metadata:
#   Version     : 2.2
#   Source      : mcm-python-modules_preface.sh
#   Type        : documentation
#   Group       : Python Modules
#   Purpose     : Group preface
#
#   Build : 2631102
#   Checksum : 3e6efa8b80c47c022279e7ba27c570196e6919c155e3904dc78239db06f7c765
# Attribution:
#   Developers  : Mark Fieten
#   Company     : Testadura Consultancy
#   Copyright   : (c) 2025 - 2026 Testadura Consultancy
#   License     : Testadura Non-Commercial License (TD-NC) v1.1.
# ==================================================================================
# - Why Python belongs to MCM -------------------------------------------------------
# Python handles the work that benefits from structured data, filesystem traversal,
# source parsing and deterministic content transformation. Bash remains the operator
# interface: the Management Console shows menus, prompts for choices and orchestrates
# external operations through the Framework's UI and execution APIs.
#
# The Python files are part of **Management Console Modules**, not a separate service
# and not an SDK implementation. They are invoked when an MCM documentation or Web
# Content Management action needs to read, validate, transform or generate content.
# The generated website is static: serving its HTML does not require running Python.
#
# There are two related, but independently usable, workflows:
#
# - **Documentation preparation** turns structured source documentation from the
#   Framework, SDK and MCM into a WebContent-compatible Markdown repository.
# - **Web Content Management** maintains Markdown content, validates it, and turns
#   it into a static website. It can also work with authored Markdown unrelated to
#   documentation bundles.
#
# -- Component and process overview ------------------------------------------------
# The diagram shows the principal execution boundaries and the artefacts exchanged.
# The two workflows meet at a **Markdown source tree**, not at the Python API level.
#
# ```text
#    MCM console (Bash)                               MCM console (Bash)
#       Manage / Generate bundles                         Web Content Management
#                 |                                                |
#                 v                                                v
#       sgnd_doc_bundles.py                                 webcontent/cli.py
#       Saved bundle JSON                                  Command dispatcher
#                 |                                                |
#                 v                                 +--------------+-------------+
#       sgnd_doc_markdown.py                        |              |             |
#       Parse and classify                  Incoming content   Page/section   Validation
#       Bash/Python source                 staging/ingestion   management        |
#                 |                                 |              |             |
#                 +--------------+------------------+--------------+-------------+
#                                |
#                                v
#                    WebContent Markdown source tree
#                    content / templates / CSS / assets
#                                |
#                                v
#                    webcontent/generator.py
#                    + markdown.py + templates.py
#                                |
#                                v
#                       Generated static HTML
#                                |
#                                v
#                    MCM publishing tools (Bash)
#                    Local or remote website root
# ```
#
# -- Documentation preparation ------------------------------------------------------
# The bundle manager (`manage-bundles.sh`) calls `sgnd_doc_bundles.py` to store named
# bundle configurations as JSON, select their ordered product sources, and validate
# input and output paths. This component **does not generate pages**.
#
# The separate Generate documentation bundle action calls `sgnd_doc_markdown.py`.
# It reads the selected bundle and its Bash/Python source files, interprets script
# metadata, function/class documentation, prefaces and epilogues, and creates a
# navigable Markdown repository with indexes, assets, and source statistics.
#
# This is a **source documentation compiler**, not the website renderer. Its output
# is a Markdown input repository that can subsequently be processed by WebContent.
# Documentation generation and website generation are intentionally separate steps.
#
# -- Web Content Management ---------------------------------------------------------
# `webcontent/cli.py` is the non-interactive command-line adapter used by the MCM
# Web Content Management workflows. It dispatches requests into smaller modules:
#
# | Component | Responsibility |
# | --- | --- |
# | `content.py` | Discover content and read site configuration and front matter. |
# | `incoming_transfer.py`, `incoming_plan.py` | Review and stage incoming files without silently changing published content. |
# | `incoming_commit.py`, `incoming_archive.py`, `ingestion.py` | Accept reviewed content, manage conflicts and archive ingested inputs. |
# | `management.py`, `sections.py`, `deletion.py` | Manage page metadata, paths, section trees and recoverable removal. |
# | `validation.py` | Check the website's source structure and content before generation. |
# | `markdown.py`, `templates.py` | Render supported Markdown and compose HTML templates. |
# | `generator.py` | Assemble navigation, pages and static output from the source repository. |
# | `social.py` | Prepare an article-based social-media draft. |
# | `webcontent-upload-service.py` | Receive authorized uploads into a staging area; it does not publish the files. |
#
# Most of these modules are **libraries**. They expose functions to their callers
# instead of running servers or menus by themselves. The upload receiver is the
# deliberate exception: it runs as a separate loopback-only upload service, behind
# the web server's authentication and HTTPS configuration.
#
# -- Generation is not publication --------------------------------------------------
# WebContent can render the repository into **static HTML** using the configured
# content, templates, images, CSS and other assets. The generator operates locally;
# it does not deploy files to a remote web server merely by generating them.
#
# Publishing is orchestrated by MCM's **Bash** web-management/publishing tools,
# such as `publish-web-content.sh`, which handle destination selection and transfer.
# Keeping publishing separate allows the same generated website to be inspected
# before deployment and keeps transport credentials out of the Python renderer.
#
# -- Reading the API documentation --------------------------------------------------
# Each Python source file has its own page. **Public functions** have individual
# reference entries, while **Internal functions** are summarized in a collapsible
# section. Explicit Public/Internal source headings can override the underscore
# naming heuristic without renaming functions or changing program behaviour.
#
# Module and function docstrings describe their contracts; the architecture above
# describes how those contracts cooperate in the larger MCM workflows.
