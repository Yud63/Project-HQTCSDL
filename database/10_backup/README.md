# database/10_backup

Các script demo **chạy tay**, không nằm trong `99_run_all.sql`. Chạy từ thư mục gốc repo, SQL Server tại `localhost`, Windows Authentication. Mọi demo có file dọn riêng: chạy xong nhớ dọn để không để sót bảng/dữ liệu trong `FilmLabDB`.

## Danh sách file

| File | Nhóm | Nội dung |
|---|---|---|
| `01_backup.sql`, `02_restore.sql` | Backup/Restore | Full, Differential, Log backup, xóa nhầm có `MARK`, restore point-in-time. Chạy 01 rồi 02, không dùng `-d FilmLabDB` |
| `03_execution_plan.sql` | Execution Plan (bản đầu) | Bảng `dbo.PlanDemo` 200.000 dòng, chạy trong SSMS (Ctrl+M) |
| `04a`..`04e_orders_plan_*.sql` | Execution Plan (Việc 5) | Trước/sau index `IX_Orders_Customer` trên bảng sao `dbo.OrdersPlan`, chạy bằng sqlcmd |
| `05a`..`05f_lock_demo_*.sql` | UPDLOCK/HOLDLOCK (Việc 6) | Demo hai cửa sổ cho BR-MKT-06 (không bán lố khi hai người đặt mua đồng thời) |

## Việc 5: Execution Plan trước/sau index

Bảng sao `dbo.OrdersPlan` (cột khớp `ord.Orders`, 200.000 dòng, chỉ có PK). Truy vấn bám `ord.sp_GetMyOrders`: lọc `CustomerId` và `IsDeleted`, `ORDER BY CreatedAt DESC, OrderId DESC`, phân trang. Index thử: `(CustomerId, CreatedAt DESC)`, cùng định nghĩa `IX_Orders_Customer`.

| File | Việc |
|---|---|
| `04a_orders_plan_setup.sql` | Dựng bảng, nạp dữ liệu, kiểm tra (chạy lại được) |
| `04b_orders_plan_before.sql` | Đo trước index |
| `04c_orders_plan_after.sql` | Tạo index, đo sau index |
| `04d_orders_plan_cleanup.sql` | Dọn bảng sao (bắt buộc) |
| `04e_orders_plan_showplan.sql` | Xem plan dạng văn bản (`SHOWPLAN_TEXT`) trước/sau, chạy giữa `04a` và `04d` |

Thứ tự: `04a` → `04b` → `04c` → `04d`.

```
sqlcmd -S localhost -E -C -b -f 65001 -i database\10_backup\04a_orders_plan_setup.sql
```

Muốn chụp plan đồ họa: mở `04b` và `04c` trong SSMS, bật Ctrl+M, F5.

Kết quả đã đo (dữ liệu sinh ngẫu nhiên nên số thay đổi nhẹ giữa các lần chạy):

| | Trước index | Sau index |
|---|---|---|
| Logical reads | 4049 | 290 |
| Plan | `Clustered Index Scan` | `Index Seek` + `Key Lookup` (nested loops) |

Ghi nhận: `IsDeleted` không nằm trong index nên còn Key Lookup, và truy vấn phân trang vẫn còn `Sort(TOP 20)`. Hướng tối ưu thêm (chưa áp dụng): `INCLUDE (IsDeleted)`.

## Việc 6: demo UPDLOCK/HOLDLOCK hai cửa sổ

Tin demo `LOCKDEMO-BR-MKT-06` có `Quantity = 2`. Người 1 mua 1, người 2 mua 2, nên tổng nhu cầu (3) vượt kho (2).

| File | Việc |
|---|---|
| `05a_lock_demo_setup.sql` | Tạo tin demo và bảng điều khiển `dbo.LockDemoCtx`. Nếu demo đang dở, dừng với lỗi 51000: chạy `05f` trước |
| `05b_lock_demo_nolock_setup.sql`, `05c_lock_demo_nolock_run.sql` | Đối chứng KHÔNG khóa trên bảng sao `dbo.LockDemoStock` |
| `05d_lock_demo_session1.sql`, `05e_lock_demo_session2.sql` | Có khóa trên thủ tục thật `mkt.sp_PlaceMarketOrder` |
| `05f_lock_demo_cleanup.sql` | Dọn thông báo, giao dịch, tin demo và các bảng demo (chạy lại được) |

Đối chứng không khóa: mở hai cửa sổ cùng lúc để cả hai cùng đọc `Stock = 2`.

```
start "Buyer1" cmd /k sqlcmd -S localhost -E -C -b -f 65001 -i database\10_backup\05c_lock_demo_nolock_run.sql -v Buyer=1 Qty=1 Delay=15 & start "Buyer2" cmd /k sqlcmd -S localhost -E -C -b -f 65001 -i database\10_backup\05c_lock_demo_nolock_run.sql -v Buyer=2 Qty=2 Delay=15
```

Có khóa trên thủ tục thật: cửa sổ 1 giữ khóa 25 giây rồi đặt mua thật, cửa sổ 2 vào sau 3 giây.

```
start "S1" cmd /k sqlcmd -S localhost -E -C -b -f 65001 -i database\10_backup\05d_lock_demo_session1.sql -v Delay=25 & start "S2" cmd /k sqlcmd -S localhost -E -C -b -f 65001 -i database\10_backup\05e_lock_demo_session2.sql -v Pre=3
```

Xem blocking trong lúc hai cửa sổ chạy:

```
sqlcmd -S localhost -E -C -d FilmLabDB -Q "SELECT session_id, blocking_session_id, wait_type, wait_time, command FROM sys.dm_exec_requests WHERE blocking_session_id <> 0"
```

Kết quả đã đo:

| | Không khóa | Có khóa (thủ tục thật) |
|---|---|---|
| Hai bên cùng đọc kho | Có | Không, bên sau bị chặn (`LCK_M_U`, khoảng 22 giây) |
| Kho cuối | `-1`, bán 3 trên 2 | `1`, không âm |
| Người thứ hai | Thành công (sai) | Lỗi `50606` (không đủ số lượng) |

Dọn sau demo (bắt buộc):

```
sqlcmd -S localhost -E -C -b -f 65001 -i database\10_backup\05f_lock_demo_cleanup.sql
```

Ghi chú:
- Demo có khóa chỉ chạy được một lần trên mỗi lần dựng (kho đã giảm sau lần chạy), muốn chạy lại phải dọn rồi dựng lại từ `05a`.
- Các file dùng `SET QUOTED_IDENTIFIER ON` vì `mkt.MarketTransactions` có cột tính toán `PERSISTED`.
- `audit.AuditLogs` là bảng chỉ-thêm (BR-AUD-01) nên file dọn không xóa dòng audit do demo sinh ra.
- Cửa sổ 1 giữ khóa rồi gọi thủ tục thật, vì thủ tục không có `WAITFOR` để giữ khóa từ bên trong.