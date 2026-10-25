/* ============================================================
   File    : database/02_foreign_keys/arc.sql
   Module  : arc - M5 Digital Archive
   Purpose : FK LIÊN MODULE (8): FK_ScanFiles_Orders, FK_ScanFiles_OrderItems, FK_ScanFiles_Users_OwnerUserId, FK_ScanFiles_Users_UploadedBy, FK_PhotoMetadata_FilmStocks, FK_Albums_Users, FK_Notifications_Users, FK_Notifications_Orders.
   Owner   : C (xem docs/Phan-cong.md)
   Depends : iam, lab, ord
   Re-run  : Chạy lại bằng REBUILD=1 (DB tạo mới). Không DROP TABLE thủ công.
   Ref     : docs/Conventions.md, docs/Contracts.md, docs/DataDictionary.xlsx
   ============================================================ */
USE FilmLabDB;
GO

SET QUOTED_IDENTIFIER ON;  -- bắt buộc cho filtered index, spatial index, computed column
SET ANSI_NULLS ON;
GO

ALTER TABLE arc.ScanFiles WITH CHECK
    ADD CONSTRAINT FK_ScanFiles_Orders FOREIGN KEY (OrderId) REFERENCES ord.Orders(OrderId);
GO

ALTER TABLE arc.ScanFiles WITH CHECK
    ADD CONSTRAINT FK_ScanFiles_OrderItems FOREIGN KEY (OrderItemId) REFERENCES ord.OrderItems(OrderItemId);
GO

ALTER TABLE arc.ScanFiles WITH CHECK
    ADD CONSTRAINT FK_ScanFiles_Users_OwnerUserId FOREIGN KEY (OwnerUserId) REFERENCES iam.Users(UserId);
GO

ALTER TABLE arc.ScanFiles WITH CHECK
    ADD CONSTRAINT FK_ScanFiles_Users_UploadedBy FOREIGN KEY (UploadedBy) REFERENCES iam.Users(UserId);
GO

ALTER TABLE arc.Notifications WITH CHECK
    ADD CONSTRAINT FK_Notifications_Users FOREIGN KEY (UserId) REFERENCES iam.Users(UserId);
GO

ALTER TABLE arc.Notifications WITH CHECK
    ADD CONSTRAINT FK_Notifications_Orders FOREIGN KEY (OrderId) REFERENCES ord.Orders(OrderId);
GO

ALTER TABLE arc.PhotoMetadata WITH CHECK
    ADD CONSTRAINT FK_PhotoMetadata_FilmStocks FOREIGN KEY (FilmStockId) REFERENCES lab.FilmStocks(StockId);
GO

ALTER TABLE arc.Albums WITH CHECK
    ADD CONSTRAINT FK_Albums_Users FOREIGN KEY (OwnerUserId) REFERENCES iam.Users(UserId);
GO
