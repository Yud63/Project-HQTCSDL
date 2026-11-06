# tools/

Công cụ sinh tài liệu từ **một nguồn dữ liệu duy nhất** để ERD, Data Dictionary, Contracts luôn khớp nhau (và ở Đợt 5 là code `CREATE TABLE`).

| File | Vai trò |
|---|---|
| `schema_spec.py` | **Nguồn sự thật**: 41 bảng, cột, kiểu, khóa, FK, ràng buộc cấp bảng. Muốn đổi thiết kế thì sửa file này |
| `plan_spec.py` | Danh mục T-SQL (61 procedure, 16 function, 28 trigger, 14 view), chữ ký 16 procedure bắt buộc, quyết định đã chốt, phân công |
| `spec_loader.py` | Đọc spec và **kiểm tra**: FK trỏ đúng bảng/kiểu, mọi bảng có khóa chính, không vòng phụ thuộc. Chạy: `python tools/spec_loader.py` |
| `gen_erd.py` | Sinh `diagrams/ERD.md` (Mermaid) |
| `gen_docs.py` | Sinh `docs/Contracts.md`, `docs/Normalization.md`, `docs/Phan-cong.md` (có kiểm tra chéo số lượng) |
| `gen_dict.py` | Sinh `docs/DataDictionary.xlsx` (cần `pip install openpyxl`; sau đó mở và lưu lại trong Excel/LibreOffice để công thức có giá trị) |

## Quy trình khi đổi thiết kế
```
sửa tools/schema_spec.py (hoặc plan_spec.py)
python tools/spec_loader.py     # phải in OK
python tools/gen_erd.py
python tools/gen_docs.py
python tools/gen_dict.py
git add -A && git commit        # CI sẽ báo đỏ nếu quên sinh lại ERD/Contracts
```

Cú pháp một cột trong `schema_spec.py`: `"Tên|KIỂU|cờ|ghi chú"`; cờ: `P` khóa chính, `N` cho phép NULL, `U` unique, `F=schema.Bang` khóa ngoại, `D=mặc định`, `G` cột tính.
