"""Prepare a social-media draft for one selected repository article."""

from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path
import re
import shutil

from .content import discover_content, load_navigation, load_site_config


@dataclass(slots=True)
class SocialResult:
    """Generated social-media draft paths and reported diagnostics."""
    success: bool
    output: str
    platform: str
    drafts_generated: int = 0
    warnings: list[str] = field(default_factory=list)
    errors: list[str] = field(default_factory=list)

    def as_dict(self) -> dict[str, object]:
        """Serialize the result to a JSON-compatible mapping.
        
        Returns:
            Operation result or None, as defined by the implementation."""
        return {"success": self.success, "output": self.output, "platform": self.platform,
                "drafts_generated": self.drafts_generated, "warnings": self.warnings,
                "errors": self.errors}


def _plain_text(body: str) -> str:
    """Extract readable prose, not Markdown or td-component markup."""
    body = re.sub(r"```[\s\S]*?```", " ", body)
    body = re.sub(r"(?m)^\s*:::[^\n]*$", " ", body)
    body = re.sub(r"!\[[^]]*\]\([^)]*\)", " ", body)
    body = re.sub(r"\[([^]]+)\]\([^)]*\)", r"\1", body)
    body = re.sub(r"(?m)^\s*[#>\-*]+\s*", "", body)
    body = re.sub(r"<[^>]*>", " ", body)
    body = re.sub(r"[`*_~]", "", body)
    return re.sub(r"\s+", " ", body).strip()


def _excerpt(body: str, limit: int) -> str:
    """Extract a readable short text excerpt for a social-media draft."""
    text = _plain_text(body)
    if len(text) <= limit:
        return text
    cropped = text[:limit].rsplit(" ", 1)[0].strip() or text[:limit]
    return cropped.rstrip(".,;: ") + "..."


def prepare_social(source: str | Path, output: str | Path, platform: str = "linkedin",
                   content_file: str = "", excerpt_length: int = 150) -> SocialResult:
    """Write one editable draft and optional image, without modifying site sources."""
    source_path = Path(source).resolve()
    output_path = Path(output).expanduser().resolve()
    platform = platform.strip().lower()
    if not re.fullmatch(r"[a-z0-9_-]+", platform):
        return SocialResult(False, str(output_path), platform, errors=["Invalid platform name"])
    if not 1 <= excerpt_length <= 20000:
        return SocialResult(False, str(output_path), platform, errors=["Invalid excerpt length"])
    if not content_file:
        return SocialResult(False, str(output_path), platform, errors=["Select one article first"])
    try:
        config = load_site_config(source_path)
        selected_path = (config.content_dir / content_file).resolve()
        if not selected_path.is_relative_to(config.content_dir.resolve()):
            raise ValueError("Selected file is outside the content directory")
        items = discover_content(config, load_navigation(source_path))
        item = next((i for i in items if i.source_path.resolve() == selected_path), None)
        if item is None:
            raise ValueError("Selected article not found in repository")
        if item.base_name == "index":
            raise ValueError("Select an article, not a section index")
        if item.draft:
            raise ValueError("Draft articles have no public URL; publish the article first")
        if not config.base_url:
            raise ValueError("Configure the site's public base_url first")
        if output_path == source_path or output_path.is_relative_to(source_path):
            raise ValueError("Social output directory must be outside the website repository")
        teaser = str(item.metadata.get("teaser") or "").strip()
        summary = str(item.metadata.get("summary") or "").strip()
        intro = teaser or summary or _excerpt(item.body, excerpt_length)
        if not intro:
            raise ValueError("Article has no usable text")
        url = config.base_url.rstrip("/") + item.route
        post = f"{intro}\n\nLees meer: {url}\n" if item.language == "NL" else f"{intro}\n\nRead more: {url}\n"
        identifier = re.sub(r"[^a-zA-Z0-9_-]", "-", selected_path.stem).strip("-")
        article_dir = output_path / platform / identifier
        if article_dir.exists():
            raise ValueError(f"Output already exists: {article_dir}; move or remove it before preparing again")
        article_dir.mkdir(parents=True)
        (article_dir / "post.txt").write_text(post, encoding="utf-8")
        (article_dir / "source.txt").write_text(f"Title: {item.title}\nLanguage: {item.language}\nSource: {selected_path}\nURL: {url}\n", encoding="utf-8")
        warnings = []
        image_value = str(item.metadata.get("featured_image") or item.metadata.get("image") or item.metadata.get("index_image") or "").strip()
        if image_value:
            image_path = (config.root / image_value.lstrip("/")).resolve()
            if image_path.is_file() and image_path.is_relative_to(config.root):
                shutil.copy2(image_path, article_dir / ("image" + image_path.suffix.lower()))
            else:
                warnings.append(f"Image not available locally: {image_value}")
        return SocialResult(True, str(article_dir), platform, 1, warnings)
    except (OSError, ValueError) as exc:
        return SocialResult(False, str(output_path), platform, errors=[str(exc)])
