'use strict';
// Thay cho handler inline (onclick/onsubmit) để CSP không cần 'unsafe-inline' cho thuộc tính.
document.addEventListener('click', function (e) {
  var t = e.target.closest('[data-confirm], [data-show], [data-hide]');
  if (!t) return;

  // Nút có data-confirm (kiểu button/submit): hỏi, bấm Hủy thì chặn submit
  if (t.hasAttribute('data-confirm') && t.tagName === 'BUTTON' && !confirm(t.getAttribute('data-confirm'))) {
    e.preventDefault();
    return;
  }
  if (t.hasAttribute('data-show')) {
    var s = document.getElementById(t.getAttribute('data-show'));
    if (s) s.style.display = 'block';
    if (t.hasAttribute('data-hide-self')) t.style.display = 'none';
  }
  if (t.hasAttribute('data-hide')) {
    var h = document.getElementById(t.getAttribute('data-hide'));
    if (h) h.style.display = 'none';
  }
});

// Form có data-confirm: hỏi trước khi gửi
document.addEventListener('submit', function (e) {
  var f = e.target;
  if (f.tagName === 'FORM' && f.hasAttribute('data-confirm') && !confirm(f.getAttribute('data-confirm'))) {
    e.preventDefault();
  }
  if (f.tagName === 'FORM' && f.hasAttribute('data-no-submit')) e.preventDefault();
});