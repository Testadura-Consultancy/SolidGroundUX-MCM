#!/usr/bin/env bash
# ==================================================================================
# SolidGroundUX SDK - Documentation Sample
# ----------------------------------------------------------------------------------
# Description:
#   This file is a documentation fixture and style guide.
#
#   It demonstrates:
#     - The fixed module header structure
#     - Module header metadata and attribution sections
#     - Developer prose inside the module header
#     - Function, variable, and general documentation labels
#     - Normal and template documentation item markers
#     - Plain documentation lines
#     - Style hints
#     - Function arguments
#
# Notes:
#   The first module header line is always a banner line.
#   The second module header line is always:
#
#     SolidGroundUX - Documentation Sample
#
#   The third module header line is always a separator line.
#
#   Metadata and Attribution are fixed header sections. Other header sections may be
#   used for developer comments or module-level prose.
#
# Metadata:
#   Version     : 2.1
#   Build       : 2627501
#   Checksum    : d77cb35fd66f8ac7780a4f69e76882ff3761d2b6d8030404af5c99d7016c6c00
#   Source      : doc-sample.sh
#   Type        : documentation
#   Group       : SDK
#   Subgroup    : Documentation Authoring
#   Purpose     : Demonstrate all supported SolidGroundUX documentation comment
#                 conventions, content labels, item markers, and style hints.
#
# Attribution:
#   Developers  : Mark Fieten
#   Company     : Testadura Consultancy
#   Client      : -
#   Copyright   : © 2025 - 2026 Testadura Consultancy
#   License     : Licensed under the Testadura Non-Commercial License (TD-NC) v1.1.
# ==================================================================================

set -uo pipefail


# doc: content_labels - Documentation content labels
    # > The primary labels are:
    #
    # >     fn:      Function documentation
    # >     var:     Variable documentation
    # >     doc:     General documentation
    #
    # > Each label can be followed by either a colon or a dollar sign.
    #
    # > A colon indicates a normal documentation item:
    #
    # >     fn:      Normal function documentation
    # >     var:     Normal variable documentation
    # >     doc:     Normal general documentation
    #
    # > A dollar sign indicates a template documentation item:
    #
    # >     fn$      Template function documentation
    # >     var$     Template variable documentation
    # >     doc$     Template general documentation


# doc: style_hints - Documentation line markers and style hints
    # > The plain documentation marker is:
    #
    # >     >           Plain documentation line
    # >     >           When used without text, emits an intentional blank line
    #
    # > Style hints are presentation hints layered on top of the structural content type.
    # > The renderer reads the exported stylehint value for each documentation line.
    # > When the style hint is normal, no additional style class is added. When another
    # > value is supplied, the renderer adds a corresponding sh-<stylehint> CSS class.
    #
    # > The currently supported style hints are:
    #
    # >     normal      Standard rendered text
    # >     label       (:) Label or small subheader text
    # >     highlight   (.) Highlighted text
    # >     emphasis    (!) Emphasized text
    # >     underline   (_) Underlined text
    # >     quote       (~) Quoted or aside text
    # >     listitem    (-) Bullet-style list item
    # >     indent          Reserved indentation style


# doc: style_hint_examples - Style hint examples
    # > This is a normal documentation line.
    #
    # : This is a label line.
    # . This is a highlighted line.
    # ! This is an emphasized line.
    # _ This is an underlined line.
    # ~ This is a quoted or aside line.
    # - This is a list item.
    # - This is another list item.


# fn: sample_public_function - Sample public function
    # . Purpose
    #   Demonstrate the no-argument public function documentation format.
    #
    # . Behavior
    #   - Provides a public SolidGroundUX helper or command entry point.
    #   - Demonstrates a function without arguments.
    #
    # . Returns
    #   0 always; the function is a documentation-only example.
    #
    # . Usage
    #   ```bash
    #   sample_public_function
    #   ```
sample_public_function() {
    return 0
}


# fn: sample_function_with_arguments - Sample function with arguments
    # . Purpose
    #   Demonstrate how function arguments are documented.
    #
    # . Behavior
    #   - Accepts one required argument.
    #   - Accepts one optional argument.
    #   - Writes both resolved values to stdout.
    #
    # . Arguments
    #   $1  Required source value.
    #   $2  Optional target value. Defaults to stdout.
    #
    # . Output
    #   Writes the resolved source and target values to stdout.
    #
    # . Returns
    #   0  Arguments were accepted.
    #   2  Required source value was missing.
    #
    # . Usage
    #   ```bash
    #   sample_function_with_arguments "input" "output"
    #   ```
sample_function_with_arguments() {
    if [[ $# -lt 1 ]]; then
        printf 'Missing required argument: source\n' >&2
        return 2
    fi

    local source_value="$1"
    local target_value="${2:-stdout}"

    printf 'source=%s target=%s\n' "$source_value" "$target_value"
}


# fn: _sample_internal_function - Internal function documentation
    # . Purpose
    #   Demonstrate an internal function.
    #
    # . Behavior
    #   - A leading underscore marks the function as internal.
    #   - The name indicates a private helper; this sample performs no work.
    #
    # . Returns
    #   0 on success.
    #
    # . Usage
    #   ```bash
    #   _sample_internal_function
    #   ```
_sample_internal_function() {
    return 0
}


# fn$ sample_template_function - Sample template function
    # . Purpose
    #   Describe what the function does.
    #
    # . Behavior
    #   - Describe the important behavior.
    #
    # . Arguments
    #   $1  Describe the first argument.
    #   $2  Describe the second argument.
    #
    # . Inputs
    #   Describe relevant global inputs, or use None.
    #
    # . Outputs
    #   Describe modified globals, or use None.
    #
    # . Output
    #   Describe stdout/stderr output, or use None.
    #
    # . Side effects
    #   Describe filesystem, process, network, or state changes, or use None.
    #
    # . Returns
    #   0  Success.
    #   1  General failure.
    #
    # . Usage
    #   ```bash
    #   sample_template_function
    #   ```
    # . Examples
    #   ```bash
    #   sample_template_function "source" "target"
    #   ```
sample_template_function() {
    return 0
}


# var: SAMPLE_PUBLIC_VARIABLE - Public variable documentation
    # . Purpose
    #   Demonstrate a normal documented variable.
    #
    # . Behavior
    #   - Creates a variable item.
    #   - Uses the variable header/body content type.
    #   - Is included in the variable glossary.
    #
    # . Default
    #   empty
SAMPLE_PUBLIC_VARIABLE=""


# var: _SAMPLE_INTERNAL_VARIABLE - Internal variable documentation
    # . Purpose
    #   Demonstrate an internal variable.
    #
    # . Behavior
    #   - A leading underscore marks the variable as internal.
    #   - The renderer may use this visibility metadata later.
_SAMPLE_INTERNAL_VARIABLE=""


# var$ SAMPLE_TEMPLATE_VARIABLE - Template variable documentation
    # . Purpose
    #   Demonstrate the var$ template marker.
    #
    # . Behavior
    #   - The dollar marker means this is a template/example variable.
    #   - Template variables are only shown when the module belongs to the Templates group.
    #
    # . Notes
    #   If a real module implements this variable, document it with var: instead of var$.
SAMPLE_TEMPLATE_VARIABLE=""


# doc: recommended_item_sections - Recommended item sections
    # . Purpose
    #   Demonstrate the preferred prose structure for documented items.
    #
    # . Recommended labels
    #   Purpose
    #   Behavior
    #   Arguments
    #   Inputs
    #   Outputs
    #   Output
    #   Side effects
    #   Returns
    #   Usage
    #   Examples
    #   Notes
    #
    # . Notes
    #   Omit sections that are not applicable. Function arguments should be documented
    #   when the function accepts positional arguments.


# doc$ general_documentation_template - General documentation template
    # > Write normal prose using the plain documentation marker.
    #
    # : Label
    # > Add labeled explanation where useful.
    #
    # . Highlight
    # > Add highlighted explanation where useful.
    #
    # ! Important
    # > Add important or emphasized notes where useful.
    #
    # _ Underline
    # > Add underlined documentation where useful.
    #
    # ~ Quote
    # > Add quoted or aside text where useful.
    #
    # - Add list items where useful.
    # - Keep list items concise.


# doc: empty_section_example - Empty section example
    # > This section intentionally contains body text, so it is not considered empty.
    # > A section with no body text, no visible items, and no visible child sections should
    # > be omitted from the index by the renderer.
