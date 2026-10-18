# Git workflow

| Hạng mục | Quy ước |
|---|---|
| Nhánh chính | `main` luôn **build được** (CI xanh); không push trực tiếp |
| Nhánh làm việc | `feature/<module>-<mo-ta>`, ví dụ `feature/ord-create-order` |
| Commit message | `<module>: <viec>` ví dụ `ord: add sp_CreateOrder` |
| Pull Request | Dùng template có sẵn, ít nhất 1 người khác duyệt |
| Tránh conflict | Mỗi module một file ở mỗi tầng; chỉ sửa file module mình |
| Trước khi push | Chạy `build.cmd` / `build.sh` với `REBUILD=1` trên máy mình |
| Đổi hợp đồng | Sửa `docs/Contracts.md` trong cùng Pull Request, báo nhóm |
| Rebase | `git pull --rebase origin main` trước khi mở Pull Request |

## Bật bảo vệ nhánh main (làm 1 lần, trên GitHub)
Settings -> Branches -> Add rule cho `main`:
- Require a pull request before merging (1 approval)
- Require status checks to pass: chọn job `build` (Build FilmLabDB)
