# ==================================================================================
# SolidGroundUX - Web Content Management Overview
# ----------------------------------------------------------------------------------
# Metadata:
#   Version     : 2.2
#   Type        : documentation
#   Group       : Modules
#   Subgroup    : Web Content Management
#   Purpose     : Subgroup preface
#
#   Build : 2630620
#   Checksum : 6ca8ce3422c04f440e9e061186a06caa591094660be07a744758cbf6e69c3d87
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
# ![Web Content Management workflows - Two independent workflows: source documentation is converted into a Markdown repository, which can optionally serve as input for website generation and publication.](/assets/mcm-wcm-workflows.png)
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
