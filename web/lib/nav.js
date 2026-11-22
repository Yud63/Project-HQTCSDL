'use strict';

// Menu theo role. P1 sở hữu file này; cần thêm trang mới thì báo P1.
// group + desc dùng cho trang chủ (home.ejs); header chỉ đọc label + href.
const MENUS = {
  Customer: [
    { group: 'Film Lab', label: 'Tìm lab', href: '/labs', desc: 'Tìm và so sánh lab theo giá, thời gian, đánh giá' },
    { group: 'Film Lab', label: 'Gợi ý', href: '/recommend', desc: 'Lab phù hợp với sở thích của bạn' },
    { group: 'Film Lab', label: 'Đơn của tôi', href: '/orders', desc: 'Theo dõi đơn đang ở bước nào' },
    { group: 'Film Lab', label: 'Thông báo', href: '/notifications', desc: 'Cập nhật mới về đơn của bạn' },
    { group: 'Ảnh của tôi', label: 'Kho ảnh', href: '/archive', desc: 'Ảnh scan theo đơn và theo album' },
    { group: 'Cộng đồng', label: 'Chợ', href: '/market', desc: 'Mua, bán đồ nhiếp ảnh phim' },
    { group: 'Cộng đồng', label: 'Sự kiện', href: '/events', desc: 'Workshop và photowalk' },
    { group: 'Trợ lý', label: 'Trợ lý AI', href: '/chat', desc: 'Hỏi về film, tra đơn, gợi ý lab' },
  ],
  LabOwner: [
    { group: 'Quản lý lab', label: 'Lab của tôi', href: '/owner/labs', desc: 'Hồ sơ lab và gói dịch vụ' },
    { group: 'Quản lý lab', label: 'Đơn hàng', href: '/owner/orders', desc: 'Nhận đơn, cập nhật bước xử lý, tải scan' },
    { group: 'Khách hàng', label: 'Đánh giá', href: '/owner/reviews', desc: 'Xem và trả lời đánh giá' },
    { group: 'Khách hàng', label: 'Doanh thu', href: '/owner/revenue', desc: 'Thống kê doanh thu' },
    { group: 'Trợ lý', label: 'Trợ lý AI', href: '/chat', desc: 'Hỏi về film và quy trình' },
  ],
  Expert: [
    { group: 'Trợ lý', label: 'Trợ lý AI', href: '/chat', desc: 'Hỏi đáp dựa trên kho tri thức' },
  ],
  Delivery: [
    { group: 'Giao nhận', label: 'Giao nhận', href: '/delivery', desc: 'Yêu cầu lấy và trả cuộn film' },
  ],
  Admin: [
    { group: 'Quản trị', label: 'Tổng quan', href: '/admin', desc: 'Số liệu chung của hệ thống' },
    { group: 'Quản trị', label: 'Lab', href: '/admin/labs', desc: 'Duyệt lab mới' },
    { group: 'Quản trị', label: 'Người dùng', href: '/admin/users', desc: 'Quản lý tài khoản' },
    { group: 'Quản trị', label: 'Khiếu nại', href: '/admin/complaints', desc: 'Xử lý khiếu nại' },
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