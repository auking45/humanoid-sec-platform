#!/usr/bin/env python3
"""
extract_svg.py — Extract standalone SVG with embedded fonts and CSS from Archify HTML artifacts
"""
import sys
import os
import re
import glob

def html_to_svg(html_path: str, svg_path: str) -> bool:
    with open(html_path, "r", encoding="utf-8") as f:
        html = f.read()

    styles = re.findall(r"<style[^>]*>(.*?)</style>", html, re.DOTALL)
    combined_css = "\n".join(styles)

    svg_match = re.search(r"(<svg[^>]*>)(.*?)(</svg>)", html, re.DOTALL)
    if not svg_match:
        print(f"[-] No SVG found in {html_path}", file=sys.stderr)
        return False

    svg_open, svg_body, svg_close = svg_match.groups()
    if "xmlns=" not in svg_open:
        svg_open = svg_open.replace("<svg ", '<svg xmlns="http://www.w3.org/2000/svg" ')

    defs_block = f'<defs><style type="text/css"><![CDATA[\n{combined_css}\n]]></style></defs>'
    final_svg = f"{svg_open}\n{defs_block}\n{svg_body}\n{svg_close}"

    with open(svg_path, "w", encoding="utf-8") as f:
        f.write(final_svg)
    print(f"[+] Exported standalone SVG: {svg_path} ({len(final_svg)} bytes)")
    return True

def main():
    if len(sys.argv) > 1:
        target = sys.argv[1]
        if os.path.isfile(target):
            out = sys.argv[2] if len(sys.argv) > 2 else target.rsplit(".", 1)[0] + ".svg"
            html_to_svg(target, out)
        elif os.path.isdir(target):
            for h in glob.glob(os.path.join(target, "*.html")):
                html_to_svg(h, h.rsplit(".", 1)[0] + ".svg")
    else:
        # Default scan docs/diagrams
        default_dir = os.path.join(os.path.dirname(__file__), "../../../docs/diagrams")
        for h in glob.glob(os.path.join(default_dir, "*.html")):
            html_to_svg(h, h.rsplit(".", 1)[0] + ".svg")

if __name__ == "__main__":
    main()
