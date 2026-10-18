# tests/

| File | Việc kiểm tra |
|---|---|
| `00_smoke_test.sql` | Đủ 9 schema, đủ 5 role |

Quy ước: mỗi test là một file `NN_<ten>.sql`, test sai thì `THROW` (để CI báo đỏ), đúng thì `PRINT N'... PASS'`.
Các test nghiệp vụ (đặt đơn, đổi trạng thái, trigger, phân quyền) thêm dần khi module xong.
