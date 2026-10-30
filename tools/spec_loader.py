# -*- coding: utf-8 -*-
"""Đọc schema_spec.py, chuẩn hóa thành cấu trúc dễ dùng và KIỂM TRA tính nhất quán."""
import re, sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import schema_spec as S

def base_type(t):
    t = t.replace(" IDENTITY", "").strip()
    return re.sub(r"\(.*\)", "", t).upper()

def split_flags(s):
    """Tách theo dấu phẩy nằm ngoài ngoặc."""
    out, depth, cur = [], 0, ""
    for ch in s:
        if ch == "(": depth += 1
        if ch == ")": depth -= 1
        if ch == "," and depth == 0:
            out.append(cur); cur = ""
        else:
            cur += ch
    out.append(cur)
    return out

def parse_col(line):
    parts = line.split("|", 3)
    if len(parts) != 4:
        raise ValueError("Cột sai cú pháp (cần 4 phần): " + line)
    name, typ, flags, note = [p.strip() for p in parts]
    col = dict(name=name, type=typ, pk=False, null=False, uq=False, fk=None, default=None, gen=False, note=note)
    for f in [x.strip() for x in split_flags(flags) if x.strip()]:
        if f == "P": col["pk"] = True
        elif f == "N": col["null"] = True
        elif f == "U": col["uq"] = True
        elif f == "G": col["gen"] = True
        elif f.startswith("F="): col["fk"] = f[2:]
        elif f.startswith("D="): col["default"] = f[2:]
        else: raise ValueError("Cờ không hợp lệ '%s' trong: %s" % (f, line))
    if col["pk"]: col["null"] = False
    return col

def load():
    tables = []
    for t in S.TABLES:
        cols = [parse_col(c) for c in t["cols"]]
        for std in S.AUDIT_COLS[t["audit"]]:
            cols.append(parse_col(S.STD[std]))
        tables.append(dict(t, cols=cols, full=t["schema"] + "." + t["name"]))
    return tables

def validate(tables):
    errs = []
    by = {t["full"]: t for t in tables}
    if len(by) != len(tables): errs.append("Trùng tên bảng")
    for t in tables:
        names = [c["name"] for c in t["cols"]]
        if len(set(names)) != len(names): errs.append("%s: trùng tên cột" % t["full"])
        pks = [c for c in t["cols"] if c["pk"]]
        if not pks: errs.append("%s: thiếu khóa chính" % t["full"])
        for c in t["cols"]:
            if "F=" in c["note"] or c["note"].startswith("F"):
                if "F=" in c["note"]: errs.append("%s.%s: cờ F= lọt vào ghi chú (thiếu/thừa dấu |)" % (t["full"], c["name"]))
            if c["fk"]:
                tgt = t["full"] if c["fk"] == "self" else c["fk"]
                if tgt not in by:
                    errs.append("%s.%s: FK tới bảng không tồn tại %s" % (t["full"], c["name"], c["fk"])); continue
                tpk = [x for x in by[tgt]["cols"] if x["pk"]]
                if len(tpk) != 1:
                    errs.append("%s.%s: FK tới bảng có khóa chính ghép %s" % (t["full"], c["name"], tgt)); continue
                if base_type(c["type"]) != base_type(tpk[0]["type"]):
                    errs.append("%s.%s: kiểu %s không khớp khóa chính %s.%s (%s)" % (
                        t["full"], c["name"], c["type"], tgt, tpk[0]["name"], tpk[0]["type"]))
        for (frm, fcols, to, tcols, note) in t["fks"]:
            if to not in by: errs.append("%s: FK ghép tới bảng không tồn tại %s" % (t["full"], to)); continue
            for fc in fcols:
                if fc not in names: errs.append("%s: FK ghép dùng cột không tồn tại %s" % (t["full"], fc))
            tn = [c["name"] for c in by[to]["cols"]]
            for tc in tcols:
                if tc not in tn: errs.append("%s: FK ghép trỏ cột không tồn tại %s.%s" % (t["full"], to, tc))
    return errs

def relationships(tables):
    """Danh sách FK: (from_table, from_cols, to_table, to_cols, cross_module, nullable, one_to_one, label, note)"""
    by = {t["full"]: t for t in tables}
    rels = []
    for t in tables:
        pkcount = sum(1 for c in t["cols"] if c["pk"])
        for c in t["cols"]:
            if not c["fk"]: continue
            tgt = t["full"] if c["fk"] == "self" else c["fk"]
            tpk = [x for x in by[tgt]["cols"] if x["pk"]][0]["name"]
            one = (c["pk"] and pkcount == 1) or c["uq"]
            rels.append(dict(frm=t["full"], fcols=[c["name"]], to=tgt, tcols=[tpk],
                             cross=(t["schema"] != tgt.split(".")[0]), nullable=c["null"], one=one,
                             note="Tự trỏ" if tgt == t["full"] else ""))
    for t in tables:
        for (frm, fcols, to, tcols, note) in t["fks"]:
            rels.append(dict(frm=frm, fcols=fcols, to=to, tcols=tcols,
                             cross=(frm.split(".")[0] != to.split(".")[0]), nullable=False,
                             one=(fcols[0] == "OrderId" and frm == "ord.Reviews"), note=note))
    return rels

def assign_fk_names(rels):
    """Tên FK theo quy ước FK_<Bang>_<BangThamChieu>; trùng thì thêm _<cột đầu>."""
    seen = {}
    for r in rels:
        child = r["frm"].split(".")[1]; parent = r["to"].split(".")[1]
        base = "FK_%s_%s" % (child, parent)
        seen.setdefault(base, []).append(r)
    for base, lst in seen.items():
        for r in lst:
            r["name"] = base if len(lst) == 1 else "%s_%s" % (base, "_".join(r["fcols"]) if len(r["fcols"]) == 1 else "Order")
    return rels

def create_order(tables, rels):
    """Thứ tự tạo bảng trong từng module (FK cùng module); phát hiện vòng phụ thuộc."""
    orders = {}
    for m in S.MODULE_ORDER:
        mt = [t["full"] for t in tables if t["schema"] == m]
        dep = {x: set() for x in mt}
        for r in rels:
            if r["frm"] in dep and r["to"] in dep and r["frm"] != r["to"]:
                dep[r["frm"]].add(r["to"])
        order, done = [], set()
        while len(order) < len(mt):
            ready = [x for x in mt if x not in done and dep[x] <= done]
            if not ready:
                raise ValueError("Vòng phụ thuộc FK trong module %s: %s" % (m, [x for x in mt if x not in done]))
            for x in ready:
                order.append(x); done.add(x)
        orders[m] = order
    return orders

def module_deps(tables, rels):
    deps = {m: set() for m in S.MODULE_ORDER}
    for r in rels:
        a, b = r["frm"].split(".")[0], r["to"].split(".")[0]
        if a != b: deps[a].add(b)
    return deps

def module_toposort(deps):
    order, done = [], set()
    while len(order) < len(S.MODULE_ORDER):
        ready = [m for m in S.MODULE_ORDER if m not in done and deps[m] <= done]
        if not ready: raise ValueError("Vòng phụ thuộc giữa các module")
        for m in ready: order.append(m); done.add(m)
    return order

if __name__ == "__main__":
    tb = load()
    errs = validate(tb)
    print("Số bảng:", len(tb), "| số cột:", sum(len(t["cols"]) for t in tb))
    if errs:
        print("LỖI:"); [print(" -", e) for e in errs]; sys.exit(1)
    rels = relationships(tb)
    print("Số FK:", len(rels), "| liên module:", sum(1 for r in rels if r["cross"]))
    print("Thứ tự module theo FK:", module_toposort(module_deps(tb, rels)))
    print("OK")
