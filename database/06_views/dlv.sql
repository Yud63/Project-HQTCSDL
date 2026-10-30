/* ============================================================
   File    : database/06_views/dlv.sql
   Module  : dlv - M4 Delivery
   Purpose : View: vw_DeliveryBoard.
   Owner   : A (xem docs/Phan-cong.md)
   Depends : iam, ord
   Re-run  : CREATE OR ALTER - chạy lại bao nhiêu lần cũng được.
   Ref     : docs/Conventions.md, docs/Contracts.md, docs/DataDictionary.xlsx
   ============================================================ */
USE FilmLabDB;
GO

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

CREATE OR ALTER VIEW dlv.vw_DeliveryBoard
AS
SELECT dr.DeliveryRequestId,
       dr.OrderId,
       o.OrderCode,
       dr.Direction,
       dr.Status,
       dr.DeliveryPartnerId,
       dp.PartnerName,
       l.LabName,
       l.AddressLine AS LabAddress,
       a.RecipientName,
       a.Phone       AS RecipientPhone,
       a.Line1, a.Ward, a.District, a.City,
       dr.Fee,
       dr.DistanceKm,
       dr.ScheduledAt,
       dr.CreatedAt
FROM dlv.DeliveryRequests dr
JOIN ord.Orders o ON o.OrderId = dr.OrderId AND o.IsDeleted = 0
JOIN lab.FilmLabs l ON l.LabId = o.LabId
JOIN iam.Addresses a ON a.AddressId = dr.CustomerAddressId
LEFT JOIN iam.DeliveryPartners dp ON dp.DeliveryPartnerId = dr.DeliveryPartnerId
WHERE dr.IsDeleted = 0 AND dr.Status IN (N'Requested', N'Assigned', N'PickedUp');
GO
