# -*- coding: utf-8 -*-
"""Sinh docs/Contracts.md, docs/Normalization.md, docs/Phan-cong.md từ schema_spec.py + plan_spec.py."""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import schema_spec as S
import plan_spec as P
import spec_loader as L

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

def w(rel, text):
    path = os.path.join(ROOT, rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    open(path, "w", encoding="utf-8", newline="\n").write(text)
    print("Đã ghi", rel)

tb = L.load()
errs = L.validate(tb)
if errs: raise SystemExit("\n".join(errs))
rels = L.assign_fk_names(L.relationships(tb))
by = {t["full"]: t for t in tb}
deps = L.module_deps(tb, rels)
create = L.create_order(tb, rels)
topo = L.module_toposort(deps)

# ---------- kiểm tra chéo giữa spec bảng và kế hoạch ----------
unit_tables = {u[0]: [u[1] + "." + x for x in u[5]] for u in P.UNITS}
all_listed = [x for v in unit_tables.values() for x in v]
assert sorted(all_listed) == sorted(by.keys()), "UNITS không khớp danh sách bảng của schema_spec"
assert len(P.PROCS) == 42 and sum(1 for p in P.PROCS if p[2]) == 16, "Phải có 42 procedure, 16 bắt buộc"
assert len(P.FUNCS) == 14 and len(P.TRIGGERS) == 28 and len(P.VIEWS) == 14
assert sum(u[4] for u in P.UNITS) == 114, "Tổng business rule phải là 114"
star_names = {p[1] for p in P.PROCS if p[2]}
sig_names = {s[0].split(".")[1] for s in P.STAR_SIGNATURES}
assert star_names == sig_names, "Chữ ký ★ không khớp danh sách ★: %s" % (star_names ^ sig_names)
assert [m for m in S.MODULE_ORDER] == [m for m in S.MODULE_ORDER if all(d in S.MODULE_ORDER[:S.MODULE_ORDER.index(m)] for d in deps[m])], \
    "Thứ tự module trong 99_run_all.sql vi phạm phụ thuộc FK"

owner_of = {}
for member, (units, _) in P.ASSIGN.items():
    for u in units: owner_of[u] = member
assert set(owner_of) == {u[0] for u in P.UNITS}, "Có module chưa được phân công"

def unit_stats(u):
    uid = u[0]
    nt = len(u[5]); br = u[4]
    star = sum(1 for p in P.PROCS if p[0] == uid and p[2])
    ext = sum(1 for p in P.PROCS if p[0] == uid and not p[2])
    fn = sum(1 for f in P.FUNCS if f[0] == uid)
    tg = sum(1 for t in P.TRIGGERS if t[0] == uid)
    vw = sum(1 for v in P.VIEWS if v[0] == uid)
    pts = nt*P.W["table"] + br*P.W["br"] + star*P.W["star"] + ext*P.W["ext"] + fn*P.W["fn"] + tg*P.W["trg"] + vw*P.W["view"]
    return dict(tables=nt, br=br, star=star, ext=ext, fn=fn, trg=tg, view=vw, pts=pts)

STATS = {u[0]: unit_stats(u) for u in P.UNITS}
UNIT = {u[0]: u for u in P.UNITS}

# =====================================================================
# CONTRACTS
# =====================================================================
c = []
c.append("# Contracts: hợp đồng giữa các module (v1.0, đóng băng ở Đợt 4)\n")
c.append("> Phần bảng và quan hệ được **sinh tự động** từ `tools/schema_spec.py` và `tools/plan_spec.py` (`python tools/gen_docs.py`).")
c.append("> **Quy tắc thay đổi:** muốn đổi cột/bảng/chữ ký procedure đã nêu ở đây thì (1) sửa `schema_spec.py` / `plan_spec.py`, (2) chạy lại các script sinh tài liệu, (3) ghi vào mục 10 (Nhật ký thay đổi), (4) báo cả nhóm trong cùng Pull Request.\n")

c.append("## 1. Quyết định thiết kế đã chốt\n")
c.append("Các quyết định D-01 đến D-15 là **mặc định** của các câu hỏi đã nêu ở Đợt 1, 2, 3. Nhóm phản đối điều nào thì nói **trước khi bắt đầu Đợt 5** (sau đó sửa sẽ tốn công).\n")
c.append("| Mã | Quyết định | Nguồn |\n|---|---|---|")
for d in P.DECISIONS: c.append("| %s | %s | %s |" % d)
c.append("")

c.append("## 2. Module, file sở hữu và phụ thuộc FK\n")
c.append("| Module (unit) | Schema | File ở mỗi tầng `database/<tầng>/` | Bảng | Phụ thuộc FK | Người phụ trách |\n|---|---|---|---|---|---|")
for u in P.UNITS:
    uid, sch, fname, title, br, tabs = u
    dep = ", ".join("`%s`" % d for d in S.MODULE_ORDER if d in deps[sch]) or "(gốc)"
    if sch == "audit": dep = "(không FK, chỉ ghi log)"
    c.append("| %s | `%s` | `%s.sql` | %s | %s | %s |" % (title, sch, fname, ", ".join(tabs), dep, owner_of[uid]))
c.append("\n**Người phụ trách** ghi bằng chữ cái A-E, đối chiếu `docs/Phan-cong.md`.\n")

c.append("## 3. Ma trận phụ thuộc FK giữa các schema\n")
c.append("Hàng = schema chứa bảng **con** (có FK); cột = schema chứa bảng **cha** (được trỏ tới). Dấu `x` kèm số FK.\n")
hdr = "| con \\ cha | " + " | ".join("`%s`" % m for m in S.MODULE_ORDER) + " |"
c.append(hdr); c.append("|---|" + "---|" * len(S.MODULE_ORDER))
for a in S.MODULE_ORDER:
    row = []
    for b in S.MODULE_ORDER:
        if a == b: row.append("")
        else:
            n = sum(1 for r in rels if r["frm"].split(".")[0] == a and r["to"].split(".")[0] == b)
            row.append("x%d" % n if n else "")
    c.append("| `%s` | " % a + " | ".join(row) + " |")
c.append("\nThứ tự dựng module hợp lệ (đã kiểm tra, không có vòng): " + " -> ".join("`%s`" % m for m in S.MODULE_ORDER) + ".")
c.append("Tổng số FK: **%d** (liên module **%d**, cùng module **%d**).\n" % (len(rels), sum(1 for r in rels if r["cross"]), sum(1 for r in rels if not r["cross"])))

c.append("## 4. Phụ thuộc gọi giữa các module (không phải FK)\n")
c.append("T-SQL phân giải tên procedure/function **lúc chạy** (deferred name resolution), nên `CREATE OR ALTER` không lỗi dù đối tượng được gọi ở file chạy sau. Chỉ cần đã build đủ trước khi **gọi**.\n")
c.append("| Đối tượng gọi | Gọi tới |\n|---|---|")
for a, b in P.CALL_DEPS: c.append("| `%s` | %s |" % (a, b))
c.append("")

c.append("## 5. Thứ tự tạo bảng trong từng module (từ FK cùng module)\n")
c.append("Dùng khi viết `01_tables/<module>.sql`. FK liên module **không** tạo ở đây mà ở `02_foreign_keys/`.\n")
c.append("| File (`01_tables/<file>.sql`) | Người | Thứ tự `CREATE TABLE` |\n|---|---|---|")
for u in P.UNITS:
    ut = set(unit_tables[u[0]])
    seq = [x.split(".")[1] for x in create[u[1]] if x in ut]
    c.append("| `%s.sql` | %s | %s |" % (u[2], owner_of[u[0]], " -> ".join(seq)))
c.append("\nLưu ý: `ord_feedback.sql` chạy **ngay sau** `ord.sql` (FK ghép của `Reviews`, `Complaints` trỏ tới `ord.Orders`).\n")

c.append("## 6. Quy ước mã lỗi (`THROW`)\n")
c.append("Mã lỗi = **dải của module** + **hậu tố hai chữ số** theo ý nghĩa thống nhất. Thông báo bằng tiếng Việt.\n")
c.append("**Dải mã theo module:**\n")
c.append("| Dải | Module |\n|---|---|")
bases = [("50100","iam"),("50200","lab"),("50300","ord (gồm review, complaint)"),("50400","dlv"),("50500","arc"),("50600","mkt"),("50700","com"),("50800","ai"),("50900","audit")]
for b in bases: c.append("| %s | %s |" % b)
c.append("\n**Hậu tố (cộng vào dải):**\n")
c.append("| Hậu tố | Ý nghĩa |\n|---|---|")
suffix = [("01","Không tìm thấy (NotFound)"),("02","Sai trạng thái / chuyển trạng thái không hợp lệ"),("03","Không có quyền (không phải chủ/Admin)"),("04","Trùng / xung đột (Duplicate)"),("05","Dữ liệu đầu vào sai (Validation)"),("06","Hết năng lực / hết hàng (Capacity)")]
for s in suffix: c.append("| %s | %s |" % s)
c.append("\nVí dụ: `50302` = module `ord`, sai trạng thái. Mọi procedure ghi dữ liệu đều nhận `@ActorUserId` (hoặc tham số tương đương như `@CustomerId`, `@SellerId`) và gọi `EXEC sp_set_session_context @key = N'UserId', @value = @ActorUserId;` ở đầu để trigger/RLS biết người thực hiện.\n")

c.append("## 7. Chữ ký 16 procedure bắt buộc (★)\n")
c.append("Đây là **API của database**; web và test chỉ phụ thuộc vào các chữ ký này. Tham số có `=` là tùy chọn.\n")
c.append("| # | Procedure | Tham số | Kết quả | Mã lỗi chính | Gọi tới |\n|---|---|---|---|---|---|")
for i, (n, prm, res, err, calls) in enumerate(P.STAR_SIGNATURES, start=1):
    c.append("| %d | `%s` | `%s` | %s | %s | %s |" % (i, n, prm.replace("|", "/"), res, err, calls))
c.append("")

c.append("## 8. Danh mục đối tượng T-SQL (kế hoạch)\n")
c.append("★ = procedure bắt buộc. Tổng: **%d procedure** (16 bắt buộc, %d mở rộng), **%d function**, **%d trigger**, **%d view**, **%d sequence**.\n" % (
    len(P.PROCS), len(P.PROCS) - 16, len(P.FUNCS), len(P.TRIGGERS), len(P.VIEWS), len(P.SEQUENCES)))
for u in P.UNITS:
    uid, sch = u[0], u[1]
    procs = [p for p in P.PROCS if p[0] == uid]
    funcs = [f for f in P.FUNCS if f[0] == uid]
    trgs = [t for t in P.TRIGGERS if t[0] == uid]
    vws = [v for v in P.VIEWS if v[0] == uid]
    seqs = [s for s in P.SEQUENCES if s[0] == sch and uid == sch]
    c.append("### `%s`: %s (người phụ trách %s)\n" % (uid, u[3], owner_of[uid]))
    c.append("| Loại | Tên | Mục đích |\n|---|---|---|")
    for p in procs: c.append("| Procedure%s | `%s.%s` | %s |" % (" ★" if p[2] else "", sch, p[1], p[3]))
    for f in funcs: c.append("| Function | `%s.%s` | %s |" % (sch, f[1], f[2]))
    for t in trgs: c.append("| Trigger | `%s.%s` (trên `%s`) | %s |" % (sch, t[1], t[2], t[3]))
    for v in vws: c.append("| View | `%s.%s` | %s |" % (sch, v[1], v[2]))
    for s in seqs: c.append("| Sequence | `%s.%s` | Sinh mã tự động |" % (s[0], s[1]))
    if len(c[-1]) == 0 or c[-1].startswith("| Loại"): c.append("| (chưa có đối tượng T-SQL) | | |")
    c.append("")

c.append("## 9. Danh sách FK (tên theo quy ước, dùng khi viết 02_foreign_keys)\n")
c.append("Danh sách đầy đủ 77 FK (kèm bảng cha/cột, bản số, tầng tạo) nằm ở `docs/DataDictionary.xlsx`, sheet `Relationships`. Tên FK: `FK_<Bảng con>_<Bảng cha>`, trùng thì thêm `_<Cột>`.\n")
c.append("| Schema (con) | FK liên module (tạo ở `02_foreign_keys/<file>.sql`) |\n|---|---|")
for m in S.MODULE_ORDER:
    names = [r["name"] for r in rels if r["cross"] and r["frm"].split(".")[0] == m]
    if names: c.append("| `%s` | %s |" % (m, ", ".join("`%s`" % n for n in names)))
c.append("")

c.append("## 10. Nhật ký thay đổi hợp đồng\n")
c.append("| Phiên bản | Ngày | Người đổi | Thay đổi | Ảnh hưởng |\n|---|---|---|---|---|")
c.append("| 1.0 | (Đợt 4) | Nhóm | Đóng băng thiết kế: 41 bảng, 77 FK, 42 procedure | Toàn bộ |")
_log = os.path.join(os.path.dirname(os.path.abspath(__file__)), "contracts_changelog.md")
if os.path.exists(_log):
    for _line in open(_log, encoding="utf-8").read().splitlines():
        if _line.strip():
            c.append(_line)
w("docs/Contracts.md", "\n".join(c) + "\n")

# =====================================================================
# NORMALIZATION
# =====================================================================
EXC = {
 "iam.Addresses": ("2NF*", "Ward -> District -> City là phụ thuộc bắc cầu (địa chỉ nhập tự do, xem DN-4)"),
 "lab.FilmLabs": ("2NF*", "Ward -> District -> City bắc cầu (DN-4); AvgRating/ReviewCount là dữ liệu dẫn xuất từ Reviews (DN-1); cột JSON (DN-9)"),
 "ord.Orders": ("2NF*", "(Subtotal, DeliveryFee) -> TotalAmount; Subtotal/PlatformFee dẫn xuất và chốt lúc đặt (DN-2)"),
 "ord.OrderItems": ("2NF*", "(Quantity, UnitPriceSnapshot) -> LineTotal là cột tính; UnitPriceSnapshot chốt giá (DN-3)"),
 "ord.Complaints": ("2NF*", "OrderId -> (CustomerId, LabId) nhưng OrderId không phải khóa của bảng này (DN-5)"),
 "arc.ScanFiles": ("2NF*", "OrderId -> OwnerUserId (DN-6); QualityScore -> QualityStatus (DN-7)"),
 "mkt.MarketTransactions": ("2NF*", "ListingId -> SellerId (DN-8); (Quantity, UnitPrice) -> TotalAmount cột tính"),
 "com.Articles": ("3NF (không BCNF)", "Title -> Slug nhưng Slug là khóa ứng viên (unique) nên vẫn đạt 3NF (DN-10); cột JSON Tags (DN-9)"),
 "ord.Reviews": ("3NF", "CustomerId, LabId phụ thuộc OrderId (là khóa ứng viên nên không vi phạm); dư thừa liên bảng với Orders được FK ghép kiểm soát (DN-5)"),
 "arc.PhotoMetadata": ("3NF", "Cột JSON ExtraJson (DN-9)"),
 "ai.UserPreferences": ("3NF", "Cột JSON ExtraJson (DN-9)"),
 "ai.AIChatLogs": ("3NF", "Cột JSON SourcesJson (DN-9)"),
 "ai.RecommendationLogs": ("3NF", "ItemId không FK có chủ ý (DN-11); cột JSON ContextJson (DN-9)"),
 "ai.KnowledgeDocs": ("3NF", "Cột JSON EmbeddingJson (DN-9)"),
 "audit.AuditLogs": ("3NF", "ChangedBy không FK có chủ ý (DN-11); cột JSON OldValues/NewValues (DN-9)"),
}
n = []
n.append("# Kiểm tra chuẩn hóa (1NF, 2NF, 3NF)\n")
n.append("> Bảng tổng hợp ở mục 4 được sinh từ `tools/schema_spec.py`. Phần phân tích (mục 1 đến 3, 5, 6) viết tay, dùng trực tiếp cho chương Thiết kế CSDL của báo cáo.\n")
n.append("## 1. Phương pháp\n")
n.append("| Bước | Việc làm |\n|---|---|")
n.append("| 1 | Với mỗi bảng, xác định khóa chính và các khóa ứng viên khác (cột `UNIQUE`, filtered unique index) |")
n.append("| 2 | Liệt kê phụ thuộc hàm (FD) giữa các thuộc tính từ business rule |")
n.append("| 3 | **1NF**: mỗi ô một giá trị nguyên tử, không nhóm lặp |")
n.append("| 4 | **2NF**: với khóa ghép, thuộc tính không khóa phụ thuộc vào **toàn bộ** khóa (không phụ thuộc một phần) |")
n.append("| 5 | **3NF**: thuộc tính không khóa không phụ thuộc bắc cầu vào khóa (không có FD giữa hai thuộc tính không khóa) |")
n.append("| 6 | Chỗ nào cố ý vi phạm thì ghi lại lý do và **cơ chế giữ nhất quán** (mục 3) |\n")
n.append("Ký hiệu cột Dạng chuẩn: `3NF` = đạt; `2NF*` = đạt 2NF nhưng **cố ý** không đạt 3NF (xem mục 3).\n")

n.append("## 2. Ví dụ minh họa: từ bảng phẳng đến 3NF\n")
n.append("Bắt đầu từ một \"phiếu đơn hàng\" phẳng mà tiệm lab thường ghi sổ:\n")
n.append("| OrderCode | CustomerName | CustomerEmail | LabName | LabCity | ServiceName | Price | Qty | FilmStocks | StageName |\n|---|---|---|---|---|---|---|---|---|---|")
n.append("| FL-001 | An | an@mail.vn | Lab Sài Gòn | HCM | Tráng C-41; Scan High | 60000; 90000 | 1; 1 | Portra 400; Portra 400 | Scanning |")
n.append("")
n.append("| Dạng | Vấn đề | Cách xử lý | Kết quả trong thiết kế |\n|---|---|---|---|")
n.append("| Chưa chuẩn | Ô chứa nhiều giá trị (`ServiceName`, `Price`, `Qty`, `FilmStocks`) | **1NF**: tách mỗi dịch vụ thành một dòng | `ord.OrderItems` (1 dòng/dịch vụ) |")
n.append("| 1NF | Khóa (OrderCode, ServiceName): `CustomerName`, `LabName`, `StageName` chỉ phụ thuộc `OrderCode` (phụ thuộc một phần); `Price` phụ thuộc (LabName, ServiceName) | **2NF**: tách theo phần khóa | `ord.Orders` (thông tin đơn), `lab.LabServices` (giá theo lab+dịch vụ) |")
n.append("| 2NF | `OrderCode -> CustomerEmail -> CustomerName` (bắc cầu); `OrderCode -> LabName -> LabCity`; `OrderCode -> StageName` qua giai đoạn | **3NF**: tách thực thể có khóa riêng | `iam.Users`, `lab.FilmLabs`, `ord.ProcessingStages` |")
n.append("| 3NF | `Price` đổi theo thời gian nhưng đơn cũ phải giữ giá cũ | Lưu **snapshot** có chủ ý | `OrderItems.UnitPriceSnapshot` (DN-3) |\n")

n.append("## 3. Các điểm phi chuẩn hóa / ngoại lệ có chủ ý\n")
n.append("Mỗi ngoại lệ có lý do và cơ chế bảo đảm nhất quán; đây là chỗ giảng viên thường hỏi.\n")
n.append("| Mã | Vị trí | Vi phạm | Lý do giữ | Cơ chế giữ nhất quán | Phương án chuẩn hóa hoàn toàn (không chọn) |\n|---|---|---|---|---|---|")
DN = [
 ("DN-1","`lab.FilmLabs.AvgRating`, `ReviewCount`","Dữ liệu dẫn xuất từ `ord.Reviews`","Tìm/xếp hạng lab đọc rất nhiều, tính lại mỗi lần tốn kém","Trigger `trg_Reviews_UpdateRating` gọi `lab.sp_RecalcLabRating`; DENY UPDATE trực tiếp 2 cột","Bỏ 2 cột, tính bằng `fn_LabAvgRating` mỗi lần truy vấn"),
 ("DN-2","`ord.Orders.Subtotal`, `PlatformFee`, `TotalAmount`","Dẫn xuất/chốt từ OrderItems và FeeConfigs","Đơn là chứng từ tài chính: tổng tiền không được đổi khi giá hay phí đổi","CHECK `TotalAmount = Subtotal + DeliveryFee`; `sp_CreateOrder` tính trong Transaction","Tính tổng từ OrderItems mỗi lần đọc"),
 ("DN-3","`ord.OrderItems.UnitPriceSnapshot`, `LineTotal`","Lặp giá của `lab.LabServices`; LineTotal là cột tính","Giữ đúng giá lúc đặt dù lab đổi giá sau đó","Chốt trong `sp_CreateOrder`; `LabServices` là Temporal Table nên vẫn truy được giá lịch sử","Tra giá theo thời điểm đặt từ bảng lịch sử"),
 ("DN-4","`iam.Addresses`, `lab.FilmLabs`: Ward/District/City","Bắc cầu Ward -> District -> City","Địa chỉ nhập tự do, hiển thị nguyên văn; không cần bảng đơn vị hành chính cho đồ án","Bắt buộc không NULL; không có ràng buộc chéo","Bảng `AdministrativeUnits` có cây Tỉnh/Quận/Phường"),
 ("DN-5","`ord.Reviews`, `ord.Complaints`: CustomerId, LabId","`OrderId -> (CustomerId, LabId)`, dư thừa với Orders","Lọc theo lab/khách không cần JOIN; làm khóa RLS multi-tenant","**FK ghép** (OrderId, CustomerId, LabId) -> `ord.Orders`: DB không cho lệch","Chỉ giữ OrderId, JOIN Orders khi cần"),
 ("DN-6","`arc.ScanFiles.OwnerUserId`","`OrderId -> OwnerUserId` (= Orders.CustomerId)","Digital Film Archive và RLS lọc theo chủ ảnh rất thường xuyên","`trg_ScanFiles_CheckOwner` + `sp_UploadScan` bảo đảm bằng `Orders.CustomerId`","JOIN Orders để biết chủ ảnh"),
 ("DN-7","`arc.ScanFiles.QualityStatus`","`QualityScore -> QualityStatus` theo ngưỡng","Lọc ảnh Warning/Failed nhanh, ngưỡng nằm trong procedure","Chỉ `sp_SetScanQuality` ghi cả hai cột; CHECK `NotChecked` thì chưa có điểm","Tính trạng thái từ điểm khi truy vấn"),
 ("DN-8","`mkt.MarketTransactions.SellerId`","`ListingId -> SellerId`","Người bán xem giao dịch của mình không cần JOIN; làm khóa RLS","**FK ghép** (ListingId, SellerId) -> `mkt.Listings`","Chỉ giữ ListingId"),
 ("DN-9","Cột JSON: `OpenHoursJson`, `SpecialTechniques`, `Tags`, `ExtraJson` (x2), `SourcesJson`, `ContextJson`, `EmbeddingJson`, `OldValues`, `NewValues`","**1NF**: giá trị đa trị/có cấu trúc trong một ô","Dữ liệu bán cấu trúc, thay đổi theo thời gian, chỉ đọc qua `OPENJSON`; tách bảng làm phình số bảng mà ít giá trị","CHECK `ISJSON = 1`; truy xuất qua `OPENJSON`/`JSON_VALUE` (điểm cộng SQL Server 2022)","Bảng con (LabOpenHours, LabTechniques, ArticleTags...)"),
 ("DN-10","`com.Articles.Slug`","`Title -> Slug`","Slug là đường dẫn duy nhất của bài, dùng làm khóa tra cứu","Filtered unique index; Slug là khóa ứng viên nên vẫn 3NF (chỉ không BCNF)","Sinh Slug lúc hiển thị từ Title"),
 ("DN-11","`ai.RecommendationLogs.ItemId`, `audit.AuditLogs.ChangedBy`","Tham chiếu không có FK","Log phải tồn tại độc lập: ItemId trỏ nhiều bảng khác nhau (đa hình), nhật ký không được bị chặn khi dữ liệu nguồn đổi","Quy ước + `RecommendationType` xác định bảng đích; `audit.sp_WriteAudit` là điểm ghi duy nhất","Một bảng log riêng cho từng loại gợi ý, FK đầy đủ"),
]
for d in DN: n.append("| " + " | ".join(d) + " |")
n.append("")

n.append("## 4. Bảng tổng hợp 41 bảng\n")
n.append("| Bảng | Khóa chính | Khóa ứng viên khác | Dạng chuẩn | Ghi chú |\n|---|---|---|---|---|")
exc_count = 0
for t in tb:
    pk = ", ".join(c_["name"] for c_ in t["cols"] if c_["pk"])
    keys = [c_["name"] for c_ in t["cols"] if c_["uq"] and not c_["pk"]]
    for (typ, txt) in t["cons"]:
        if typ == "UQ":
            short = txt.split(";")[0]
            if short.startswith("Filtered unique index "):
                short = short.replace("Filtered unique index ", "").split(" WHERE")[0] + " [lọc]"
            keys.append(short)
    nf, note = EXC.get(t["full"], ("3NF", ""))
    if nf.startswith("2NF"): exc_count += 1
    if t["kind"] == "Junction" and not note: note = "Khóa ghép; mọi thuộc tính phụ thuộc toàn bộ khóa"
    n.append("| `%s` | %s | %s | %s | %s |" % (t["full"], pk, "; ".join(keys) if keys else "(không)", nf, note))
full3 = len(tb) - exc_count
json_cols = sum(1 for t in tb for c_ in t["cols"] if "ISJSON" in c_["note"])
json_tables = sum(1 for t in tb if any("ISJSON" in c_["note"] for c_ in t["cols"]))
n.append("")
n.append("**Kết quả:** %d/%d bảng đạt 3NF; %d bảng (`2NF*`) cố ý không đạt 3NF theo DN-1 đến DN-8. Ngoài ra các cột JSON (DN-9) là ngoại lệ **1NF** có chủ ý (%d cột JSON ở %d bảng), và 2 cột không có FK có chủ ý (DN-11).\n" % (full3, len(tb), exc_count, json_cols, json_tables))

n.append("## 5. Ví dụ kiểm tra chi tiết\n")
n.append("### 5.1. `ord.Orders`\n")
n.append("| Thuộc tính | FD | Nhận xét |\n|---|---|---|")
n.append("| `OrderId` | khóa chính | |")
n.append("| `OrderCode` | khóa ứng viên (UNIQUE) | `OrderCode -> mọi thuộc tính` |")
n.append("| `CustomerId, LabId, StageId, FulfillmentMethod, ...` | phụ thuộc trực tiếp vào `OrderId` | Đạt 2NF (khóa đơn) |")
n.append("| `TotalAmount` | `(Subtotal, DeliveryFee) -> TotalAmount` | FD giữa hai nhóm thuộc tính không khóa: **không 3NF**, ngoại lệ DN-2 (chứng từ tài chính) |")
n.append("\n### 5.2. `com.EventRegistrations` (khóa ghép)\n")
n.append("| Thuộc tính | Phụ thuộc vào | Nhận xét |\n|---|---|---|")
n.append("| `Status`, `IsPaid`, `CancelledAt` | **toàn bộ** (`EventId`, `UserId`): trạng thái đăng ký của *người này* ở *sự kiện này* | Không phụ thuộc một phần nên đạt 2NF |")
n.append("| Thông tin sự kiện (tên, giờ, địa điểm) | chỉ `EventId` | Đã tách sang `com.Events` để tránh phụ thuộc một phần |")
n.append("\n### 5.3. `arc.ScanFiles` và `arc.PhotoMetadata`\n")
n.append("Metadata tách thành bảng 1-1 (`PhotoMetadata`, khóa chính = FK tới `ScanFiles`) vì: (1) nhiều file chưa có metadata nên tránh nhiều cột NULL ở bảng chính; (2) hai nhóm thuộc tính có vòng đời khác nhau (file do lab upload, metadata do khách/lab bổ sung sau).\n")
n.append("### 5.4. `lab.LabServices`\n")
n.append("Khóa ứng viên `(LabId, PackageName)`; `UnitPrice`, `TurnaroundDays`, `ScanQuality` phụ thuộc đầy đủ vào gói của một lab. Đạt 3NF. `ProcessCode` không suy ra từ `ServiceTypeId` (gói Scan dùng `'ANY'`), nên không có FD bắc cầu.\n")

n.append("## 6. Kết luận cho báo cáo\n")
n.append("- Thiết kế đạt **3NF ở %d/%d bảng**; %d bảng phi chuẩn hóa có chủ ý, mỗi bảng có lý do nghiệp vụ và cơ chế kiểm soát (FK ghép, trigger, CHECK, procedure).\n" % (full3, len(tb), exc_count))
n.append("- Phi chuẩn hóa tập trung vào hai mục đích: **(a) snapshot chứng từ** (giá, phí, tổng tiền không đổi theo thời gian) và **(b) tăng tốc truy vấn đọc nhiều** (rating, chủ ảnh, khóa RLS).")
n.append("- Mọi phi chuẩn hóa dạng *dẫn xuất* đều có đúng một nơi ghi (procedure hoặc trigger) để tránh dị thường cập nhật.")
w("docs/Normalization.md", "\n".join(n) + "\n")

# =====================================================================
# PHÂN CÔNG
# =====================================================================
p = []
p.append("# Phân công nhóm 5 người\n")
p.append("> Bảng số liệu được **sinh tự động** từ `tools/plan_spec.py` (`python tools/gen_docs.py`). Điểm công sức là **ước lượng** (sai số khoảng 15%); nhóm rà lại ở mốc cuối tuần 2 rồi chuyển việc nếu lệch.\n")
p.append("## 1. Phân công theo module\n")
p.append("Điền họ tên vào cột đầu. Mỗi người sở hữu các file `database/<tầng>/<module>.sql` của module mình (không sửa file của người khác).\n")
p.append("| Thành viên | Họ tên | Module sở hữu | Bảng | Business rule | Procedure ★ / mở rộng | Function | Trigger | View |\n|---|---|---|---|---|---|---|---|---|")
member_pts = {}
for m, (units, cross) in P.ASSIGN.items():
    s = {k: sum(STATS[u][k] for u in units) for k in ["tables","br","star","ext","fn","trg","view","pts"]}
    cp = sum(x[1] for x in cross)
    member_pts[m] = (s["pts"], cp, P.REPORT_POINTS_EACH, s["pts"] + cp + P.REPORT_POINTS_EACH)
    p.append("| **%s** | ____ | %s | %d | %d | %d / %d | %d | %d | %d |" % (
        m, ", ".join("`%s`" % UNIT[u][2] for u in units), s["tables"], s["br"], s["star"], s["ext"], s["fn"], s["trg"], s["view"]))
tot = {k: sum(STATS[u][k] for u in STATS) for k in ["tables","br","star","ext","fn","trg","view"]}
p.append("| **Tổng** | | | %d | %d | %d / %d | %d | %d | %d |\n" % (tot["tables"], tot["br"], tot["star"], tot["ext"], tot["fn"], tot["trg"], tot["view"]))

p.append("## 2. Công việc chung (ngoài module)\n")
p.append("| Thành viên | Việc | Điểm |\n|---|---|---|")
for m, (units, cross) in P.ASSIGN.items():
    for (t_, pt) in cross: p.append("| %s | %s | %g |" % (m, t_, pt))
p.append("| Cả nhóm | Viết báo cáo: mỗi người viết phần module của mình | %g mỗi người |\n" % P.REPORT_POINTS_EACH)

p.append("## 3. Cân bằng khối lượng\n")
p.append("Điểm module = bảng x %g + business rule x %g + procedure ★ x %g + procedure mở rộng x %g + function x %g + trigger x %g + view x %g.\n" % (
    P.W["table"], P.W["br"], P.W["star"], P.W["ext"], P.W["fn"], P.W["trg"], P.W["view"]))
p.append("| Thành viên | Điểm module | Việc chung | Báo cáo | **Tổng** | So với trung bình |\n|---|---|---|---|---|---|")
avg = sum(v[3] for v in member_pts.values()) / len(member_pts)
for m, (a, b, c_, d) in member_pts.items():
    p.append("| %s | %.1f | %.1f | %.1f | **%.1f** | %+.0f%% |" % (m, a, b, c_, d, (d - avg) / avg * 100))
p.append("| Trung bình | | | | %.1f | |\n" % avg)
spread = max(v[3] for v in member_pts.values()) - min(v[3] for v in member_pts.values())
assert spread / avg < 0.15, "Phân công lệch quá 15%%: %.1f" % (spread / avg * 100)

p.append("### Điểm công sức từng module\n")
p.append("| Module | Người | Bảng | BR | ★ | Mở rộng | Fn | Trg | View | **Điểm** |\n|---|---|---|---|---|---|---|---|---|---|")
for u in P.UNITS:
    s = STATS[u[0]]
    p.append("| `%s` | %s | %d | %d | %d | %d | %d | %d | %d | %.1f |" % (u[2], owner_of[u[0]], s["tables"], s["br"], s["star"], s["ext"], s["fn"], s["trg"], s["view"], s["pts"]))
p.append("")

p.append("## 4. Lý do chia như trên\n")
p.append("| Thành viên | Lý do |\n|---|---|")
p.append("| A | `iam` là module gốc mọi module khác phụ thuộc nên giao cho trưởng nhóm để làm trước; `audit` và `dlv` nhẹ; A giữ luôn bảo mật, backup, CI vì cần nhìn toàn hệ thống |")
p.append("| B | `ord` (đơn, giai đoạn, thanh toán) và `lab` là **đường găng** của hệ thống (sp_CreateOrder gọi nhiều module); hai module liền kề nhau nên ít phải phối hợp |")
p.append("| C | `ord_feedback` (review, khiếu nại) bám vào bảng `Orders` của B nhưng tách file riêng; `arc` (ảnh scan, thông báo) cùng mạch hậu xử lý đơn; C cũng giữ test tích hợp và `demo.sql` vì hiểu rõ luồng cuối đơn |")
p.append("| D | `mkt` và `com` độc lập với luồng đơn (chỉ phụ thuộc `iam`, `lab`), làm song song không chờ ai |")
p.append("| E | `ai` nhẹ về bảng nhưng cần dữ liệu từ nhiều module để chấm điểm gợi ý; E kiêm web demo và slide vì web chỉ gọi lại các procedure |")
p.append("")

p.append("## 5. Lịch theo tuần (tuần 1 đã xong khi chốt Đợt 4)\n")
p.append("| Tuần | Mục tiêu | Mốc cứng |\n|---|---|---|")
p.append("| 2 | Mỗi người viết `01_tables`, `02_foreign_keys`, `03_indexes`, `04_seed` (reference trước, sample sau) cho module mình | **Hết ngày 2**: A xong `iam` (bảng + seed reference). **Hết ngày 3**: B xong `lab`, `ord`. **Hết tuần**: `99_run_all.sql` chạy sạch trên máy cả 5 người, CI xanh |")
p.append("| 3 | `05_functions`, `06_views`, `07_procedures`, `08_triggers` cho module mình; mỗi procedure kèm test | **Giữa tuần**: B xong `sp_CreateOrder`, `sp_UpdateOrderStage` (người khác cần để test). **Hết tuần**: đủ 16 procedure ★ chạy qua test |")
p.append("| 4 | A: `09_security`, `10_backup`; B: Execution Plan trước/sau index; C: test tích hợp + `demo.sql`; E: web + slide; mọi người: viết phần báo cáo của mình | **Đầu tuần**: A xong RLS và chạy lại toàn bộ test. **Ngày -2**: tập demo, chụp ảnh dự phòng. Ngày cuối: bản chốt, chạy lại từ máy sạch |")
p.append("")
p.append("**Giúp nhau:** khi xong module sớm, người đó nhận procedure mở rộng của người khác hoặc hỗ trợ E làm web (web chỉ gọi `sp_` và `vw_`).\n")

p.append("## 6. Bàn giao phụ thuộc (ai chờ ai)\n")
p.append("| Cần | Do | Để | Khi nào |\n|---|---|---|---|")
p.append("| Bảng `iam` + seed `Roles` | A | B, D, E | Hết ngày 2 tuần 2 |")
p.append("| Bảng `lab`, `ord` + seed `ProcessingStages`, `FeeConfigs` | B | A (`dlv`), C (`arc`, `ord_feedback`) | Hết ngày 3 tuần 2 |")
p.append("| `ord.sp_UpdateOrderStage` | B | A (`dlv.sp_UpdateDeliveryStatus` gọi) | Giữa tuần 3 |")
p.append("| `arc.sp_CreateNotification` | C | Mọi người (thông báo) | Đầu tuần 3 (làm sớm vì nhiều nơi gọi) |")
p.append("| `audit.sp_WriteAudit` | A | Mọi trigger `trg_*_Audit` | Đầu tuần 3 |")
p.append("| `lab.sp_RecalcLabRating` | B | C (`trg_Reviews_UpdateRating`) | Giữa tuần 3 |")
p.append("| `dlv.sp_RequestDelivery` | A | B (`sp_CreateOrder` gọi) | Giữa tuần 3 |")
p.append("")

p.append("## 7. Vòng duyệt chéo (mỗi Pull Request cần 1 người duyệt)\n")
p.append("| Người duyệt | Duyệt bài của |\n|---|---|")
for a, b in P.REVIEW_RING: p.append("| %s | %s |" % (a, b))
p.append("")

p.append("## 8. Sở hữu file (tránh xung đột Git)\n")
p.append("Mỗi tầng có một file riêng cho từng module. Chỉ người sở hữu sửa file; sửa file người khác phải qua Pull Request của họ.\n")
p.append("| Tầng | File | Chủ sở hữu |\n|---|---|---|")
tiers = ["01_tables","02_foreign_keys","03_indexes","04_seed/reference","04_seed/sample","05_functions","06_views","07_procedures","08_triggers"]
p.append("| (mọi tầng) | " + ", ".join("`%s.sql` -> %s" % (u[2], owner_of[u[0]]) for u in P.UNITS) + " | theo module |")
p.append("| `09_security`, `10_backup`, `99_run_all.sql`, `tests/00_smoke_test.sql`, `docs/`, `tools/` | | A |")
p.append("| `tests/` (test nghiệp vụ), `demo/` | | C |")
p.append("| `web/` | | E |")
p.append("")

p.append("## 9. Rủi ro nhân sự\n")
p.append("| Rủi ro | Cách xử lý |\n|---|---|")
p.append("| B quá tải (đường găng) | Ở mốc cuối tuần 2, chuyển `lab` sang người xong sớm nhất; B giữ `ord` |")
p.append("| E vừa `ai` vừa web | `ai` làm gọn (chỉ ★ + 2 procedure mở rộng); D hoặc C hỗ trợ web khi xong module |")
p.append("| Ai đó trễ | Module độc lập nhất (`mkt`, `com`) có thể cắt phần mở rộng (xem mục \"có thể cắt\" cuối mỗi đợt Requirements) |")
w("docs/Phan-cong.md", "\n".join(p) + "\n")
print("Phân công: điểm tổng từng người:", {m: round(v[3], 1) for m, v in member_pts.items()}, "| trung bình", round(avg, 1))
