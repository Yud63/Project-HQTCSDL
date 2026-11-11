'use strict';

// Menu theo role. P1 sở hữu file này; cần thêm trang mới thì báo P1.
const MENUS = {
  Customer: [
    { label: 'Tìm lab', href: '/labs' },
    { label: 'Đơn của tôi', href: '/orders' },
    { label: 'Thông báo', href: '/notifications' },
    { label: 'Kho ảnh', href: '/archive' },
    { label: 'Gợi ý', href: '/recommend' },
    { label: 'Chợ', href: '/market' },
    { label: 'Sự kiện', href: '/events' },
    { label: 'Trợ lý AI', href: '/chat' },
  ],
  LabOwner: [
    { label: 'Lab của tôi', href: '/owner/labs' },
    { label: 'Đơn hàng', href: '/owner/orders' },
    { label: 'Đánh giá', href: '/owner/reviews' },
    { label: 'Doanh thu', href: '/owner/revenue' },
    { label: 'Trợ lý AI', href: '/chat' },
  ],
  Expert: [{ label: 'Trợ lý AI', href: '/chat' }],
  Delivery: [{ label: 'Giao nhận', href: '/delivery' }],
  Admin: [
    { label: 'Tổng quan', href: '/admin' },
    { label: 'Lab', href: '/admin/labs' },
    { label: 'Người dùng', href: '/admin/users' },
    { label: 'Khiếu nại', href: '/admin/complaints' },
  ],
};

// Trang đích của "/" theo role. Đặt URL khi trang đã chạy (null = hiện trang chào).
const HOMES = {
  Customer: null,
  LabOwner: null,
  Expert: null,
  Delivery: null,
  Admin: null,
};

const menuFor = (role) => MENUS[role] || [];
const homeFor = (role) => HOMES[role] || null;

module.exports = { menuFor, homeFor };