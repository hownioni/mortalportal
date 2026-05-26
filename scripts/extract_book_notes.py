#!/usr/bin/env python3
"""
Extract opinionated book notes for the project using Claude Haiku.

Usage:
    python scripts/extract_book_notes.py --pdf <path> --title "<title>"
    python scripts/extract_book_notes.py --pdf books/refactoring.pdf --title "Refactoring — Martin Fowler"

Context is read from CLAUDE.md automatically.
Override with --context "your context string" if needed.

Requires: pip install anthropic
"""

import argparse
import base64
import re
import sys
from pathlib import Path

try:
    import anthropic
except ImportError:
    print("Error: anthropic package not found.")
    print("Run: pip install anthropic")
    sys.exit(1)


SYSTEM_PROMPT = """You are a senior software engineer helping a game developer build a personal reference library for their Godot 4 project.

Your job: read the provided book and extract ONLY the principles, patterns, and practices most relevant to the developer's specific project context. Be ruthlessly opinionated — filter out everything that does not apply to this specific project.

Output format — strict markdown, ready to save as a docs/book-notes/ file:

# [Book Title] — Notes
> [one-sentence description of the book's core argument]

## Directly applicable principles
[For each principle: a short heading, 2–4 sentence explanation, and a concrete Godot/GDScript example. Skip anything that does not apply.]

## Patterns to use
[Named patterns from the book that apply, with a one-paragraph note on when and how to apply each in this project's context.]

## Red flags and smells to watch for
[Warning signs the book identifies that are relevant to this project's stated challenges.]

## What this book says not to do
[Anti-patterns explicitly warned against, filtered for relevance to this project.]

## One thing to do first
[The single most impactful change this book recommends, applied to this specific project.]

Rules:
- Be opinionated. If the book covers 200 topics and only 12 apply, list 12.
- Write in second person, directly to the developer. Never say "as the book says."
- Every example must be concrete and Godot/GDScript-specific where possible.
- No padding, no filler. Dense and useful.
- Respond ONLY with the markdown file content. No preamble or explanation."""


def slugify(title: str) -> str:
    slug = title.lower()
    slug = re.sub(r"[^a-z0-9\s-]", "", slug)
    slug = re.sub(r"[\s-]+", "-", slug).strip("-")
    return slug[:60]


def load_context(context_arg: str | None) -> str:
    if context_arg:
        return context_arg

    claude_md = Path("CLAUDE.md")
    if claude_md.exists():
        return claude_md.read_text(encoding="utf-8").strip()

    print("Warning: no CLAUDE.md found. Using minimal context.")
    return "Godot 4.x game project using GDScript and composition-based architecture."


def main():
    parser = argparse.ArgumentParser(
        description="Extract opinionated book notes using Claude Haiku.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    parser.add_argument("--pdf", required=True, help="Path to the book PDF")
    parser.add_argument(
        "--title",
        required=True,
        help="Book title and author, e.g. 'Refactoring — Martin Fowler'",
    )
    parser.add_argument(
        "--context",
        help="Project context string (optional; defaults to CLAUDE.md)",
    )
    parser.add_argument(
        "--output",
        help="Output file path (optional; defaults to docs/book-notes/<slug>.md)",
    )
    args = parser.parse_args()

    # Validate PDF
    pdf_path = Path(args.pdf)
    if not pdf_path.exists():
        print(f"Error: PDF not found: {pdf_path}")
        sys.exit(1)
    if pdf_path.suffix.lower() != ".pdf":
        print("Error: file must be a .pdf")
        sys.exit(1)

    # Load context
    context = load_context(args.context)

    # Determine output path
    if args.output:
        out_file = Path(args.output)
    else:
        out_dir = Path("docs/book-notes")
        out_dir.mkdir(parents=True, exist_ok=True)
        out_file = out_dir / f"{slugify(args.title)}.md"

    # Read and encode PDF
    print(f"Reading {pdf_path.name} ({pdf_path.stat().st_size / 1024 / 1024:.1f} MB)…")
    pdf_data = base64.standard_b64encode(pdf_path.read_bytes()).decode("utf-8")

    print("Sending to Haiku — may take 30–90 seconds for a full book…")

    client = anthropic.Anthropic()

    message = client.messages.create(
        model="claude-haiku-4-5-20251001",
        max_tokens=4096,
        system=SYSTEM_PROMPT,
        messages=[
            {
                "role": "user",
                "content": [
                    {
                        "type": "document",
                        "source": {
                            "type": "base64",
                            "media_type": "application/pdf",
                            "data": pdf_data,
                        },
                    },
                    {
                        "type": "text",
                        "text": (
                            f"Book: {args.title}\n\n"
                            f"My project context:\n{context}\n\n"
                            "Extract the most relevant principles for my specific situation."
                        ),
                    },
                ],
            }
        ],
    )

    output = "\n".join(
        block.text for block in message.content if hasattr(block, "text")
    ).strip()

    out_file.parent.mkdir(parents=True, exist_ok=True)
    out_file.write_text(output, encoding="utf-8")

    print(f"\n✓  Saved to {out_file}")
    print(f"   Input tokens:  {message.usage.input_tokens:,}")
    print(f"   Output tokens: {message.usage.output_tokens:,}")
    print(f"\nReference in Claude Code with: @{out_file}")


if __name__ == "__main__":
    main()
