# Phân công nhóm 5 người

> Bảng số liệu được **sinh tự động** từ `tools/plan_spec.py` (`python tools/gen_docs.py`). Điểm công sức là **ước lượng** (sai số khoảng 15%); nhóm rà lại ở mốc cuối tuần 2 rồi chuyển việc nếu lệch.

## 1. Phân công theo module

Điền họ tên vào cột đầu. Mỗi người sở hữu các file `database/<tầng>/<module>.sql` của module mình (không sửa file của người khác).

| Thành viên | Họ tên | Module sở hữu | Bảng | Business rule | Procedure ★ / mở rộng | Function | Trigger | View |
|---|---|---|---|---|---|---|---|---|
| **A** | ____ | `iam`, `audit`, `dlv` | 9 | 28 | 2 / 8 | 1 | 3 | 3 |
| **B** | ____ | `ord`, `lab` | 12 | 25 | 6 / 8 | 7 | 7 | 3 |
| **C** | ____ | `ord_feedback`, `arc` | 7 | 26 | 4 / 7 | 3 | 8 | 3 |
| **D** | ____ | `mkt`, `com` | 9 | 26 | 3 / 13 | 3 | 9 | 4 |
| **E** | ____ | `ai` | 4 | 9 | 1 / 5 | 1 | 1 | 1 |
| **Tổng** | | | 41 | 114 | 16 / 41 | 15 | 28 | 14 |

## 2. Công việc chung (ngoài module)

| Thành viên | Việc | Điểm |
|---|---|---|
| A | Quản lý repo, CI, merge, giữ Contracts/Conventions | 8 |
| A | Bảo mật: role, GRANT/DENY, RLS, Masking (09_security) | 15 |
| A | Backup/Restore + kịch bản phục hồi (10_backup) | 5 |
| C | Kiểm thử tích hợp end-to-end (tests/) | 10 |
| C | Kịch bản demo.sql | 8 |
| D | Rà soát index, so sánh Execution Plan trước/sau | 8 |
| E | Web demo (8-12 màn hình gọi sp_/vw_) | 45 |
| E | Slide thuyết trình | 8 |
| Cả nhóm | Viết báo cáo: mỗi người viết phần module của mình | 5 mỗi người |

## 3. Cân bằng khối lượng

Điểm module = bảng x 2 + business rule x 0.5 + procedure ★ x 3 + procedure mở rộng x 1.5 + function x 1 + trigger x 1.5 + view x 1.

| Thành viên | Điểm module | Việc chung | Báo cáo | **Tổng** | So với trung bình |
|---|---|---|---|---|---|
| A | 58.5 | 28.0 | 5.0 | **91.5** | +1% |
| B | 87.0 | 0.0 | 5.0 | **92.0** | +2% |
| C | 67.5 | 18.0 | 5.0 | **90.5** | +0% |
| D | 80.0 | 8.0 | 5.0 | **93.0** | +3% |
| E | 26.5 | 53.0 | 5.0 | **84.5** | -6% |
| Trung bình | | | | 90.3 | |

### Điểm công sức từng module

| Module | Người | Bảng | BR | ★ | Mở rộng | Fn | Trg | View | **Điểm** |
|---|---|---|---|---|---|---|---|---|---|
| `iam` | A | 6 | 10 | 1 | 5 | 0 | 1 | 0 | 29.0 |
| `lab` | B | 6 | 10 | 2 | 5 | 2 | 2 | 1 | 36.5 |
| `ord` | B | 6 | 15 | 4 | 3 | 5 | 5 | 2 | 50.5 |
| `ord_feedback` | C | 2 | 14 | 3 | 2 | 2 | 5 | 2 | 34.5 |
| `dlv` | A | 2 | 12 | 1 | 2 | 1 | 2 | 1 | 21.0 |
| `arc` | C | 5 | 12 | 1 | 5 | 1 | 3 | 1 | 33.0 |
| `mkt` | D | 5 | 15 | 2 | 7 | 2 | 6 | 2 | 47.0 |
| `com` | D | 4 | 11 | 1 | 6 | 1 | 3 | 2 | 33.0 |
| `ai` | E | 4 | 9 | 1 | 5 | 1 | 1 | 1 | 26.5 |
| `audit` | A | 1 | 6 | 0 | 1 | 0 | 0 | 2 | 8.5 |

## 4. Lý do chia như trên

| Thành viên | Lý do |
|---|---|
| A | `iam` là module gốc mọi module khác phụ thuộc nên giao cho trưởng nhóm để làm trước; `audit` và `dlv` nhẹ; A giữ luôn bảo mật, backup, CI vì cần nhìn toàn hệ thống |
| B | `ord` (đơn, giai đoạn, thanh toán) và `lab` là **đường găng** của hệ thống (sp_CreateOrder gọi nhiều module); hai module liền kề nhau nên ít phải phối hợp |
| C | `ord_feedback` (review, khiếu nại) bám vào bảng `Orders` của B nhưng tách file riêng; `arc` (ảnh scan, thông báo) cùng mạch hậu xử lý đơn; C cũng giữ test tích hợp và `demo.sql` vì hiểu rõ luồng cuối đơn |
| D | `mkt` và `com` độc lập với luồng đơn (chỉ phụ thuộc `iam`, `lab`), làm song song không chờ ai |
| E | `ai` nhẹ về bảng nhưng cần dữ liệu từ nhiều module để chấm điểm gợi ý; E kiêm web demo và slide vì web chỉ gọi lại các procedure |

## 5. Lịch theo tuần (tuần 1 đã xong khi chốt Đợt 4)

| Tuần | Mục tiêu | Mốc cứng |
|---|---|---|
| 2 | Mỗi người viết `01_tables`, `02_foreign_keys`, `03_indexes`, `04_seed` (reference trước, sample sau) cho module mình | **Hết ngày 2**: A xong `iam` (bảng + seed reference). **Hết ngày 3**: B xong `lab`, `ord`. **Hết tuần**: `99_run_all.sql` chạy sạch trên máy cả 5 người, CI xanh |
| 3 | `05_functions`, `06_views`, `07_procedures`, `08_triggers` cho module mình; mỗi procedure kèm test | **Giữa tuần**: B xong `sp_CreateOrder`, `sp_UpdateOrderStage` (người khác cần để test). **Hết tuần**: đủ 16 procedure ★ chạy qua test |
| 4 | A: `09_security`, `10_backup`; B: Execution Plan trước/sau index; C: test tích hợp + `demo.sql`; E: web + slide; mọi người: viết phần báo cáo của mình | **Đầu tuần**: A xong RLS và chạy lại toàn bộ test. **Ngày -2**: tập demo, chụp ảnh dự phòng. Ngày cuối: bản chốt, chạy lại từ máy sạch |

**Giúp nhau:** khi xong module sớm, người đó nhận procedure mở rộng của người khác hoặc hỗ trợ E làm web (web chỉ gọi `sp_` và `vw_`).

## 6. Bàn giao phụ thuộc (ai chờ ai)

| Cần | Do | Để | Khi nào |
|---|---|---|---|
| Bảng `iam` + seed `Roles` | A | B, D, E | Hết ngày 2 tuần 2 |
| Bảng `lab`, `ord` + seed `ProcessingStages`, `FeeConfigs` | B | A (`dlv`), C (`arc`, `ord_feedback`) | Hết ngày 3 tuần 2 |
| `ord.sp_UpdateOrderStage` | B | A (`dlv.sp_UpdateDeliveryStatus` gọi) | Giữa tuần 3 |
| `arc.sp_CreateNotification` | C | Mọi người (thông báo) | Đầu tuần 3 (làm sớm vì nhiều nơi gọi) |
| `audit.sp_WriteAudit` | A | Mọi trigger `trg_*_Audit` | Đầu tuần 3 |
| `lab.sp_RecalcLabRating` | B | C (`trg_Reviews_UpdateRating`) | Giữa tuần 3 |
| `dlv.sp_RequestDelivery` | A | B (`sp_CreateOrder` gọi) | Giữa tuần 3 |

## 7. Vòng duyệt chéo (mỗi Pull Request cần 1 người duyệt)

| Người duyệt | Duyệt bài của |
|---|---|
| A | B |
| B | C |
| C | D |
| D | E |
| E | A |

## 8. Sở hữu file (tránh xung đột Git)

Mỗi tầng có một file riêng cho từng module. Chỉ người sở hữu sửa file; sửa file người khác phải qua Pull Request của họ.

| Tầng | File | Chủ sở hữu |
|---|---|---|
| (mọi tầng) | `iam.sql` -> A, `lab.sql` -> B, `ord.sql` -> B, `ord_feedback.sql` -> C, `dlv.sql` -> A, `arc.sql` -> C, `mkt.sql` -> D, `com.sql` -> D, `ai.sql` -> E, `audit.sql` -> A | theo module |
| `09_security`, `10_backup`, `99_run_all.sql`, `tests/00_smoke_test.sql`, `docs/`, `tools/` | | A |
| `tests/` (test nghiệp vụ), `demo/` | | C |
| `web/` | | E |

## 9. Rủi ro nhân sự

| Rủi ro | Cách xử lý |
|---|---|
| B quá tải (đường găng) | Ở mốc cuối tuần 2, chuyển `lab` sang người xong sớm nhất; B giữ `ord` |
| E vừa `ai` vừa web | `ai` làm gọn (chỉ ★ + 2 procedure mở rộng); D hoặc C hỗ trợ web khi xong module |
| Ai đó trễ | Module độc lập nhất (`mkt`, `com`) có thể cắt phần mở rộng (xem mục "có thể cắt" cuối mỗi đợt Requirements) |
