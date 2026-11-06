# docs/

| File | Nội dung | Trạng thái |
|---|---|---|
| `Requirements.md` | Phân tích yêu cầu 41 bảng, business rule (hợp nhất Đợt 1-3) | Có |
| `DataDictionary.xlsx` | Bảng, cột, FK, ràng buộc, enum (sinh từ spec) | Có |
| `Contracts.md` | Quyết định đã chốt, chữ ký 16 procedure ★, danh mục T-SQL, mã lỗi | Có (bản gốc v1.0 chốt ở Đợt 4; thay đổi sau đó ghi ở mục 10, hiện tới bản 1.15) |
| `Normalization.md` | Kiểm tra 1NF/2NF/3NF, phi chuẩn hóa có chủ ý | Có |
| `Phan-cong.md` | Phân công 5 người, lịch, bàn giao | Có (điền họ tên) |
| `Conventions.md` | Quy ước đặt tên, kiểu, cách viết T-SQL | Có (v2) |
| `Git-Workflow.md` | Quy trình Git, Pull Request | Có |
| `BaoCao.docx` | Báo cáo cuối | Chưa có, làm sau |

`Contracts.md`, `Normalization.md`, `Phan-cong.md` và `DataDictionary.xlsx` được sinh từ `tools/` (xem `tools/README.md`), không sửa tay.

## Tài liệu ở nơi khác

| File | Nội dung |
|---|---|
| `../diagrams/ERD.md` | Sơ đồ ERD (Mermaid) |
| `../tools/contracts_changelog.md` | Nguồn của mục 10 (Nhật ký thay đổi) trong `Contracts.md` |
| `../tests/README.md` | Danh sách test 00-22 |
| `../demo/README.md` | Kịch bản demo và dữ liệu dashboard |
| `../database/10_backup/README.md` | Backup/restore, Execution Plan trước/sau index, demo khóa UPDLOCK/HOLDLOCK |
| `../web/README.md` | Web demo gọi Stored Procedure (đang chuẩn bị) |