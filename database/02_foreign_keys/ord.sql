/* ============================================================
   File    : database/02_foreign_keys/ord.sql
   Module  : ord - M3 Order, Processing, Payment, Fee
   Purpose : FK LIÊN MODULE (9): FK_Orders_Users, FK_Orders_FilmLabs, FK_Orders_Addresses_PickupAddressId, FK_Orders_Addresses_ReturnAddressId, FK_OrderItems_LabServices, FK_OrderItems_FilmStocks, FK_OrderStageLog_Users, FK_FeeConfigs_FilmLabs, FK_FeeConfigs_Users.
   Owner   : B (xem docs/Phan-cong.md)
   Depends : iam, lab
   Re-run  : Chạy lại bằng REBUILD=1 (DB tạo mới). Không DROP TABLE thủ công.
   Ref     : docs/Conventions.md, docs/Contracts.md, docs/DataDictionary.xlsx
   ============================================================ */
USE FilmLabDB;
GO

SET QUOTED_IDENTIFIER ON;  -- bắt buộc cho filtered index, spatial index, computed column
SET ANSI_NULLS ON;
GO

ALTER TABLE ord.FeeConfigs WITH CHECK
    ADD CONSTRAINT FK_FeeConfigs_FilmLabs FOREIGN KEY (ScopeLabId) REFERENCES lab.FilmLabs(LabId);
GO

ALTER TABLE ord.FeeConfigs WITH CHECK
    ADD CONSTRAINT FK_FeeConfigs_Users FOREIGN KEY (CreatedBy) REFERENCES iam.Users(UserId);
GO

ALTER TABLE ord.Orders WITH CHECK
    ADD CONSTRAINT FK_Orders_Users FOREIGN KEY (CustomerId) REFERENCES iam.Users(UserId);
GO

ALTER TABLE ord.Orders WITH CHECK
    ADD CONSTRAINT FK_Orders_FilmLabs FOREIGN KEY (LabId) REFERENCES lab.FilmLabs(LabId);
GO

ALTER TABLE ord.Orders WITH CHECK
    ADD CONSTRAINT FK_Orders_Addresses_PickupAddressId FOREIGN KEY (PickupAddressId) REFERENCES iam.Addresses(AddressId);
GO

ALTER TABLE ord.Orders WITH CHECK
    ADD CONSTRAINT FK_Orders_Addresses_ReturnAddressId FOREIGN KEY (ReturnAddressId) REFERENCES iam.Addresses(AddressId);
GO

ALTER TABLE ord.OrderItems WITH CHECK
    ADD CONSTRAINT FK_OrderItems_LabServices FOREIGN KEY (LabServiceId) REFERENCES lab.LabServices(LabServiceId);
GO

ALTER TABLE ord.OrderItems WITH CHECK
    ADD CONSTRAINT FK_OrderItems_FilmStocks FOREIGN KEY (FilmStockId) REFERENCES lab.FilmStocks(StockId);
GO

ALTER TABLE ord.OrderStageLog WITH CHECK
    ADD CONSTRAINT FK_OrderStageLog_Users FOREIGN KEY (ChangedBy) REFERENCES iam.Users(UserId);
GO
