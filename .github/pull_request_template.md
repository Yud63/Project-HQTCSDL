## Mô tả
<!-- Module nào (iam/lab/ord/...)? Thêm/sửa gì? -->

## Checklist (tick hết mới xin merge)
- [ ] Chỉ sửa file thuộc module của mình (không đụng file module khác)
- [ ] Đã chạy `build.cmd` / `build.sh` với `REBUILD=1` trên máy mình, không lỗi
- [ ] Đặt tên đúng `docs/Conventions.md` (schema, PK/FK/CK/UQ/DF/IX, kiểu dữ liệu chuẩn)
- [ ] Không gõ tay chuỗi trạng thái; dùng bảng danh mục + FK
- [ ] Không ghi trực tiếp vào bảng module khác (gọi procedure của module đó)
- [ ] Procedure theo template (TRY/CATCH, THROW đúng dải mã lỗi); Trigger set-based
- [ ] Nếu đổi cột/bảng/chữ ký procedure đã công bố: đã cập nhật `docs/Contracts.md`
- [ ] Đã thêm/cập nhật test trong `tests/` (nếu có logic mới)
