/* ============================================================
   File    : database/02_foreign_keys/dlv.sql
   Module  : dlv - M4 Delivery
   Purpose : FK LIÊN MODULE (4): FK_DeliveryRequests_Orders, FK_DeliveryRequests_Addresses, FK_DeliveryRequests_DeliveryPartners, FK_DeliveryStatusLog_Users.
   Owner   : A (xem docs/Phan-cong.md)
   Depends : iam, ord
   Re-run  : Chạy lại bằng REBUILD=1 (DB tạo mới). Không DROP TABLE thủ công.
   Ref     : docs/Conventions.md, docs/Contracts.md, docs/DataDictionary.xlsx
   ============================================================ */
USE FilmLabDB;
GO

SET QUOTED_IDENTIFIER ON;  -- bắt buộc cho filtered index, spatial index, computed column
SET ANSI_NULLS ON;
GO

ALTER TABLE dlv.DeliveryRequests WITH CHECK
    ADD CONSTRAINT FK_DeliveryRequests_Orders FOREIGN KEY (OrderId) REFERENCES ord.Orders(OrderId);
GO

ALTER TABLE dlv.DeliveryRequests WITH CHECK
    ADD CONSTRAINT FK_DeliveryRequests_Addresses FOREIGN KEY (CustomerAddressId) REFERENCES iam.Addresses(AddressId);
GO

ALTER TABLE dlv.DeliveryRequests WITH CHECK
    ADD CONSTRAINT FK_DeliveryRequests_DeliveryPartners FOREIGN KEY (DeliveryPartnerId) REFERENCES iam.DeliveryPartners(DeliveryPartnerId);
GO

ALTER TABLE dlv.DeliveryStatusLog WITH CHECK
    ADD CONSTRAINT FK_DeliveryStatusLog_Users FOREIGN KEY (ChangedBy) REFERENCES iam.Users(UserId);
GO
