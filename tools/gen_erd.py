# -*- coding: utf-8 -*-
"""Sinh diagrams/ERD.md (Mermaid erDiagram). GitHub hiển thị trực tiếp; có thể dán vào draw.io (Arrange > Insert > Advanced > Mermaid) hoặc mermaid.live."""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import schema_spec as S
import spec_loader as L

def ent(full): return full.replace(".", "_")

def attr_lines(t, rels_from):
    fkcols = set()
    for r in rels_from:
        for c in r["fcols"]: fkcols.add(c)
    lines = []
    for c in t["cols"]:
        keys = []
        if c["pk"]: keys.append("PK")
        if c["fk"] or c["name"] in fkcols: keys.append("FK")
        if c["uq"] and not c["pk"]: keys.append("UK")
        k = (" " + ",".join(keys)) if keys else ""
        base = L.base_type(c["type"]).lower()
        lines.append("        %s %s%s" % (base, c["name"], k))
    return lines

def card(r):
    left = "|o" if r["nullable"] else "||"
    right = "o|" if r["one"] else "o{"
    return "%s--%s" % (left, right)

def rel_line(r):
    lab = ",".join(r["fcols"])
    return '    %s %s %s : "%s"' % (ent(r["to"]), card(r), ent(r["frm"]), lab)

def main(out):
    tb = L.load()
    errs = L.validate(tb)
    if errs: raise SystemExit("\n".join(errs))
    rels = L.relationships(tb)
    by = {t["full"]: t for t in tb}
    md = []
    md.append("# ERD: FilmLabDB (41 bảng)\n")
    md.append("> **File này được sinh tự động** từ `tools/schema_spec.py` bằng `python tools/gen_erd.py`. Không sửa tay; muốn đổi thiết kế thì sửa `schema_spec.py` rồi chạy lại.\n")
    md.append("**Cách xem:** GitHub hiển thị sơ đồ Mermaid ngay trong trang này. Để chỉnh sửa/xuất ảnh: dán khối code vào <https://mermaid.live> hoặc draw.io (*Arrange > Insert > Advanced > Mermaid*).\n")
    md.append("**Quy ước ký hiệu:**\n")
    md.append("| Ký hiệu | Nghĩa |\n|---|---|\n| `PK` / `FK` / `UK` | Khóa chính / khóa ngoại / duy nhất |\n| `\\|\\|--o{` | Cha bắt buộc (1) - con có nhiều (0..N) |\n| `\\|o--o{` | Cha tùy chọn (0..1) - con có nhiều (0..N), cột FK cho phép NULL |\n| `\\|\\|--o\\|` | Quan hệ 1-1 (FK đồng thời là khóa chính hoặc unique) |\n| Tên thực thể `iam_Users` | Schema `iam`, bảng `Users` |\n")
    md.append("Một số FK ghép (nhiều cột) được vẽ bằng một đường nối, nhãn là danh sách cột (ví dụ `OrderId,CustomerId,LabId`).\n")

    # Overview
    md.append("## 1. Tổng quan quan hệ giữa các bảng (không hiển thị cột)\n")
    md.append("```mermaid\nerDiagram")
    for m in S.MODULE_ORDER:
        for r in rels:
            if r["frm"].split(".")[0] == m:
                md.append(rel_line(r))
    md.append("```\n")

    # Module map
    md.append("## 2. Các module và bảng\n")
    md.append("| Schema | Module | Bảng |\n|---|---|---|")
    for m in S.MODULE_ORDER:
        names = ", ".join(t["name"] for t in tb if t["schema"] == m)
        md.append("| `%s` | %s | %s |" % (m, S.MODULE_NAMES[m], names))
    md.append("")

    # Per-module
    for i, m in enumerate(S.MODULE_ORDER, start=3):
        mt = [t for t in tb if t["schema"] == m]
        md.append("## %d. Module `%s`: %s\n" % (i, m, S.MODULE_NAMES[m]))
        md.append("```mermaid\nerDiagram")
        mod_rels = [r for r in rels if r["frm"].split(".")[0] == m]
        # entities of module (full attributes)
        for t in mt:
            rf = [r for r in rels if r["frm"] == t["full"]]
            md.append("    %s {" % ent(t["full"]))
            md.extend(attr_lines(t, rf))
            md.append("    }")
        # external stubs (only PK)
        ext = []
        for r in mod_rels:
            if r["to"].split(".")[0] != m and r["to"] not in ext: ext.append(r["to"])
        for e in ext:
            t = by[e]
            pks = [c for c in t["cols"] if c["pk"]]
            md.append("    %s {" % ent(e))
            for c in pks:
                md.append("        %s %s PK" % (L.base_type(c["type"]).lower(), c["name"]))
            md.append("    }")
        for r in mod_rels:
            md.append(rel_line(r))
        md.append("```\n")
        if ext:
            md.append("Bảng ngoài module (chỉ hiện khóa chính): " + ", ".join("`%s`" % e for e in ext) + ".\n")
        # Notes
        notes = [r for r in mod_rels if r["note"] and r["note"] != "Tự trỏ"]
        for r in notes:
            md.append("- **FK ghép** `%s(%s)` -> `%s(%s)`: %s." % (r["frm"], ", ".join(r["fcols"]), r["to"], ", ".join(r["tcols"]), r["note"]))
        if notes: md.append("")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    open(out, "w", encoding="utf-8", newline="\n").write("\n".join(md))
    print("Đã ghi", out, "| thực thể:", len(tb), "| quan hệ:", len(rels))

if __name__ == "__main__":
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    main(os.path.join(root, "diagrams", "ERD.md"))
