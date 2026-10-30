# -*- coding: utf-8 -*-
"""Sinh code Đợt 5 từ schema_spec.py: 01_tables, 02_foreign_keys, 03_indexes.
Chạy: python tools/gen_sql.py   (từ thư mục gốc repo). Giữ nguyên phần header của từng file."""
import re, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import spec_loader as L
import schema_spec as S

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "database")
SETOPT = "SET QUOTED_IDENTIFIER ON;  -- bắt buộc cho filtered index, spatial index, computed column\nSET ANSI_NULLS ON;\nGO\n"

def file_key(t):
    return "ord_feedback" if t["module"] == "M6" else t["schema"]

# ---------- Ràng buộc CK lấy từ ghi chú cột ----------
CK_OVERRIDE = {
    ("iam.Users", "Email"): "Email LIKE '%_@_%._%'",
    ("iam.Users", "Phone"): "Phone NOT LIKE '%[^0-9+]%' AND LEN(Phone) BETWEEN 9 AND 15",
    ("arc.PhotoMetadata", "ShootingDate"): "ShootingDate <= CAST(SYSUTCDATETIME() AS DATE)",
    ("mkt.Messages", "Body"): "LEN(Body) > 0",
    ("ai.KnowledgeDocs", "Content"): "LEN(Content) > 0",
}
def col_check(full, c):
    if (full, c["name"]) in CK_OVERRIDE: return CK_OVERRIDE[(full, c["name"])]
    n = c["note"].split(";")[0].strip()
    if not n.startswith("CK"): return None
    n = n[2:].strip()
    nm = c["name"]
    m = re.match(r"IN \((.*?)\)", n)
    if m: return "%s IN (%s)" % (nm, m.group(1))
    m = re.match(r"BETWEEN (\d+) AND (\d+)", n)
    if m: return "%s BETWEEN %s AND %s" % (nm, m.group(1), m.group(2))
    m = re.match(r"(\d+)\.\.(\d+)", n)
    if m: return "%s BETWEEN %s AND %s" % (nm, m.group(1), m.group(2))
    m = re.match(r"(>=|>) (\d+)", n)
    if m: return "%s %s %s" % (nm, m.group(1), m.group(2))
    if n.startswith("ISJSON = 1"): return "ISJSON(%s) = 1" % nm
    raise ValueError("Không hiểu CK: %s.%s: %s" % (full, nm, c["note"]))

def ident_cols(expr, names):
    found = []
    for w in re.findall(r"[A-Za-z_][A-Za-z0-9_]*", re.sub(r"'[^']*'", "", expr)):
        if w in names and w not in found: found.append(w)
    return found

GENERATED = {("ord.OrderItems", "LineTotal"): "Quantity * UnitPriceSnapshot",
             ("mkt.MarketTransactions", "TotalAmount"): "Quantity * UnitPrice"}

def coltype(c):
    t = c["type"]
    if t.endswith(" IDENTITY"): t = t.replace(" IDENTITY", " IDENTITY(1,1)")
    return t

def fix_where(t, w):
    """Filtered index không cho NOT IN: đổi thành IN với các giá trị còn lại (lấy từ CK IN của cột)."""
    m = re.search(r"(\w+) NOT IN \((.*?)\)", w)
    if not m: return w
    col, excl = m.group(1), {x.strip() for x in m.group(2).split(",")}
    c = next(c for c in t["cols"] if c["name"] == col)
    allv = [x.strip() for x in re.match(r"CK IN \((.*?)\)", c["note"].split(";")[0]).group(1).split(",")]
    keep = [x for x in allv if x not in excl]
    return w.replace(m.group(0), "%s IN (%s)" % (col, ",".join(keep)))

def build():
    tables = L.load()
    errs = L.validate(tables)
    if errs: raise SystemExit("\n".join(errs))
    rels = L.assign_fk_names(L.relationships(tables))
    by = {t["full"]: t for t in tables}
    names_by_schema = {}
    def claim(schema, name):
        s = names_by_schema.setdefault(schema, set())
        if name in s: raise ValueError("Trùng tên ràng buộc/index: %s.%s" % (schema, name))
        s.add(name)
    out_tables, out_fk, out_idx = {}, {}, {}
    rel_by_from = {}
    for r in rels: rel_by_from.setdefault(r["frm"], []).append(r)

    # tên FK gắn cho cột đơn
    def fk_name_for(frm, cols, to):
        for r in rel_by_from.get(frm, []):
            if r["fcols"] == cols and r["to"] == to: return r["name"]
        raise KeyError((frm, cols, to))

    orders = L.create_order(tables, rels)
    for key in S.MODULE_ORDER + ["ord_feedback"]:
        sch = "ord" if key == "ord_feedback" else key
        seq = [by[f] for f in orders[sch] if file_key(by[f]) == key]
        blocks, fks_cross, idx_lines = [], [], []
        for t in seq:
            tn, full, sc = t["name"], t["full"], t["schema"]
            names = [c["name"] for c in t["cols"]]
            temporal = any(k == "TEMPORAL" for k, _ in t["cons"])
            lines, tail = [], []
            pkcols = [c["name"] for c in t["cols"] if c["pk"]]
            for c in t["cols"]:
                if (full, c["name"]) in GENERATED:
                    lines.append("    %-20s AS (CAST(%s AS %s)) PERSISTED NOT NULL" % (c["name"], GENERATED[(full, c["name"])], c["type"]))
                    continue
                s = "    %-20s %s %s" % (c["name"], coltype(c), "NULL" if c["null"] else "NOT NULL")
                if c["default"] is not None:
                    claim(sc, "DF_%s_%s" % (tn, c["name"]))
                    s += "\n        %-18s CONSTRAINT DF_%s_%s DEFAULT %s" % ("", tn, c["name"], c["default"])
                if c["pk"] and len(pkcols) == 1:
                    claim(sc, "PK_" + tn); s += "\n        %-18s CONSTRAINT PK_%s PRIMARY KEY" % ("", tn)
                if c["uq"]:
                    claim(sc, "UQ_%s_%s" % (tn, c["name"])); s += "\n        %-18s CONSTRAINT UQ_%s_%s UNIQUE" % ("", tn, c["name"])
                ck = col_check(full, c)
                if ck:
                    claim(sc, "CK_%s_%s" % (tn, c["name"]))
                    s += "\n        %-18s CONSTRAINT CK_%s_%s CHECK (%s)" % ("", tn, c["name"], ck)
                    m = re.match(r"\w+ IN \((.*)\)$", ck)
                    if m:
                        mx = max(len(x.strip("'")) for x in m.group(1).split(","))
                        ln = re.search(r"\((\d+)\)", c["type"])
                        if ln and mx > int(ln.group(1)): raise ValueError("Literal dài hơn cột: %s.%s" % (full, c["name"]))
                lines.append(s)
            if temporal:
                lines.append("    ValidFrom            DATETIME2(0) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL")
                lines.append("    ValidTo              DATETIME2(0) GENERATED ALWAYS AS ROW END HIDDEN NOT NULL")
            if len(pkcols) > 1:
                claim(sc, "PK_" + tn); lines.append("    CONSTRAINT PK_%s PRIMARY KEY (%s)" % (tn, ", ".join(pkcols)))
            for kind, txt in t["cons"]:
                if kind == "CK":
                    cs = ident_cols(txt, names)
                    nm = "CK_%s_%s" % (tn, "_".join(cs[:2]))
                    i = 2
                    while nm in names_by_schema.get(sc, set()):
                        nm = "CK_%s_%s" % (tn, "_".join(cs[:i + 1])); i += 1
                        if i > len(cs) + 1: nm += "_x"
                    claim(sc, nm)
                    lines.append("    CONSTRAINT %s CHECK (%s)" % (nm, txt))
                elif kind == "UQ":
                    m = re.match(r"Filtered unique index (UX_\w+ )?\((.*?)\) WHERE (.*)$", txt)
                    if m:
                        cols = m.group(2); nm = (m.group(1) or "").strip()
                        if not nm: nm = "UX_%s_%s" % (tn, cols.replace(", ", "_").replace("Id", "") if False else "Owner_Title")
                        idx_lines.append((full, nm, "UNIQUE", cols, None, fix_where(t, m.group(3))))
                        continue
                    m = re.match(r"(UQ_\w+ )?\((.*?)\)(;.*)?$", txt.replace("UQ ", "", 1) if txt.startswith("UQ (") else txt)
                    if not m: raise ValueError("UQ lạ: " + txt)
                    cols = m.group(2)
                    nm = (m.group(1) or "").strip() or "UQ_%s_%s" % (tn, cols.replace(", ", "_"))
                    claim(sc, nm); lines.append("    CONSTRAINT %s UNIQUE (%s)" % (nm, cols))
            # FK cùng schema (inline) / khác schema (02)
            for r in rel_by_from.get(full, []):
                tgt = by[r["to"]]; tpk = r["tcols"]
                clause = "FOREIGN KEY (%s) REFERENCES %s(%s)" % (", ".join(r["fcols"]), r["to"], ", ".join(tpk))
                if r["cross"]:
                    fks_cross.append("ALTER TABLE %s WITH CHECK\n    ADD CONSTRAINT %s %s;\nGO" % (full, r["name"], clause))
                else:
                    claim(sc, r["name"]); lines.append("    CONSTRAINT %s %s" % (r["name"], clause))
            if temporal:
                lines.append("    PERIOD FOR SYSTEM_TIME (ValidFrom, ValidTo)")
            body = ",\n".join(lines)
            tail = "\n) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = %s.%sHistory));" % (sc, tn) if temporal else "\n);"
            blocks.append("-- %s\nCREATE TABLE %s\n(\n%s%s\nGO\n" % (t["desc"], full, body, tail))
        out_tables[key] = "\n".join(blocks)
        out_fk[key] = "\n\n".join(fks_cross) + ("\n" if fks_cross else "")
        out_idx[key] = idx_lines
    return tables, out_tables, out_fk, out_idx, by

# ---------- Index theo Requirements D.2 ----------
IX = [
 ("lab.FilmLabs","IX_FilmLabs_Approval_City","ApprovalStatus, City","AvgRating"),
 ("lab.LabServices","IX_LabServices_Search","LabId, ServiceTypeId, FormatId","UnitPrice, TurnaroundDays"),
 ("ord.Orders","IX_Orders_Customer","CustomerId, CreatedAt DESC",None),
 ("ord.Orders","IX_Orders_Lab_Stage","LabId, StageId",None),
 ("ord.OrderItems","IX_OrderItems_Order","OrderId",None),
 ("ord.OrderStageLog","IX_OrderStageLog_Order","OrderId, ChangedAt",None),
 ("dlv.DeliveryRequests","IX_Delivery_Partner_Status","DeliveryPartnerId, Status","OrderId, Direction"),
 ("dlv.DeliveryStatusLog","IX_DeliveryLog_Request","DeliveryRequestId, ChangedAt",None),
 ("arc.ScanFiles","IX_ScanFiles_Owner","OwnerUserId, UploadedAt DESC",None),
 ("arc.ScanFiles","IX_ScanFiles_Order","OrderId",None),
 ("arc.PhotoMetadata","IX_PhotoMetadata_Stock","FilmStockId",None),
 ("arc.AlbumPhotos","IX_AlbumPhotos_ScanFile","ScanFileId",None),
 ("arc.Notifications","IX_Notifications_User","UserId, IsRead, CreatedAt DESC",None),
 ("ord.Reviews","IX_Reviews_Lab","LabId, IsVisible","RatingOverall"),
 ("ord.Complaints","IX_Complaints_Status","Status, CreatedAt",None),
 ("mkt.Listings","IX_Listings_Browse","Status, CategoryId, Price","Title, City"),
 ("mkt.MarketTransactions","IX_MktTxn_Buyer","BuyerId, CreatedAt DESC",None),
 ("mkt.MarketTransactions","IX_MktTxn_Seller_Status","SellerId, Status",None),
 ("mkt.Messages","IX_Messages_Thread","ListingId, SentAt",None),
 ("com.Articles","IX_Articles_Feed","Status, ArticleType, PublishedAt DESC",None),
 ("com.ArticleComments","IX_Comments_Article","ArticleId, CreatedAt",None),
 ("com.Events","IX_Events_Upcoming","Status, StartAt",None),
 ("com.EventRegistrations","IX_EventReg_User","UserId, Status",None),
 ("ai.AIChatLogs","IX_ChatLogs_Session","SessionId, CreatedAt",None),
 ("ai.AIChatLogs","IX_ChatLogs_User","UserId, CreatedAt DESC",None),
 ("ai.RecommendationLogs","IX_RecLogs_User","UserId, CreatedAt DESC",None),
 ("ai.RecommendationLogs","IX_RecLogs_Item","RecommendationType, ItemId",None),
 ("audit.AuditLogs","IX_Audit_Record","TableSchema, TableName, PrimaryKeyValue, ChangedAt DESC",None),
 ("audit.AuditLogs","IX_Audit_User","ChangedBy, ChangedAt DESC",None),
]
SPATIAL = [("lab.FilmLabs","SIX_FilmLabs_Location","Location")]
FT = [("mkt.Listings","PK_Listings","Title, Description"),
      ("com.Articles","PK_Articles","Title, Summary, Body"),
      ("ai.KnowledgeDocs","PK_KnowledgeDocs","Title, Content")]

def index_sql(key, uxs, by):
    out = []
    for (full, nm, kind, cols, inc, where) in uxs:
        out.append("CREATE UNIQUE NONCLUSTERED INDEX %s\n    ON %s (%s)\n    WHERE %s;\nGO\n" % (nm, full, cols, where))
    for (full, nm, cols, inc) in IX:
        if file_key(by[full]) != key: continue
        s = "CREATE NONCLUSTERED INDEX %s\n    ON %s (%s)" % (nm, full, cols)
        if inc: s += "\n    INCLUDE (%s)" % inc
        out.append(s + ";\nGO\n")
    for (full, nm, col) in SPATIAL:
        if file_key(by[full]) != key: continue
        out.append("CREATE SPATIAL INDEX %s\n    ON %s (%s)\n    USING GEOGRAPHY_AUTO_GRID;\nGO\n" % (nm, full, col))
    for (full, pk, cols) in FT:
        if file_key(by[full]) != key: continue
        out.append(
"-- Full-Text (D-20): chỉ tạo khi instance có cài Full-Text (image Linux của CI không có)\n"
"IF SERVERPROPERTY('IsFullTextInstalled') = 1\nBEGIN\n"
"    IF NOT EXISTS (SELECT 1 FROM sys.fulltext_catalogs WHERE name = N'ftc_FilmLabDB')\n"
"        EXEC(N'CREATE FULLTEXT CATALOG ftc_FilmLabDB;');\n"
"    EXEC(N'CREATE FULLTEXT INDEX ON %s (%s) KEY INDEX %s ON ftc_FilmLabDB WITH CHANGE_TRACKING AUTO;');\nEND\nGO\n"
            % (full, ", ".join("%s LANGUAGE 0" % c.strip() for c in cols.split(",")), pk))
    return "\n".join(out)

def write_into(path, body, marker="-- TODO: viết nội dung tại đây"):
    src = open(path, encoding="utf-8").read()
    if marker in src: head = src.split(marker)[0]
    else: head = src.rstrip("\n") + "\n\n"
    # cắt phần SET đã chèn lần chạy trước
    head = head.split("SET QUOTED_IDENTIFIER ON;")[0].split("-- Không có dữ liệu danh mục")[0]
    open(path, "w", encoding="utf-8", newline="\n").write(head + body)

def main():
    tables, tb, fk, idx, by = build()
    for key in S.MODULE_ORDER + ["ord_feedback"]:
        write_into(os.path.join(ROOT, "01_tables", key + ".sql"), SETOPT + "\n" + tb[key])
        write_into(os.path.join(ROOT, "02_foreign_keys", key + ".sql"),
                   SETOPT + "\n" + (fk[key] if fk[key].strip() else "-- (không có FK liên module)\n"))
        write_into(os.path.join(ROOT, "03_indexes", key + ".sql"), SETOPT + "\n" + index_sql(key, idx[key], by))
    print("OK: đã sinh 01_tables, 02_foreign_keys, 03_indexes cho 10 file")

if __name__ == "__main__":
    main()
