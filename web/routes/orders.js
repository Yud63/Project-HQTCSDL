/**
 * routes/orders.js
 * Phụ trách bởi: P3 (Khách hàng sau khi đặt đơn)
 * Các URL:
 * - GET  /orders
 * - GET  /orders/:id
 * - POST /orders/:id/cancel
 * - GET  /orders/:id/review
 * - POST /orders/:id/review
 * - GET  /orders/:id/complaint
 * - POST /orders/:id/complaint
 * - GET  /notifications
 * - POST /notifications/:id/read
 * - GET  /archive
 */

const express = require('express');
const router = express.Router();
const { sql, callProc, queryAs } = require('../lib/db');
const directQuery = async (...args) => (await queryAs(...args)).recordset;
const { requireLogin, requireRole } = require('../lib/auth');

// Áp dụng middleware kiểm tra đăng nhập và role Customer cho toàn bộ route P3
router.use(['/orders', '/notifications'], requireLogin, requireRole('Customer'));

// ------------------------------------------------------------
// 1. GET /orders - Danh sách đơn hàng của khách hàng
// ------------------------------------------------------------
router.get('/orders', async (req, res, next) => {
  try {
    const userId = req.session.user.id;
    const stageCode = req.query.stage || null;
    const pageNo = parseInt(req.query.page, 10) || 1;
    const pageSize = 10;

    const result = await callProc('Customer', userId, 'ord.sp_GetMyOrders', {
      UserId: userId,
      AsRole: 'Customer',
      StageCode: stageCode,
      PageNo: pageNo,
      PageSize: pageSize
    });

    const orders = result.recordset || [];
    const totalCount = orders.length > 0 ? orders[0].TotalRows : 0;
    const totalPages = Math.max(1, Math.ceil(totalCount / pageSize));

    res.render('orders/index', {
      title: 'Đơn hàng của tôi',
      user: req.session.user,
      orders,
      currentStage: stageCode,
      currentPage: pageNo,
      totalPages,
      totalCount
    });
  } catch (err) {
    next(err);
  }
});

// ------------------------------------------------------------
// 2. GET /orders/:id - Chi tiết đơn hàng và timeline 13 giai đoạn
// ------------------------------------------------------------
router.get('/orders/:id', async (req, res, next) => {
  try {
    const userId = req.session.user.id;
    const orderId = parseInt(req.params.id, 10);

    if (isNaN(orderId)) {
      req.flash('danger', 'Mã đơn hàng không hợp lệ.');
      return res.redirect('/orders');
    }

    const result = await callProc('Customer', userId, 'ord.sp_GetOrderDetail', {
      OrderId: orderId,
      UserId: userId
    });

    const order = result.recordsets[0] && result.recordsets[0][0];
    if (!order) {
      req.flash('danger', 'Không tìm thấy đơn hàng yêu cầu.');
      return res.redirect('/orders');
    }

    const items = result.recordsets[1] || [];
    const timeline = result.recordsets[2] || [];
    const review = null;
    const complaints = [];
    const scanFiles = [];

    res.render('orders/detail', {
      title: `Chi tiết đơn hàng #${order.OrderCode || order.OrderId}`,
      user: req.session.user,
      order,
      items,
      timeline,
      review,
      complaints,
      scanFiles
    });
  } catch (err) {
    next(err);
  }
});

// ------------------------------------------------------------
// 3. POST /orders/:id/cancel - Hủy đơn hàng
// ------------------------------------------------------------
router.post('/orders/:id/cancel', async (req, res, next) => {
  try {
    const userId = req.session.user.id;
    const orderId = parseInt(req.params.id, 10);
    const reason = (req.body.reason || '').trim();

    if (!reason) {
      req.flash('danger', 'Vui lòng cung cấp lý do hủy đơn hàng.');
      return res.redirect(`/orders/${orderId}`);
    }

    await callProc('Customer', userId, 'ord.sp_CancelOrder', {
      OrderId: orderId,
      ActorUserId: userId,
      Reason: reason
    });

    req.flash('success', 'Đơn hàng đã được hủy thành công.');
    res.redirect(`/orders/${orderId}`);
  } catch (err) {
    req.flash('danger', err.message || 'Không thể hủy đơn hàng do xung đột trạng thái.');
    res.redirect(`/orders/${req.params.id}`);
  }
});

// ------------------------------------------------------------
// 4. GET /orders/:id/review - Trang đánh giá đơn hàng
// ------------------------------------------------------------
router.get('/orders/:id/review', async (req, res, next) => {
  try {
    const userId = req.session.user.id;
    const orderId = parseInt(req.params.id, 10);

    const result = await callProc('Customer', userId, 'ord.sp_GetOrderDetail', {
      OrderId: orderId,
      UserId: userId
    });

    const order = result.recordsets[0] && result.recordsets[0][0];
    if (!order) {
      req.flash('danger', 'Không tìm thấy đơn hàng.');
      return res.redirect('/orders');
    }

    if (order.StageId !== 12) {
      req.flash('danger', 'Chỉ có thể đánh giá phòng Lab khi đơn hàng đã hoàn tất.');
      return res.redirect(`/orders/${orderId}`);
    }

    const hasReview = false;
    if (hasReview) {
      req.flash('danger', 'Bạn đã gửi đánh giá cho đơn hàng này rồi.');
      return res.redirect(`/orders/${orderId}`);
    }

    res.render('orders/review', {
      title: `Đánh giá dịch vụ - Đơn #${order.OrderCode || order.OrderId}`,
      user: req.session.user,
      order
    });
  } catch (err) {
    next(err);
  }
});

// ------------------------------------------------------------
// 5. POST /orders/:id/review - Gửi đánh giá
// ------------------------------------------------------------
router.post('/orders/:id/review', async (req, res, next) => {
  try {
    const userId = req.session.user.id;
    const orderId = parseInt(req.params.id, 10);

    const ratingOverall = parseInt(req.body.ratingOverall, 10);
    const ratingScanQuality = req.body.ratingScanQuality ? parseInt(req.body.ratingScanQuality, 10) : null;
    const ratingSpeed = req.body.ratingSpeed ? parseInt(req.body.ratingSpeed, 10) : null;
    const comment = (req.body.comment || '').trim();

    if (!ratingOverall || ratingOverall < 1 || ratingOverall > 5) {
      req.flash('danger', 'Vui lòng chọn số sao đánh giá tổng thể (1 - 5 sao).');
      return res.redirect(`/orders/${orderId}/review`);
    }

    await callProc('Customer', userId, 'ord.sp_AddReview', {
      OrderId: orderId,
      CustomerId: userId,
      RatingOverall: ratingOverall,
      RatingScanQuality: ratingScanQuality,
      RatingSpeed: ratingSpeed,
      Comment: comment
    }, { NewReviewId: sql.Int });

    req.flash('success', 'Cảm ơn bạn đã gửi đánh giá! Ý kiến của bạn giúp nâng cao chất lượng phòng Lab.');
    res.redirect(`/orders/${orderId}`);
  } catch (err) {
    req.flash('danger', err.message || 'Không thể lưu đánh giá.');
    res.redirect(`/orders/${req.params.id}/review`);
  }
});

// ------------------------------------------------------------
// 6. GET /orders/:id/complaint - Trang khiếu nại đơn hàng
// ------------------------------------------------------------
router.get('/orders/:id/complaint', async (req, res, next) => {
  try {
    const userId = req.session.user.id;
    const orderId = parseInt(req.params.id, 10);

    const result = await callProc('Customer', userId, 'ord.sp_GetOrderDetail', {
      OrderId: orderId,
      UserId: userId
    });

    const order = result.recordsets[0] && result.recordsets[0][0];
    if (!order) {
      req.flash('danger', 'Không tìm thấy đơn hàng.');
      return res.redirect('/orders');
    }

    res.render('orders/complaint', {
      title: `Gửi khiếu nại - Đơn #${order.OrderCode || order.OrderId}`,
      user: req.session.user,
      order
    });
  } catch (err) {
    next(err);
  }
});

// ------------------------------------------------------------
// 7. POST /orders/:id/complaint - Gửi khiếu nại
// ------------------------------------------------------------
router.post('/orders/:id/complaint', async (req, res, next) => {
  try {
    const userId = req.session.user.id;
    const orderId = parseInt(req.params.id, 10);

    const category = (req.body.category || '').trim();
    const title = (req.body.title || '').trim();
    const description = (req.body.description || '').trim();

    if (!category) {
      req.flash('danger', 'Vui lòng chọn danh mục khiếu nại.');
      return res.redirect(`/orders/${orderId}/complaint`);
    }
    if (!title || title.length < 5) {
      req.flash('danger', 'Tiêu đề khiếu nại phải có ít nhất 5 ký tự.');
      return res.redirect(`/orders/${orderId}/complaint`);
    }
    if (!description || description.length < 10) {
      req.flash('danger', 'Nội dung khiếu nại chi tiết phải có ít nhất 10 ký tự.');
      return res.redirect(`/orders/${orderId}/complaint`);
    }

    await callProc('Customer', userId, 'ord.sp_FileComplaint', {
      OrderId: orderId,
      CustomerId: userId,
      Category: category,
      Title: title,
      Description: description
    }, { NewComplaintId: sql.Int });

    req.flash('success', 'Khiếu nại của bạn đã được tiếp nhận. Đội ngũ CSKH và Lab sẽ phản hồi sớm nhất.');
    res.redirect(`/orders/${orderId}`);
  } catch (err) {
    req.flash('danger', err.message || 'Không thể gửi khiếu nại.');
    res.redirect(`/orders/${req.params.id}/complaint`);
  }
});

// ------------------------------------------------------------
// 8. GET /notifications - Hộp thư thông báo của khách hàng
// ------------------------------------------------------------
router.get('/notifications', async (req, res, next) => {
  try {
    const userId = req.session.user.id;
    const filter = req.query.filter || 'all'; // all, unread, read

    // Quyết định D1: Đọc bảng RLS arc.Notifications đã được GRANT SELECT
    const notifications = await directQuery(
      'Customer',
      userId,
      `SELECT NotificationId, UserId, Type, Title, Body, OrderId, IsRead, ReadAt, CreatedAt 
       FROM arc.Notifications 
       WHERE UserId = @UserId 
       ORDER BY CreatedAt DESC`,
      { UserId: userId }
    );

    let filteredNotifs = notifications;
    if (filter === 'unread') {
      filteredNotifs = notifications.filter(n => !n.IsRead);
    } else if (filter === 'read') {
      filteredNotifs = notifications.filter(n => n.IsRead);
    }

    const unreadCount = notifications.filter(n => !n.IsRead).length;

    res.render('notifications/index', {
      title: 'Hộp thư thông báo',
      user: req.session.user,
      notifications: filteredNotifs,
      filter,
      unreadCount,
      totalCount: notifications.length
    });
  } catch (err) {
    next(err);
  }
});

// ------------------------------------------------------------
// 9. POST /notifications/:id/read - Đánh dấu thông báo đã đọc
// ------------------------------------------------------------
router.post('/notifications/:id/read', async (req, res, next) => {
  try {
    const userId = req.session.user.id;
    const notifId = parseInt(req.params.id, 10);

    await callProc('Customer', userId, 'arc.sp_MarkNotificationRead', {
      NotificationId: notifId,
      UserId: userId
    });

    res.redirect('/notifications');
  } catch (err) {
    next(err);
  }
});

module.exports = router;
