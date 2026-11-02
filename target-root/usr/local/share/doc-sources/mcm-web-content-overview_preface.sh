# ==================================================================================
# SolidGroundUX - Web Content Management Overview
# ----------------------------------------------------------------------------------
# Metadata:
#   Version     : 2.1
#   Type        : documentation
#   Group       : Modules
#   Subgroup    : Web Content Management
#   Purpose     : Subgroup preface
#
# Attribution:
#   Developers  : Mark Fieten
#   Company     : Testadura Consultancy
#   Copyright   : (c) 2025 - 2026 Testadura Consultancy
#   License     : Licensed under the Testadura Non-Commercial License (TD-NC) v1.1.
# ==================================================================================
# -- Two processes, one optional hand-off -------------------------------------------
#
# Web Content Management brings together two independent workflows. The first
# builds a **Markdown documentation repository from source comments and docstrings**.
# The second **builds a static website from a selected Markdown repository**.
# They share Markdown as a possible hand-off, not as a mandatory coupling.
#
# ```text
#  Framework / SDK / MCM source
#             |
#             v
#   Documentation bundle manager
#             |
#             v
#    Markdown documentation repo -----------+
#                                            |
#    Independently authored Markdown ------+---> Select WCM source
#                                                   |
#                                           Validate / generate
#                                                   |
#                                              HTML + assets
#                                                   |
#                                             Review locally
#                                                   |
#                                           Publish via SSH/rsync
#                                                   |
#                                               Nginx host
# ```
#
# Each Markdown repository is an **alternative source**. Documentation generation
# does not build a website; website generation does not automatically deploy it.
# An authored website may bypass the bundle workflow entirely.
#
# -- Read the workflow guides -------------------------------------------------------
#
# | Guide | Purpose | Main output |
# | --- | --- | --- |
# | [Documentation Generation and Authoring](../mcm-documentation-preface/) | Save bundles, extract source documentation, author comments, functions and examples | Navigable Markdown documentation repository |
# | [Markdown Repository to Website](../mcm-web-content-manager-preface/) | Manage Markdown content, generate public/preview HTML, and publish through MCM | Static website on the configured web server |
#
# The console modules expose user actions; Python implements the bundle/Markdown
# conversion and website renderer; Bash publication tools perform remote transfer.
# The steps may be run independently and do not imply a Git commit or deployment.
