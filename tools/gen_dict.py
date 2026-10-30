# -*- coding: utf-8 -*-
"""Sinh docs/DataDictionary.xlsx từ schema_spec.py (cần openpyxl)."""
import os, re, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import schema_spec as S
import spec_loader as L
from openpyxl import Workbook
from openpyxl.styles import Font, PatternFill, Alignment, Border, Side
from openpyxl.utils import get_column_letter

FONT = "Arial"
HDR_FILL = PatternFill("solid", start_color="1F3864")
HDR_FONT = Font(name=FONT, size=10, bold=True, color="FFFFFF")
BODY = Font(name=FONT, size=10)
BOLD = Font(name=FONT, size=10, bold=True)
TITLE = Font(name=FONT, size=14, bold=True, color="1F3864")
INPUT = Font(name=FONT, size=10, color="0000FF")
BAND = PatternFill("solid", start_color="EEF2F8")
thin = Side(style="thin", color="BFBFBF")
BORDER = Border(left=thin, right=thin, top=thin, bottom=thin)
WRAP = Alignment(wrap_text=True, vertical="top")

def header(ws, row, titles, widths):
    for i, (t, w) in enumerate(zip(titles, widths), start=1):
        c = ws.cell(row=row, column=i, value=t)
        c.font, c.fill, c.border = HDR_FONT, HDR_FILL, BORDER
        c.alignment = Alignment(wrap_text=True, vertical="center", horizontal="center")
        ws.column_dimensions[get_column_letter(i)].width = w
    ws.row_dimensions[row].height = 30

def put(ws, r, c, v, bold=False, wrap=True, font=None):
    cell = ws.cell(row=r, column=c, value=v)
    cell.font = font or (BOLD if bold else BODY)
    cell.border = BORDER
    cell.alignment = WRAP if wrap else Alignment(vertical="top")
    return cell

def main(out):
    tb = L.load()
    errs = L.validate(tb)
    if errs: raise SystemExit("\n".join(errs))
    rels = L.assign_fk_names(L.relationships(tb))
    by = {t["full"]: t for t in tb}
    wb = Workbook()

    # ---------------- Tables ----------------
    wt = wb.active; wt.title = "Tables"
    titles = ["STT","Schema","Bảng","Module","Loại","Flow","Mô tả","Số cột","Cột chuẩn","Số FK ra ngoài"]
    header(wt, 1, titles, [6,9,22,28,10,11,60,9,16,12])
    r = 2
    for t in tb:
        put(wt, r, 1, r-1)
        put(wt, r, 2, t["schema"]); put(wt, r, 3, t["name"], bold=True)
        put(wt, r, 4, S.MODULE_NAMES[t["schema"]]); put(wt, r, 5, t["kind"]); put(wt, r, 6, t["flows"])
        put(wt, r, 7, t["desc"])
        put(wt, r, 8, "=COUNTIFS(Columns!$A:$A,B%d,Columns!$B:$B,C%d)" % (r, r))
        put(wt, r, 9, {"A":"Created/Updated/IsDeleted","CU":"Created/Updated","C":"CreatedAt","":"(không)"}[t["audit"]])
        put(wt, r, 10, "=COUNTIFS(Relationships!$C:$C,B%d&\".\"&C%d,Relationships!$G:$G,\"Liên module\")" % (r, r))
        if r % 2 == 1:
            for c in range(1, 11): wt.cell(row=r, column=c).fill = BAND
        r += 1
    nT = len(tb); lastT = nT + 1
    wt.freeze_panes = "D2"; wt.auto_filter.ref = "A1:J%d" % lastT

    # ---------------- Columns ----------------
    wc = wb.create_sheet("Columns")
    header(wc, 1, ["Schema","Bảng","STT cột","Cột","Kiểu dữ liệu","NULL?","Khóa","Tham chiếu tới (FK)","Mặc định","Ý nghĩa / Ràng buộc"],
           [9,22,8,24,22,11,10,32,30,70])
    r = 2
    for t in tb:
        composite = set()
        for (frm, fcols, to, tcols, note) in t["fks"]:
            composite |= set(fcols)
        for i, c in enumerate(t["cols"], start=1):
            keys = []
            if c["pk"]: keys.append("PK")
            if c["fk"]: keys.append("FK")
            elif c["name"] in composite: keys.append("FK ghép")
            if c["uq"] and not c["pk"]: keys.append("UQ")
            fk = ""
            if c["fk"]:
                tgt = t["full"] if c["fk"] == "self" else c["fk"]
                tpk = [x for x in by[tgt]["cols"] if x["pk"]][0]["name"]
                fk = "%s(%s)" % (tgt, tpk)
            elif c["name"] in composite:
                for (frm, fcols, to, tcols, note) in t["fks"]:
                    if c["name"] in fcols: fk = "%s(%s)" % (to, ", ".join(tcols))
            typ = c["type"] + (" (cột tính)" if c["gen"] else "")
            vals = [t["schema"], t["name"], i, c["name"], typ, "NULL" if c["null"] else "NOT NULL",
                    ", ".join(keys), fk, c["default"] or "", c["note"]]
            for j, v in enumerate(vals, start=1):
                put(wc, r, j, v, bold=(j == 4))
            r += 1
    nC = r - 2; lastC = r - 1
    wc.freeze_panes = "E2"; wc.auto_filter.ref = "A1:J%d" % lastC

    # ---------------- Relationships ----------------
    wr = wb.create_sheet("Relationships")
    header(wr, 1, ["STT","Tên FK","Bảng con","Cột con","Bảng cha","Cột cha","Phạm vi","Tạo ở","Bản số","NULL?","ON DELETE","Ghi chú"],
           [6,38,24,30,24,30,13,20,12,9,12,46])
    r = 2
    for i, rel in enumerate(rels, start=1):
        card = "1-1" if rel["one"] else ("0..1 - N" if rel["nullable"] else "1 - N")
        vals = [i, rel["name"], rel["frm"], ", ".join(rel["fcols"]), rel["to"], ", ".join(rel["tcols"]),
                "Liên module" if rel["cross"] else "Cùng module",
                "02_foreign_keys" if rel["cross"] else "01_tables",
                card, "NULL" if rel["nullable"] else "NOT NULL", "NO ACTION", rel["note"]]
        for j, v in enumerate(vals, start=1): put(wr, r, j, v, bold=(j == 2))
        r += 1
    nR = len(rels); lastR = nR + 1
    wr.freeze_panes = "C2"; wr.auto_filter.ref = "A1:L%d" % lastR

    # ---------------- Constraints ----------------
    wk = wb.create_sheet("Constraints")
    header(wk, 1, ["STT","Schema","Bảng","Loại","Nội dung (ràng buộc cấp bảng)"], [6,9,22,12,110])
    r = 2
    for t in tb:
        for (typ, txt) in t["cons"]:
            put(wk, r, 1, r-1); put(wk, r, 2, t["schema"]); put(wk, r, 3, t["name"], bold=True)
            put(wk, r, 4, typ); put(wk, r, 5, txt); r += 1
    nK = r - 2; lastK = r - 1
    wk.freeze_panes = "D2"; wk.auto_filter.ref = "A1:E%d" % lastK

    # ---------------- Enums ----------------
    we = wb.create_sheet("Enums")
    header(we, 1, ["STT","Schema","Bảng","Cột","Giá trị cho phép (CHECK IN)","Số giá trị"], [6,9,22,24,80,11])
    r = 2
    for t in tb:
        for c in t["cols"]:
            m = re.search(r"IN \(([^)]*)\)", c["note"])
            if m and "CK" in c["note"]:
                vals = [x.strip().strip("'") for x in m.group(1).split(",")]
                put(we, r, 1, r-1); put(we, r, 2, t["schema"]); put(we, r, 3, t["name"], bold=True); put(we, r, 4, c["name"])
                put(we, r, 5, ", ".join(vals)); put(we, r, 6, len(vals)); r += 1
    nE = r - 2; lastE = r - 1
    we.freeze_panes = "E2"; we.auto_filter.ref = "A1:F%d" % lastE

    # ---------------- README (đầu file) ----------------
    ws = wb.create_sheet("Hướng dẫn", 0)
    ws.column_dimensions["A"].width = 34; ws.column_dimensions["B"].width = 16; ws.column_dimensions["C"].width = 90
    ws["A1"] = "Data Dictionary: FilmLabDB"; ws["A1"].font = TITLE
    ws["A2"] = "Nền tảng kết nối cộng đồng nhiếp ảnh phim và các Film Lab (MiniLab) tích hợp AI | SQL Server 2022 + T-SQL"; ws["A2"].font = BODY
    ws["A3"] = "File sinh tự động từ tools/schema_spec.py (python tools/gen_dict.py). Không sửa tay trong file này; sửa spec rồi sinh lại."; ws["A3"].font = Font(name=FONT, size=10, italic=True)
    row = 5
    ws.cell(row=row, column=1, value="Các sheet").font = BOLD; row += 1
    for name, desc in [("Tables","41 bảng: module, loại, mô tả, số cột, số FK liên module"),
                       ("Columns","Toàn bộ cột: kiểu dữ liệu, NULL, khóa, FK, mặc định, ý nghĩa/ràng buộc"),
                       ("Relationships","Mọi khóa ngoại (kể cả FK ghép): bảng con/cha, phạm vi, tầng tạo (01_tables hay 02_foreign_keys)"),
                       ("Constraints","Ràng buộc cấp bảng: CHECK nhiều cột, UNIQUE/filtered index, trigger, Temporal, Full-Text"),
                       ("Enums","Các cột dùng CHECK IN (...) và tập giá trị cho phép")]:
        ws.cell(row=row, column=1, value=name).font = BOLD
        ws.cell(row=row, column=3, value=desc).font = BODY; row += 1
    row += 1
    ws.cell(row=row, column=1, value="Thống kê (tính bằng công thức)").font = BOLD; row += 1
    stats = [
      ("Tổng số bảng", "=COUNTA(Tables!C2:C%d)" % lastT, "Đủ 41 bảng của thiết kế"),
      ("Tổng số cột", "=COUNTA(Columns!D2:D%d)" % lastC, "Gồm cả cột chuẩn CreatedAt/UpdatedAt/IsDeleted"),
      ("Tổng số khóa ngoại", "=COUNTA(Relationships!B2:B%d)" % lastR, "Gồm 3 FK ghép nhiều cột và 1 FK tự trỏ"),
      ("FK liên module", "=COUNTIF(Relationships!G2:G%d,\"Liên module\")" % lastR, "Tạo ở database/02_foreign_keys"),
      ("FK cùng module", "=COUNTIF(Relationships!G2:G%d,\"Cùng module\")" % lastR, "Tạo ngay ở database/01_tables"),
      ("Bảng Entity", "=COUNTIF(Tables!E2:E%d,\"Entity\")" % lastT, "Bảng nghiệp vụ"),
      ("Bảng Lookup", "=COUNTIF(Tables!E2:E%d,\"Lookup\")" % lastT, "Danh mục cố định, có seed reference"),
      ("Bảng Junction", "=COUNTIF(Tables!E2:E%d,\"Junction\")" % lastT, "Bảng liên kết N-N"),
      ("Bảng Log", "=COUNTIF(Tables!E2:E%d,\"Log\")" % lastT, "Nhật ký, chỉ thêm"),
      ("Cột dùng CHECK IN (enum)", "=COUNTA(Enums!D2:D%d)" % lastE, "Xem sheet Enums"),
      ("Ràng buộc cấp bảng", "=COUNTA(Constraints!D2:D%d)" % lastK, "Xem sheet Constraints"),
    ]
    for label, f, note in stats:
        ws.cell(row=row, column=1, value=label).font = BODY
        c = ws.cell(row=row, column=2, value=f); c.font = BOLD; c.alignment = Alignment(horizontal="right")
        ws.cell(row=row, column=3, value=note).font = BODY; row += 1
    row += 1
    ws.cell(row=row, column=1, value="Số bảng theo module").font = BOLD; row += 1
    first_mod = row
    for m in S.MODULE_ORDER:
        ws.cell(row=row, column=1, value="%s (%s)" % (m, S.MODULE_NAMES[m])).font = BODY
        c = ws.cell(row=row, column=2, value="=COUNTIF(Tables!B2:B%d,\"%s\")" % (lastT, m)); c.font = BOLD; c.alignment = Alignment(horizontal="right")
        row += 1
    ws.cell(row=row, column=1, value="Cộng").font = BOLD
    c = ws.cell(row=row, column=2, value="=SUM(B%d:B%d)" % (first_mod, row - 1)); c.font = BOLD; c.alignment = Alignment(horizontal="right")
    ws.cell(row=row, column=3, value="Phải bằng Tổng số bảng ở trên").font = BODY
    row += 2
    ws.cell(row=row, column=1, value="Quy ước đọc").font = BOLD; row += 1
    for k, v in [("Cột chuẩn", "Bảng chính có CreatedAt, UpdatedAt, IsDeleted (xóa mềm). Bảng log/lookup/junction có thể thiếu một số cột (xem cột 'Cột chuẩn' ở sheet Tables)."),
                 ("Kiểu IDENTITY", "Ghi 'INT IDENTITY' = tự tăng. Bảng lookup dùng ID cố định, không IDENTITY."),
                 ("FK ghép", "Reviews, Complaints, MarketTransactions dùng FK nhiều cột để DB tự bảo đảm dữ liệu khớp đơn/tin đăng."),
                 ("Không FK có chủ ý", "ai.RecommendationLogs.ItemId và audit.AuditLogs.ChangedBy không có FK (xem docs/Normalization.md)."),
                 ("ON DELETE", "Mặc định NO ACTION cho mọi FK; xóa mềm bằng IsDeleted để tránh lỗi multiple cascade paths.")]:
        ws.cell(row=row, column=1, value=k).font = BOLD
        c = ws.cell(row=row, column=3, value=v); c.font = BODY; c.alignment = WRAP; row += 1
    ws.sheet_view.showGridLines = False
    os.makedirs(os.path.dirname(out), exist_ok=True)
    wb.save(out)
    print("Đã ghi", out, "| bảng:", nT, "| cột:", nC, "| FK:", nR, "| ràng buộc:", nK, "| enum:", nE)

if __name__ == "__main__":
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    main(os.path.join(root, "docs", "DataDictionary.xlsx"))
