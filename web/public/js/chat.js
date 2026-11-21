(function () {
  'use strict';
  var log = document.getElementById('chat-log');
  var form = document.getElementById('chat-form');
  var input = document.getElementById('chat-input');
  var send = document.getElementById('chat-send');
  var menuBox = document.getElementById('chat-menu');
  var groups = [];
  try { groups = JSON.parse(menuBox.getAttribute('data-menu') || '[]'); } catch (e) { groups = []; }

  function btn(label, onClick) {
    var b = document.createElement('button');
    b.type = 'button';
    b.className = 'btn chat-chip';
    b.textContent = label;
    b.addEventListener('click', onClick);
    return b;
  }

  function showRoot() {
    menuBox.textContent = '';
    menuBox.appendChild(btn('Tra đơn của tôi', function () { ask('Đơn của tôi đến đâu rồi?'); }));
    menuBox.appendChild(btn('Gợi ý lab', function () { ask('Gợi ý lab tốt nhất cho tôi'); }));
    groups.forEach(function (g) {
      menuBox.appendChild(btn(g.topic, function () { showGroup(g); }));
    });
  }

  function showGroup(g) {
    menuBox.textContent = '';
    g.items.forEach(function (t) {
      menuBox.appendChild(btn(t, function () { ask(t); }));
    });
    menuBox.appendChild(btn('← Quay lại', showRoot));
  }

  function ask(text) {
    input.value = text;
    form.requestSubmit();
  }

  function add(text, cls) {
    var d = document.createElement('div');
    d.className = 'chat-msg ' + cls;
    d.textContent = text;
    log.appendChild(d);
    log.scrollTop = log.scrollHeight;
    return d;
  }

  showRoot();
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
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'x-csrf-token': (document.querySelector('meta[name="csrf-token"]') || {}).content || ''
      },
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
        showRoot();
      });
  });
})();