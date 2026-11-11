(function () {
  'use strict';
  var log = document.getElementById('chat-log');
  var form = document.getElementById('chat-form');
  var input = document.getElementById('chat-input');
  var send = document.getElementById('chat-send');

  function add(text, cls) {
    var d = document.createElement('div');
    d.className = 'chat-msg ' + cls;
    d.textContent = text;
    log.appendChild(d);
    log.scrollTop = log.scrollHeight;
    return d;
  }

  form.addEventListener('submit', function (e) {
    e.preventDefault();
    var text = input.value.trim();
    if (!text) return;
    add(text, 'chat-user');
    input.value = '';
    input.disabled = true;
    send.disabled = true;
    var wait = add('Đang trả lời...', 'chat-bot chat-wait');

    fetch('/chat/send', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'Accept': 'application/json' },
      body: JSON.stringify({ message: text })
    })
      .then(function (r) {
        return r.json().then(function (j) { return { ok: r.ok, status: r.status, body: j }; });
      })
      .then(function (r) {
        if (r.status === 401) { window.location.href = '/login'; return; }
        if (!r.ok) {
          wait.className = 'chat-msg chat-error';
          wait.textContent = r.body.error || 'Có lỗi xảy ra.';
          return;
        }
        wait.className = 'chat-msg chat-bot';
        wait.textContent = r.body.answer;
        if (r.body.sources && r.body.sources.length) {
          var s = document.createElement('div');
          s.className = 'chat-sources';
          s.textContent = 'Nguồn: ' + r.body.sources.join('; ');
          wait.appendChild(s);
        }
      })
      .catch(function () {
        wait.className = 'chat-msg chat-error';
        wait.textContent = 'Không kết nối được máy chủ.';
      })
      .then(function () {
        input.disabled = false;
        send.disabled = false;
        input.focus();
      });
  });
})();