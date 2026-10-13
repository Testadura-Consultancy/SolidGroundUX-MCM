"""Non-interactive command-line adapter for the WebContent package."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys

from .deletion import delete_content, inspect_delete
from .sections import list_sections, create_section, inspect_section, remove_section
from .management import list_pages, edit_metadata, move_page
from .generator import generate_site
from .ingestion import ingest_content, inspect_ingest
from .social import prepare_social
from .validation import validate_site


def _write_result(payload: dict[str, object], result_file: str | None) -> None:
    """Write result to generated output."""
    encoded = json.dumps(payload, ensure_ascii=False, indent=2)
    if result_file:
        path = Path(result_file).expanduser()
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(encoded + "\n", encoding="utf-8")
    else:
        sys.stdout.write(encoded + "\n")


def _add_ingest_fields(parser: argparse.ArgumentParser) -> None:
    """Add normalized metadata fields shared by ingest preview and commit calls."""
    parser.add_argument("--source", required=True)
    parser.add_argument("--input-file", required=True)
    parser.add_argument("--title", required=True)
    parser.add_argument("--language", required=True)
    parser.add_argument("--parent", required=True)
    parser.add_argument("--kind", required=True, choices=["page", "section", "article"])
    parser.add_argument("--slug", required=True)
    parser.add_argument("--summary", default="")
    parser.add_argument("--result-file")


def _parser() -> argparse.ArgumentParser:
    """Handle parser for the web content workflow."""
    parser = argparse.ArgumentParser(prog="sgnd-webcontent", description="Generate, validate, ingest, and delete static web content repositories.")
    subparsers = parser.add_subparsers(dest="command", required=True)

    validate = subparsers.add_parser("validate", help="Validate a web content repository.")
    validate.add_argument("--source", required=True)
    validate.add_argument("--result-file")

    generate = subparsers.add_parser("generate", help="Generate a static website.")
    generate.add_argument("--source", required=True)
    generate.add_argument("--output", required=True)
    generate.add_argument("--language", default="ALL")
    generate.add_argument("--mode", choices=["public", "preview"], default="public")
    generate.add_argument("--rss", action="store_true", help="Generate an RSS feed for dated articles (public only).")
    generate.add_argument("--result-file")

    social = subparsers.add_parser("prepare-social", help="Prepare platform-specific social-media drafts.")
    social.add_argument("--source", required=True)
    social.add_argument("--output", required=True)
    social.add_argument("--platform", default="linkedin")
    social.add_argument("--content-file", required=True)
    social.add_argument("--excerpt-length", type=int, default=150)
    social.add_argument("--result-file")

    inspect = subparsers.add_parser("inspect-ingest", help="Inspect one loose Markdown file and return ingest defaults/options.")
    inspect.add_argument("--source", required=True)
    inspect.add_argument("--input-file", required=True)
    inspect.add_argument("--language", default="")
    inspect.add_argument("--result-file")

    preview = subparsers.add_parser("preview-ingest", help="Validate metadata and preview the canonical ingest destination.")
    _add_ingest_fields(preview)

    ingest = subparsers.add_parser(
        "ingest",
        help="Ingest one Markdown file into the canonical content tree and archive its original source.",
    )
    _add_ingest_fields(ingest)

    inspect_delete_parser = subparsers.add_parser(
        "inspect-delete",
        help="List canonical child pages that can be deleted safely.",
    )
    inspect_delete_parser.add_argument("--source", required=True)
    inspect_delete_parser.add_argument("--result-file")

    for command, help_text in (
        ("preview-delete", "Preview recoverable deletion of one canonical content page."),
        ("delete", "Archive one canonical content page and remove it from the active content tree."),
    ):
        delete_parser = subparsers.add_parser(command, help=help_text)
        delete_parser.add_argument("--source", required=True)
        delete_parser.add_argument("--content-file", required=True)
        delete_parser.add_argument("--recursive", action="store_true")
        delete_parser.add_argument("--all-languages", action="store_true")
        delete_parser.add_argument("--result-file")

    pages = subparsers.add_parser("list-pages", help="Browse canonical pages and their metadata.")
    pages.add_argument("--source", required=True)
    pages.add_argument("--result-file")
    edit = subparsers.add_parser("edit-metadata", help="Change one front matter value without touching the body.")
    edit.add_argument("--source", required=True)
    edit.add_argument("--content-file", required=True)
    edit.add_argument("--key", required=True)
    edit.add_argument("--value", required=True)
    edit.add_argument("--result-file")
    move = subparsers.add_parser("move-page", help="Move or rename one article or page.")
    move.add_argument("--source", required=True)
    move.add_argument("--content-file", required=True)
    move.add_argument("--parent", required=True)
    move.add_argument("--slug", required=True)
    move.add_argument("--result-file")
    sections = subparsers.add_parser("list-sections", help="List existing sections and parents.")
    sections.add_argument("--source", required=True)
    sections.add_argument("--result-file")
    create = subparsers.add_parser("create-section", help="Create draft section indexes.")
    create.add_argument("--source", required=True)
    create.add_argument("--parent", default="")
    create.add_argument("--slug", required=True)
    create.add_argument("--title-nl", default="")
    create.add_argument("--title-en", default="")
    create.add_argument("--languages", default="NL,EN")
    create.add_argument("--result-file")
    inspect_section_parser = subparsers.add_parser("inspect-section", help="Inspect section subtree before removal.")
    inspect_section_parser.add_argument("--source", required=True)
    inspect_section_parser.add_argument("--section", required=True)
    inspect_section_parser.add_argument("--result-file")
    remove = subparsers.add_parser("remove-section", help="Move, archive or permanently delete a section tree.")
    remove.add_argument("--source", required=True)
    remove.add_argument("--section", required=True)
    remove.add_argument("--mode", required=True, choices=["move", "archive", "delete"])
    remove.add_argument("--destination", default="")
    remove.add_argument("--archive-root", default="")
    remove.add_argument("--result-file")
    return parser


def main(argv: list[str] | None = None) -> int:
    """Parse command-line arguments and dispatch the requested command.
    
    Args:
        argv: Input used by this operation.
    
    Returns:
        Operation result or None, as defined by the implementation."""
    args = _parser().parse_args(argv)
    try:
        if args.command in {"list-sections", "create-section", "inspect-section", "remove-section"}:
            if args.command == "list-sections":
                payload = list_sections(args.source)
            elif args.command == "create-section":
                payload = create_section(args.source, args.parent, args.slug, args.title_nl, args.title_en, args.languages)
            elif args.command == "inspect-section":
                payload = inspect_section(args.source, args.section)
            else:
                payload = remove_section(args.source, args.section, args.mode, args.destination, args.archive_root)
            _write_result(payload, args.result_file)
            return 0
        if args.command == "list-pages":
            payload = list_pages(args.source)
            _write_result(payload, args.result_file)
            return 0
        if args.command == "edit-metadata":
            payload = edit_metadata(args.source, args.content_file, args.key, args.value)
            _write_result(payload, args.result_file)
            return 0
        if args.command == "move-page":
            payload = move_page(args.source, args.content_file, args.parent, args.slug)
            _write_result(payload, args.result_file)
            return 0
        if args.command == "validate":
            result = validate_site(args.source)
        elif args.command == "generate":
            result = generate_site(args.source, args.output, args.language, mode=args.mode, rss=args.rss)
        elif args.command == "prepare-social":
            result = prepare_social(args.source, args.output, args.platform, args.content_file, args.excerpt_length)
        elif args.command == "inspect-ingest":
            result = inspect_ingest(args.source, args.input_file, args.language)
        elif args.command == "inspect-delete":
            result = inspect_delete(args.source)
        elif args.command == "preview-delete":
            result = delete_content(
                args.source,
                args.content_file,
                recursive=args.recursive,
                all_languages=args.all_languages,
                commit=False,
            )
        elif args.command == "delete":
            result = delete_content(
                args.source,
                args.content_file,
                recursive=args.recursive,
                all_languages=args.all_languages,
                commit=True,
            )
        elif args.command == "preview-ingest":
            result = ingest_content(
                args.source,
                args.input_file,
                title=args.title,
                language=args.language,
                parent=args.parent,
                kind=args.kind,
                slug=args.slug,
                summary=args.summary,
                commit=False,
            )
        else:
            result = ingest_content(
                args.source,
                args.input_file,
                title=args.title,
                language=args.language,
                parent=args.parent,
                kind=args.kind,
                slug=args.slug,
                summary=args.summary,
                commit=True,
            )
        payload = result.as_dict()
        _write_result(payload, getattr(args, "result_file", None))
        return 0 if bool(payload.get("success")) else 1
    except Exception as exc:
        payload = {"success": False, "errors": [str(exc)]}
        _write_result(payload, getattr(args, "result_file", None))
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
