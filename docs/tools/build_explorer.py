#!/usr/bin/env python3
"""build_explorer.py — fill the explorer template with the measured area data.

    python3 docs/tools/build_explorer.py            -> docs/explorer.html (images by path)
    python3 docs/tools/build_explorer.py --inline OUT.html
                                                    -> one self-contained file
"""
import base64, io, json, sys
tpl = open("docs/tools/explorer_template.html").read()
blocks = json.load(open("docs/area.json"))["blocks"]
blocks.pop("Glue", None)
html = tpl.replace("{{AREA_JSON}}", json.dumps(blocks))
if len(sys.argv) > 2 and sys.argv[1] == "--inline":
    from PIL import Image
    def uri(path, width):
        im = Image.open(path).convert("RGB")
        im = im.resize((width, round(im.height * width / im.width)), Image.LANCZOS)
        buf = io.BytesIO(); im.save(buf, "JPEG", quality=84, optimize=True)
        return "data:image/jpeg;base64," + base64.b64encode(buf.getvalue()).decode()
    html = html.replace("{{IMG_BLOCKS}}", uri("docs/images/layout_blocks.png", 1600))
    html = html.replace("{{IMG_ZOOM}}", uri("docs/images/layout_zoom.png", 1300))
    out = sys.argv[2]
else:
    html = html.replace("{{IMG_BLOCKS}}", "images/layout_blocks.png").replace("{{IMG_ZOOM}}", "images/layout_zoom.png")
    out = "docs/explorer.html"
open(out, "w").write(html)
print(f"wrote {out} ({len(html)/1024:.0f} KB)")
