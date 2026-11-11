'use strict';
const crypto = require('crypto');
const router = require('express').Router();
const { sql } = require('../lib/db');
const { requireRole } = require('../lib/auth');
const { HttpError } = require('../lib/errors');
const gemini = require('../lib/gemini');

const CHAT_ROLES = ['Customer', 'LabOwner', 'Expert'];
const MAX_QUESTION = 400; // giới hạn của ai.sp_SearchKnowledge
const TOP_N = 3;
const NO_DOC = 'Hiện chưa có tài liệu phù hợp với câu hỏi này trong kho kiến thức. Bạn thử diễn đạt lại bằng từ khóa khác nhé.';
const BUSY = 'Trợ lý tạm thời không phản hồi. Vui lòng thử lại sau.';

const int = (v) => ({ type: sql.Int, value: v ?? null });

// UserId luôn lấy từ session (req.callProc), không nhận từ client
function logMessage(req, sessionId, role, message, extra = {}) {
  return req.callProc('ai.sp_LogChatMessage', {
    UserId: req.session.user.id,
    SessionId: { type: sql.UniqueIdentifier, value: sessionId },
    Role: role,
    Message: message,
    ModelName: extra.model ?? null,
    PromptTokens: int(extra.promptTokens),
    CompletionTokens: int(extra.completionTokens),
    LatencyMs: int(extra.latencyMs),
    SourcesJson: extra.sources ?? null,
  }, { NewChatLogId: sql.BigInt });
}

// Mỗi lần mở trang chat là một SessionId mới
router.get('/chat', requireRole(...CHAT_ROLES), (req, res) => {
  req.session.chatSessionId = crypto.randomUUID();
  res.render('chat', { title: 'Trợ lý AI', maxLen: MAX_QUESTION });
});

router.post('/chat/send', requireRole(...CHAT_ROLES), async (req, res) => {
  const question = String((req.body || {}).message || '').trim();
  if (!question) throw new HttpError(400, 'Vui lòng nhập câu hỏi.');
  if (question.length > MAX_QUESTION) throw new HttpError(400, `Câu hỏi tối đa ${MAX_QUESTION} ký tự.`);

  if (!req.session.chatSessionId) req.session.chatSessionId = crypto.randomUUID();
  const sessionId = req.session.chatSessionId;
  const user = req.session.user;

  // Ghi câu hỏi trước, để Gemini lỗi vẫn còn dấu vết
  await logMessage(req, sessionId, 'User', question);

  const found = await req.callProc('ai.sp_SearchKnowledge', {
    UserId: user.id,
    Query: question,
    TopN: { type: sql.TinyInt, value: TOP_N },
    Topic: null,
  });
  const chunks = found.recordset;

  if (chunks.length === 0) {
    await logMessage(req, sessionId, 'Assistant', NO_DOC, { model: 'rule-no-context', sources: [] });
    return res.json({ answer: NO_DOC, sources: [] });
  }

  let result;
  try {
    result = await gemini.answer(question, chunks);
  } catch (e) {
    console.error('[chat] Gemini lỗi:', e.message);
    return res.status(502).json({ error: BUSY });
  }

  const sources = chunks.map((c) => ({ docId: c.KnowledgeDocId, chunk: c.ChunkIndex, title: c.Title, score: c.Score }));
  try {
    await logMessage(req, sessionId, 'Assistant', result.text, {
      model: result.model,
      promptTokens: result.promptTokens,
      completionTokens: result.completionTokens,
      latencyMs: result.latencyMs,
      sources,
    });
  } catch (e) {
    console.error('[chat] Không ghi được log trả lời:', e.message);
  }

  return res.json({ answer: result.text, sources: [...new Set(chunks.map((c) => c.Title))] });
});

module.exports = router;