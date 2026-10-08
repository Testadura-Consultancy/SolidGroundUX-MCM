"""Template-driven social-media draft generation."""

from __future__ import annotations

from dataclasses import dataclass, field
import re
from pathlib import Path

from .content import ContentItem, discover_content, load_navigation, load_site_config
from .templates import load_template, render_template
from .validation import validate_site


@dataclass(slots=True)
class SocialResult:
    success: bool
    output: str
    platform: str
    drafts_generated: int = 0
    warnings: list[str] = field(default_factory=list)
    errors: list[str] = field(default_factory=list)

    def as_dict(self) -> dict[str, object]:
        return {
            "success": self.success,
            "output": self.output,
            "platform": self.platform,
            "drafts_generated": self.drafts_generated,
            "warnings": self.warnings,
            "errors": self.errors,
        }


def _social_settings(item: ContentItem, platform: str) -> tuple[bool, str]:
    social = item.metadata.get("social")
    intro = str(item.metadata.get("social_intro", "") or "")

    if social is None:
        return False, intro
    if isinstance(social, bool):
        return social, intro
    if isinstance(social, list):
        return platform in {str(value).lower() for value in social}, intro
    if isinstance(social, str):
        value = social.strip().lower()
        return value in {"true", "yes", "draft", platform}, intro
    if isinstance(social, dict):
        setting = social.get(platform)
        if isinstance(setting, dict):
            enabled = bool(setting.get("enabled", True))
            intro = str(setting.get("intro", intro) or intro)
            return enabled, intro
        if isinstance(setting, bool):
            return setting, intro
        if isinstance(setting, str):
            return setting.strip().lower() not in {"false", "no", "off", ""}, intro
    return False, intro


def _hashtags(tags: list[str]) -> str:
    result: list[str] = []
    for tag in tags:
        cleaned = re.sub(r"[^A-Za-z0-9_]+", "", tag.replace(" ", ""))
        if cleaned:
            result.append("#" + cleaned)
    return " ".join(result)


def prepare_social(
    source: str | Path,
    output: str | Path,
    platform: str = "linkedin",
    languages: str = "ALL",
) -> SocialResult:
    source_path = Path(source).resolve()
    output_path = Path(output).expanduser().resolve()
    platform = platform.lower().strip()

    validation = validate_site(source_path)
    if not validation.success:
        return SocialResult(False, str(output_path), platform, warnings=validation.warnings, errors=validation.errors)

    config = load_site_config(source_path)
    template_path = config.templates_dir / "social" / f"{platform}.txt"
    if not template_path.is_file():
        return SocialResult(False, str(output_path), platform, errors=[f"Social template not found: {template_path}"])

    selected = set(config.supported_languages) if languages.upper() == "ALL" else {part.strip().upper() for part in languages.split(",") if part.strip()}
    unknown = selected - set(config.supported_languages)
    if unknown:
        return SocialResult(False, str(output_path), platform, errors=[f"Unsupported language(s): {', '.join(sorted(unknown))}"])

    navigation = load_navigation(source_path)
    items = discover_content(config, navigation)
    template = load_template(template_path)
    count = 0

    for item in items:
        if item.draft or item.language not in selected or item.base_name == "index":
            continue
        enabled, intro = _social_settings(item, platform)
        if not enabled:
            continue
        canonical = f"{config.base_url}{item.route}" if config.base_url else item.route
        rendered = render_template(
            template,
            {
                "title": item.title,
                "summary": item.summary,
                "social_intro": intro or item.summary,
                "canonical_url": canonical,
                "hashtags": _hashtags(item.tags),
            },
        ).rstrip() + "\n"
        relative = item.source_path.relative_to(config.content_dir).with_suffix("")
        target = output_path / platform / relative.parent / f"{item.base_name}_{item.language}.txt"
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(rendered, encoding="utf-8")
        count += 1

    return SocialResult(True, str(output_path), platform, count, validation.warnings, [])
