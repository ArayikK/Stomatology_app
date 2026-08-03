import xml.etree.ElementTree as ET

NS = {'svg': 'http://www.w3.org/2000/svg'}
SRC = r"C:\Users\arayi\Desktop\Dental.svg"
OUT = r"C:\Users\arayi\Desktop\Stom\lib\chart\tooth_paths.dart"

def polygon_to_d(points_attr):
    raw = points_attr.replace(',', ' ').split()
    nums = [float(n) for n in raw]
    coords = list(zip(nums[0::2], nums[1::2]))
    d = "M" + " L".join(f"{x},{y}" for x, y in coords) + " Z"
    return d

def collect_shapes(elem):
    """Recursively collect (fill, d) pairs from path/polygon descendants, in document order, deduping exact consecutive duplicates coming from mirrored duplicate sub-groups."""
    shapes = []
    tag = elem.tag.split('}')[-1]
    if tag == 'path':
        d = elem.get('d')
        fill = elem.get('fill', '#000000')
        if d:
            shapes.append((fill, d))
    elif tag == 'polygon':
        pts = elem.get('points')
        fill = elem.get('fill', '#000000')
        if pts:
            shapes.append((fill, polygon_to_d(pts)))
    for child in elem:
        shapes.extend(collect_shapes(child))
    return shapes

def dedupe(shapes):
    out = []
    seen_run = []
    # de-dupe exact repeated whole-sequence blocks (Illustrator mirrored duplicate <g>)
    n = len(shapes)
    if n % 2 == 0 and n > 0:
        half = n // 2
        if shapes[:half] == shapes[half:]:
            return shapes[:half]
    return shapes

def esc(s):
    return s.replace(chr(92), chr(92) * 2).replace("'", "\\'")

def main():
    tree = ET.parse(SRC)
    root = tree.getroot()
    view_box = root.get('viewBox').split()
    vb_w, vb_h = view_box[2], view_box[3]

    top_groups = root.findall('svg:g', NS)

    base_shapes = []
    teeth = {}

    for g in top_groups:
        gid = g.get('id')
        shapes = collect_shapes(g)
        shapes = dedupe(shapes)
        if gid == 'Mouth':
            base_shapes = shapes
        else:
            num = int(gid.lstrip('_'))
            teeth[num] = shapes

    lines = []
    lines.append("// GENERATED FILE - do not edit by hand.")
    lines.append("// Produced by tools/gen_tooth_paths.py from Dental.svg.")
    lines.append("//")
    lines.append("// NOTE: the source SVG does not contain separate '<n>_hg' highlight-overlay")
    lines.append("// groups as originally assumed -- each tooth group only has its natural-color")
    lines.append("// artwork (crown outline + shading sub-paths). HIGHLIGHTS below reuses each")
    lines.append("// tooth's own geometry, recolored to HIGHLIGHT_COLOR, so the painter can fill")
    lines.append("// the whole tooth silhouette blue for teeth with treatment history instead of")
    lines.append("// drawing separate highlight artwork.")
    lines.append("")
    lines.append(f"const double kViewBoxWidth = {vb_w};")
    lines.append(f"const double kViewBoxHeight = {vb_h};")
    lines.append("")
    lines.append("const String kHighlightColor = '#2F6FED';")
    lines.append("")

    def emit_pair_list(name, shapes, indent="  "):
        out = [f"const List<MapEntry<String, String>> {name} = ["]
        for fill, d in shapes:
            out.append(f"{indent}MapEntry('{esc(fill)}', '{esc(d)}'),")
        out.append("];")
        return "\n".join(out)

    lines.append(emit_pair_list("kBase", base_shapes))
    lines.append("")

    lines.append("const Map<int, List<MapEntry<String, String>>> kTeeth = {")
    for num in sorted(teeth.keys()):
        shapes = teeth[num]
        lines.append(f"  {num}: [")
        for fill, d in shapes:
            lines.append(f"    MapEntry('{esc(fill)}', '{esc(d)}'),")
        lines.append("  ],")
    lines.append("};")
    lines.append("")

    lines.append("const Map<int, List<MapEntry<String, String>>> kHighlights = {")
    for num in sorted(teeth.keys()):
        shapes = teeth[num]
        lines.append(f"  {num}: [")
        for _fill, d in shapes:
            lines.append(f"    MapEntry(kHighlightColor, '{esc(d)}'),")
        lines.append("  ],")
    lines.append("};")
    lines.append("")

    with open(OUT, 'w', encoding='utf-8') as f:
        f.write("\n".join(lines) + "\n")

    print("wrote", OUT)
    print("base shapes:", len(base_shapes))
    print("teeth:", len(teeth), "total shapes:", sum(len(v) for v in teeth.values()))

if __name__ == '__main__':
    main()
