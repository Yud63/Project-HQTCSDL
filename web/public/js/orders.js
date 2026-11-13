/**
 * public/js/orders.js
 * Kịch bản giao diện người dùng cho Phần 3 (FilmLabDB)
 * Chức năng:
 * - Đếm ngược tự động tải lại (Auto-refresh 20s) theo dõi tiến độ đơn hàng
 * - Đánh giá sao tương tác (Star rating)
 * - Xác nhận hủy đơn hàng kèm lý do
 * - Xem nhanh ảnh scan trong Kho lưu trữ
 */

document.addEventListener('DOMContentLoaded', function () {
  // ------------------------------------------------------------
  // 1. TỰ ĐỘNG TẢI LẠI TRANG CHI TIẾT ĐƠN HÀNG (Auto-Refresh 20s)
  // ------------------------------------------------------------
  const timerElement = document.getElementById('autoRefreshCountdown');
  const timerToggleBtn = document.getElementById('autoRefreshToggle');
  const manualRefreshBtn = document.getElementById('manualRefreshBtn');

  if (timerElement) {
    let countdown = 20;
    let isPaused = false;

    const interval = setInterval(function () {
      if (!isPaused) {
        countdown--;
        timerElement.textContent = countdown + 's';
        if (countdown <= 0) {
          clearInterval(interval);
          window.location.reload();
        }
      }
    }, 1000);

    if (timerToggleBtn) {
      timerToggleBtn.addEventListener('click', function () {
        isPaused = !isPaused;
        this.textContent = isPaused ? 'Tiếp tục' : 'Tạm dừng';
        this.classList.toggle('btn-outline');
      });
    }

    if (manualRefreshBtn) {
      manualRefreshBtn.addEventListener('click', function () {
        window.location.reload();
      });
    }
  }

  // ------------------------------------------------------------
  // 2. TƯƠNG TÁC ĐÁNH GIÁ SAO (Star Rating System)
  // ------------------------------------------------------------
  const starContainers = document.querySelectorAll('.star-rating-group');
  const ratingTexts = {
    1: '1 sao - Rất không hài lòng',
    2: '2 sao - Cần cải thiện',
    3: '3 sao - Đạt yêu cầu',
    4: '4 sao - Tốt, hài lòng',
    5: '5 sao - Xuất sắc, vượt mong đợi'
  };

  starContainers.forEach(container => {
    const inputId = container.getAttribute('data-input-id');
    const input = document.getElementById(inputId);
    const hint = container.parentElement.querySelector('.star-rating-hint');
    const stars = container.querySelectorAll('.star-btn');

    if (!input || stars.length === 0) return;

    function highlightStars(val) {
      stars.forEach(s => {
        const sVal = parseInt(s.getAttribute('data-value'), 10);
        if (sVal <= val) {
          s.classList.add('active');
        } else {
          s.classList.remove('active');
        }
      });
    }

    stars.forEach(star => {
      star.addEventListener('mouseenter', function () {
        const hoverVal = parseInt(this.getAttribute('data-value'), 10);
        stars.forEach(s => {
          const sVal = parseInt(s.getAttribute('data-value'), 10);
          if (sVal <= hoverVal) s.classList.add('hover');
          else s.classList.remove('hover');
        });
        if (hint) hint.textContent = ratingTexts[hoverVal] || '';
      });

      star.addEventListener('mouseleave', function () {
        stars.forEach(s => s.classList.remove('hover'));
        const currentVal = parseInt(input.value, 10) || 0;
        highlightStars(currentVal);
        if (hint) hint.textContent = currentVal ? ratingTexts[currentVal] : '';
      });

      star.addEventListener('click', function () {
        const selectedVal = parseInt(this.getAttribute('data-value'), 10);
        input.value = selectedVal;
        highlightStars(selectedVal);
        if (hint) hint.textContent = ratingTexts[selectedVal];
      });
    });

    // Khởi tạo trạng thái ban đầu nếu đã có giá trị
    if (input.value) {
      highlightStars(parseInt(input.value, 10));
    }
  });

  // ------------------------------------------------------------
  // 3. XÁC NHẬN HỦY ĐƠN HÀNG (Cancel Order Prompt)
  // ------------------------------------------------------------
  const cancelForm = document.getElementById('cancelOrderForm');
  if (cancelForm) {
    cancelForm.addEventListener('submit', function (e) {
      const reasonInput = document.getElementById('cancelReasonInput');
      const reason = reasonInput ? reasonInput.value.trim() : '';

      if (!reason) {
        e.preventDefault();
        alert('Vui lòng nhập lý do bạn muốn hủy đơn hàng.');
        if (reasonInput) reasonInput.focus();
        return;
      }

      if (!confirm('Bạn có chắc chắn muốn hủy đơn hàng này không? Sau khi hủy bạn sẽ không thể hoàn tác.')) {
        e.preventDefault();
      }
    });
  }
});
