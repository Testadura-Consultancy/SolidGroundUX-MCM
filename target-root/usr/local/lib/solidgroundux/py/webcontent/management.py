"""Manage canonical Markdown front matter and move pages without Git side effects."""
from __future__ import annotations
from pathlib import Path
import re
from .content import discover_content, load_navigation, load_site_config, parse_front_matter

SAFE_KEY = re.compile(r"^[A-Za-z][A-Za-z0-9_-]*$")
SAFE_SEGMENT = re.compile(r"^[a-z0-9][a-z0-9-]*$")

def _setup(source):
    """Handle setup for the web content workflow."""
    root = Path(source).expanduser().resolve()
    config = load_site_config(root)
    items = discover_content(config, load_navigation(root))
    return config, items

def _resolve(config, path):
    """Handle resolve for the web content workflow."""
    content = config.content_dir.resolve()
    candidate = (content / path).resolve()
    if not candidate.is_relative_to(content) or candidate.suffix.lower() != '.md' or not candidate.is_file():
        raise ValueError('Not an existing Markdown page within content directory')
    return candidate

def list_pages(source):
    """List discovered canonical Markdown pages for the management interface.
    
    Args:
        source: Input used by this operation.
    
    Returns:
        Operation result or None, as defined by the implementation."""
    config, items = _setup(source)
    pages = []
    for item in sorted(items, key=lambda x: (x.route, x.language)):
        pages.append({'file': item.source_path.relative_to(config.content_dir).as_posix(), 'title': item.title,
                      'language': item.language, 'route': item.route, 'metadata': item.metadata})
    return {'success': True, 'pages': pages}

def edit_metadata(source, path, key, value):
    """Update a single front-matter field while retaining article body text.
    
    Args:
        source: Input used by this operation.
        path: Input used by this operation.
        key: Input used by this operation.
        value: Input used by this operation.
    
    Returns:
        Operation result or None, as defined by the implementation."""
    config, _ = _setup(source)
    file = _resolve(config, path)
    if not SAFE_KEY.fullmatch(key) or key in {'parent', 'slug', 'language'}:
        raise ValueError('Invalid or location-dependent metadata field')
    raw = file.read_text(encoding='utf-8')
    meta, _ = parse_front_matter(raw)
    if not raw.startswith('---\n') or not isinstance(meta, dict):
        raise ValueError('Valid front matter required')
    # Boolean editor input can include padding from the MCM ask control.
    # Store only canonical lowercase true/false in front matter.
    if key in {'featured', 'draft', 'hide_title'}:
        value = value.strip().lower()
        if value not in {'true', 'false'}:
            raise ValueError('Boolean field requires true or false')
    if '\n' in value or '\r' in value:
        raise ValueError('Multi-line metadata values cannot be edited here')
    if key in {'title', 'summary', 'date', 'featured_image', 'hero_image'}:
        encoded = '"' + value.replace('\\','\\\\').replace('"','\\"') + '"'
    else:
        encoded = value
    lines = raw.splitlines(keepends=True)
    close = next((i for i in range(1,len(lines)) if lines[i].strip() == '---'), None)
    if close is None: raise ValueError('Missing front matter terminator')
    pattern = re.compile(r'^' + re.escape(key) + r'\s*:')
    found = [i for i in range(1,close) if pattern.match(lines[i])]
    if len(found)>1: raise ValueError('Duplicate metadata key')
    if found: lines[found[0]]=f'{key}: {encoded}\n'
    else: lines.insert(close,f'{key}: {encoded}\n')
    file.write_text(''.join(lines), encoding='utf-8')
    return {'success': True,'file':path,'key':key,'value':value}

def move_page(source, path, parent, slug):
    """Move or rename one language-specific page without overwriting a target.
    
    Args:
        source: Input used by this operation.
        path: Input used by this operation.
        parent: Input used by this operation.
        slug: Input used by this operation.
    
    Returns:
        Operation result or None, as defined by the implementation."""
    config, items = _setup(source)
    file = _resolve(config,path)
    if file.stem.startswith('index_'):
        raise ValueError('Section index pages must not be moved using Move Page; move the section as a whole in Git')
    if not SAFE_SEGMENT.fullmatch(slug):
        raise ValueError('Slug must be lowercase letters, digits and hyphens')
    if parent.startswith('/') or '..' in Path(parent).parts:
        raise ValueError('Destination parent must be a relative section path')
    target_dir=(config.content_dir / parent).resolve()
    if not target_dir.is_relative_to(config.content_dir.resolve()) or not (target_dir / 'index_NL.md').exists() and not (target_dir / 'index_EN.md').exists():
        raise ValueError('Destination must be an existing section with an index page')
    suffix = file.stem.rsplit('_',1)[-1]
    target=target_dir/f'{slug}_{suffix}.md'
    if target.exists() and target != file:
        raise ValueError('Destination already exists; refusing to overwrite')
    original_route=next((x.route for x in items if x.source_path.resolve()==file), '')
    if file != target: file.rename(target)
    return {'success': True,'from':path,'to':target.relative_to(config.content_dir).as_posix(),
            'old_route':original_route,'warnings':['Check and update links pointing to the former URL; no links were rewritten automatically.']}
