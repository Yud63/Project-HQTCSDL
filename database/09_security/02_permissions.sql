/* ============================================================
   File    : database/09_security/02_permissions.sql
   Module  : security - GRANT / DENY
   Purpose : GRANT EXECUTE trên procedure, SELECT trên view cho từng role; DENY ghi trực tiếp vào bảng. Làm SAU KHI các module chạy ổn.
   Owner   : TBD (chưa chia việc)
   Depends : Tất cả module đã xong
   Re-run  : Chạy lại được (GRANT/DENY idempotent).
   Ref     : docs/Conventions.md, docs/Contracts.md
   ============================================================ */
USE FilmLabDB;
GO

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- ===== 1. GRANT EXECUTE: role_Customer =====
GRANT EXECUTE ON ord.sp_CreateOrder              TO role_Customer;
GRANT EXECUTE ON ord.sp_CancelOrder              TO role_Customer;
GRANT EXECUTE ON ord.sp_ProcessPayment           TO role_Customer;
GRANT EXECUTE ON ord.sp_AddReview                TO role_Customer;
GRANT EXECUTE ON ord.sp_FileComplaint            TO role_Customer;
GRANT EXECUTE ON lab.sp_SearchLabs               TO role_Customer;
GRANT EXECUTE ON arc.sp_MarkNotificationRead     TO role_Customer;
GRANT EXECUTE ON mkt.sp_CreateListing            TO role_Customer;
GRANT EXECUTE ON mkt.sp_PlaceMarketOrder         TO role_Customer;
GRANT EXECUTE ON mkt.sp_SearchListings           TO role_Customer;
GRANT EXECUTE ON mkt.sp_UpdateMarketTransaction  TO role_Customer;
GRANT EXECUTE ON mkt.sp_RateSeller               TO role_Customer;
GRANT EXECUTE ON mkt.sp_SendMessage              TO role_Customer;
GRANT EXECUTE ON com.sp_PublishArticle           TO role_Customer;
GRANT EXECUTE ON com.sp_AddComment               TO role_Customer;
GRANT EXECUTE ON com.sp_AcceptAnswer             TO role_Customer;
GRANT EXECUTE ON com.sp_RegisterEvent            TO role_Customer;
GRANT EXECUTE ON com.sp_CancelEventRegistration  TO role_Customer;
GRANT EXECUTE ON ai.sp_GetLabRecommendations     TO role_Customer;
GRANT EXECUTE ON ai.sp_SaveUserPreferences       TO role_Customer;
GRANT EXECUTE ON ai.sp_LogChatMessage            TO role_Customer;
GRANT EXECUTE ON ai.sp_RecordRecommendationAction TO role_Customer;
GRANT EXECUTE ON iam.sp_SaveAddress              TO role_Customer;
GRANT EXECUTE ON arc.sp_SaveAlbum                TO role_Customer;
GRANT EXECUTE ON arc.sp_SetAlbumPhoto            TO role_Customer;

-- ===== 2. GRANT EXECUTE: role_LabOwner =====
GRANT EXECUTE ON lab.sp_SearchLabs               TO role_LabOwner;
GRANT EXECUTE ON ord.sp_UpdateOrderStage         TO role_LabOwner;
GRANT EXECUTE ON ord.sp_ReplyReview              TO role_LabOwner;
GRANT EXECUTE ON arc.sp_UploadScan               TO role_LabOwner;
GRANT EXECUTE ON arc.sp_MarkNotificationRead     TO role_LabOwner;
GRANT EXECUTE ON mkt.sp_SearchListings           TO role_LabOwner;
GRANT EXECUTE ON com.sp_AddComment               TO role_LabOwner;
GRANT EXECUTE ON com.sp_RegisterEvent            TO role_LabOwner;
GRANT EXECUTE ON com.sp_CancelEventRegistration  TO role_LabOwner;
GRANT EXECUTE ON ai.sp_LogChatMessage            TO role_LabOwner;
GRANT EXECUTE ON lab.sp_SaveLabProfile           TO role_LabOwner;
GRANT EXECUTE ON lab.sp_SaveLabService           TO role_LabOwner;
GRANT EXECUTE ON com.sp_SaveEvent                TO role_LabOwner;

-- ===== 3. GRANT EXECUTE: role_Expert =====
GRANT EXECUTE ON lab.sp_SearchLabs               TO role_Expert;
GRANT EXECUTE ON arc.sp_MarkNotificationRead     TO role_Expert;
GRANT EXECUTE ON mkt.sp_SearchListings           TO role_Expert;
GRANT EXECUTE ON com.sp_PublishArticle           TO role_Expert;
GRANT EXECUTE ON com.sp_AddComment               TO role_Expert;
GRANT EXECUTE ON com.sp_AcceptAnswer             TO role_Expert;
GRANT EXECUTE ON com.sp_RegisterEvent            TO role_Expert;
GRANT EXECUTE ON com.sp_CancelEventRegistration  TO role_Expert;
GRANT EXECUTE ON ai.sp_LogChatMessage            TO role_Expert;
GRANT EXECUTE ON com.sp_SaveEvent                TO role_Expert;

-- ===== 4. GRANT EXECUTE: role_Delivery =====
GRANT EXECUTE ON dlv.sp_UpdateDeliveryStatus     TO role_Delivery;
GRANT EXECUTE ON arc.sp_MarkNotificationRead     TO role_Delivery;

-- ===== 5. GRANT EXECUTE: role_Admin (cả schema, trừ audit) =====
GRANT EXECUTE ON SCHEMA::iam TO role_Admin;
GRANT EXECUTE ON SCHEMA::lab TO role_Admin;
GRANT EXECUTE ON SCHEMA::ord TO role_Admin;
GRANT EXECUTE ON SCHEMA::dlv TO role_Admin;
GRANT EXECUTE ON SCHEMA::arc TO role_Admin;
GRANT EXECUTE ON SCHEMA::mkt TO role_Admin;
GRANT EXECUTE ON SCHEMA::com TO role_Admin;
GRANT EXECUTE ON SCHEMA::ai  TO role_Admin;

-- ===== 6. DENY EXECUTE procedure nội bộ (chỉ được gọi qua procedure/trigger khác nhờ ownership chaining) =====
DENY EXECUTE ON audit.sp_WriteAudit        TO role_Customer, role_LabOwner, role_Expert, role_Delivery, role_Admin; -- BR-AUD-02
DENY EXECUTE ON arc.sp_CreateNotification  TO role_Customer, role_LabOwner, role_Expert, role_Delivery, role_Admin;
DENY EXECUTE ON lab.sp_RecalcLabRating     TO role_Customer, role_LabOwner, role_Expert, role_Delivery, role_Admin; -- BR-LAB-06
DENY EXECUTE ON dlv.sp_RequestDelivery     TO role_Customer, role_LabOwner, role_Expert, role_Delivery, role_Admin;

-- ===== 7. GRANT SELECT view =====
-- Customer
GRANT SELECT ON lab.vw_TopLabs          TO role_Customer;
GRANT SELECT ON arc.vw_CustomerArchive  TO role_Customer;
GRANT SELECT ON mkt.vw_MarketActive     TO role_Customer;
GRANT SELECT ON mkt.vw_SellerStats      TO role_Customer;
GRANT SELECT ON ord.vw_LabReviews       TO role_Customer;
GRANT SELECT ON com.vw_UpcomingEvents   TO role_Customer;
-- LabOwner
GRANT SELECT ON lab.vw_TopLabs          TO role_LabOwner;
GRANT SELECT ON ord.vw_LabRevenue       TO role_LabOwner;
GRANT SELECT ON ord.vw_OrdersInProgress TO role_LabOwner;
GRANT SELECT ON ord.vw_LabReviews       TO role_LabOwner;
GRANT SELECT ON mkt.vw_MarketActive     TO role_LabOwner;
GRANT SELECT ON com.vw_UpcomingEvents   TO role_LabOwner;
-- Expert
GRANT SELECT ON lab.vw_TopLabs              TO role_Expert;
GRANT SELECT ON mkt.vw_MarketActive         TO role_Expert;
GRANT SELECT ON com.vw_ExpertContributions  TO role_Expert;
GRANT SELECT ON com.vw_UpcomingEvents       TO role_Expert;
-- Delivery
GRANT SELECT ON dlv.vw_DeliveryBoard    TO role_Delivery;
-- Admin (đủ 14 view)
GRANT SELECT ON lab.vw_TopLabs                  TO role_Admin;
GRANT SELECT ON ord.vw_LabRevenue               TO role_Admin;
GRANT SELECT ON ord.vw_OrdersInProgress         TO role_Admin;
GRANT SELECT ON ord.vw_LabReviews               TO role_Admin;
GRANT SELECT ON ord.vw_OpenComplaints           TO role_Admin;
GRANT SELECT ON dlv.vw_DeliveryBoard            TO role_Admin;
GRANT SELECT ON arc.vw_CustomerArchive          TO role_Admin;
GRANT SELECT ON mkt.vw_MarketActive             TO role_Admin;
GRANT SELECT ON mkt.vw_SellerStats              TO role_Admin;
GRANT SELECT ON com.vw_ExpertContributions      TO role_Admin;
GRANT SELECT ON com.vw_UpcomingEvents           TO role_Admin;
GRANT SELECT ON ai.vw_RecommendationMetrics     TO role_Admin;
GRANT SELECT ON audit.vw_RecentChanges          TO role_Admin;
GRANT SELECT ON audit.vw_AdminDashboard         TO role_Admin;

-- ===== 8. GRANT SELECT bảng sẽ có RLS ở Nhóm 11 =====
GRANT SELECT ON ord.Orders              TO role_Customer, role_LabOwner, role_Admin;
GRANT SELECT ON arc.ScanFiles           TO role_Customer, role_LabOwner, role_Admin;
GRANT SELECT ON arc.Albums              TO role_Customer, role_Admin;
GRANT SELECT ON dlv.DeliveryRequests    TO role_Delivery, role_Admin;
GRANT SELECT ON mkt.MarketTransactions  TO role_Customer, role_Admin;
GRANT SELECT ON mkt.Messages            TO role_Customer, role_Admin;
GRANT SELECT ON arc.Notifications       TO role_Customer, role_LabOwner, role_Expert, role_Delivery, role_Admin;
GRANT SELECT ON ai.UserPreferences      TO role_Customer, role_LabOwner, role_Expert, role_Admin;
GRANT SELECT ON ai.AIChatLogs           TO role_Customer, role_LabOwner, role_Expert, role_Admin;
GRANT SELECT ON ai.RecommendationLogs   TO role_Customer, role_Admin;

-- ===== 9. DENY DELETE bảng không xóa cứng =====
DENY DELETE ON iam.Users             TO role_Customer, role_LabOwner, role_Expert, role_Delivery, role_Admin; -- BR-IAM-07
DENY DELETE ON ord.Orders            TO role_Customer, role_LabOwner, role_Expert, role_Delivery, role_Admin; -- BR-ORD-13
DENY DELETE ON ord.OrderItems        TO role_Customer, role_LabOwner, role_Expert, role_Delivery, role_Admin;
DENY DELETE ON ord.Payments          TO role_Customer, role_LabOwner, role_Expert, role_Delivery, role_Admin;
DENY DELETE ON arc.ScanFiles         TO role_Customer, role_LabOwner, role_Expert, role_Delivery, role_Admin; -- BR-ARC-10
DENY DELETE ON ord.Complaints        TO role_Customer, role_LabOwner, role_Expert, role_Delivery, role_Admin; -- BR-CMP-08
DENY DELETE ON mkt.Listings          TO role_Customer, role_LabOwner, role_Expert, role_Delivery, role_Admin; -- BR-MKT-14
DENY DELETE ON mkt.MarketTransactions TO role_Customer, role_LabOwner, role_Expert, role_Delivery, role_Admin;
DENY DELETE ON mkt.Messages          TO role_Customer, role_LabOwner, role_Expert, role_Delivery, role_Admin;
DENY DELETE ON com.Articles          TO role_Customer, role_LabOwner, role_Expert, role_Delivery, role_Admin; -- BR-COM-11
DENY DELETE ON com.ArticleComments   TO role_Customer, role_LabOwner, role_Expert, role_Delivery, role_Admin;
DENY DELETE ON com.Events            TO role_Customer, role_LabOwner, role_Expert, role_Delivery, role_Admin;
DENY DELETE ON ai.AIChatLogs         TO role_Customer, role_LabOwner, role_Expert, role_Delivery, role_Admin; -- BR-AI-04 (chỉ sp_PurgeOldLogs)

-- ===== 10. Nhật ký và log bất biến =====
DENY UPDATE, DELETE ON audit.AuditLogs    TO role_Customer, role_LabOwner, role_Expert, role_Delivery, role_Admin; -- BR-AUD-01
DENY UPDATE, DELETE ON ord.OrderStageLog  TO role_Customer, role_LabOwner, role_Expert, role_Delivery, role_Admin; -- BR-ORD-13
DENY INSERT         ON audit.AuditLogs    TO role_Customer, role_LabOwner, role_Expert, role_Delivery, role_Admin; -- BR-AUD-02
GRANT SELECT        ON audit.AuditLogs    TO role_Admin;                                                           -- BR-AUD-05
DENY  SELECT        ON audit.AuditLogs    TO role_Customer, role_LabOwner, role_Expert, role_Delivery;

-- ===== 11. DENY UPDATE cột AvgRating, ReviewCount (BR-LAB-06) =====
DENY UPDATE (AvgRating, ReviewCount) ON lab.FilmLabs
    TO role_Customer, role_LabOwner, role_Expert, role_Delivery, role_Admin;

-- ===== 12. AIChatLogs: chỉ cột Feedback được UPDATE (BR-AI-02) =====
DECLARE @cols NVARCHAR(MAX) =
    STUFF((SELECT N', ' + QUOTENAME(c.name)
           FROM sys.columns c
           WHERE c.object_id = OBJECT_ID(N'ai.AIChatLogs') AND c.name <> N'Feedback'
           ORDER BY c.column_id
           FOR XML PATH(N''), TYPE).value(N'.', N'NVARCHAR(MAX)'), 1, 2, N'');
DECLARE @sql NVARCHAR(MAX) =
    N'DENY UPDATE (' + @cols + N') ON ai.AIChatLogs TO role_Customer, role_LabOwner, role_Expert, role_Delivery, role_Admin;';
EXEC (@sql);
GRANT UPDATE (Feedback) ON ai.AIChatLogs TO role_Customer, role_LabOwner, role_Expert;
GO

-- ===== 8. Đợt 8a: đăng nhập, đăng ký và đường đọc cho web =====
GRANT EXECUTE ON iam.sp_RegisterUser    TO role_Auth;
GRANT EXECUTE ON iam.sp_GetLoginInfo    TO role_Auth;
GRANT EXECUTE ON iam.sp_GetMyAddresses  TO role_Customer;
GRANT EXECUTE ON ord.sp_GetMyOrders     TO role_Customer, role_LabOwner;
GRANT EXECUTE ON ord.sp_GetOrderDetail  TO role_Customer, role_LabOwner;
GRANT EXECUTE ON lab.sp_GetLabDetail    TO role_Customer, role_LabOwner, role_Expert;
GRANT EXECUTE ON lab.sp_GetMyLabs       TO role_LabOwner;