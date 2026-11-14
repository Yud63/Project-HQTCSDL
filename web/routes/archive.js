'use strict';
const express = require('express');
const router = express.Router();
const { queryAs } = require('../lib/db');
const { requireLogin, requireRole } = require('../lib/auth');

router.use('/archive', requireLogin, requireRole('Customer'));

// Lỗi nghiệp vụ của sp_GetMyAlbums / sp_GetAlbumPhotos
const BUSINESS_ERRORS = [50501, 50503, 50505];
const errNumber = (e) => e && (e.number ?? (e.originalError && e.originalError.number));

function handleBusinessError(req, res, e, next) {
  if (BUSINESS_ERRORS.includes(errNumber(e))) {
    req.flash('danger', e.message);
    return res.redirect('/archive/albums');
  }
  return next(e);
}

// GET /archive - lưới ảnh scan của tôi
router.get('/archive', async (req, res, next) => {
  try {
    const u = req.session.user;
    const photos = (await queryAs(u.role, u.id,
      `SELECT ScanFileId, OrderId, OrderCode, LabName, FrameNumber, FileName, StorageUrl,
              WidthPx, HeightPx, QualityStatus, UploadedAt, FilmBrand, FilmStockName,
              CameraModel, ShootingDate, ExposedIso, AlbumCount
       FROM arc.vw_CustomerArchive
       WHERE OwnerUserId = @UserId
       ORDER BY UploadedAt DESC, OrderId, FrameNumber`,
      { UserId: u.id })).recordset;
    res.render('archive/index', { title: 'Kho ảnh', photos });
  } catch (e) {
    next(e);
  }
});

// GET /archive/albums - danh sách album của tôi
router.get('/archive/albums', async (req, res, next) => {
  try {
    const albums = (await req.callProc('arc.sp_GetMyAlbums', { UserId: req.session.user.id })).recordset;
    res.render('archive/albums', { title: 'Album của tôi', albums });
  } catch (e) {
    next(e);
  }
});

// GET /archive/albums/:id - ảnh trong một album
router.get('/archive/albums/:id', async (req, res, next) => {
  try {
    const id = parseInt(req.params.id, 10);
    if (!Number.isInteger(id) || id <= 0) {
      req.flash('danger', 'Mã album không hợp lệ.');
      return res.redirect('/archive/albums');
    }
    const r = await req.callProc('arc.sp_GetAlbumPhotos', { UserId: req.session.user.id, AlbumId: id });
    const album = r.recordsets[0] && r.recordsets[0][0];
    if (!album) {
      req.flash('danger', 'Album không tồn tại.');
      return res.redirect('/archive/albums');
    }
    return res.render('archive/album', { title: album.Title, album, photos: r.recordsets[1] || [] });
  } catch (e) {
    return handleBusinessError(req, res, e, next);
  }
});

module.exports = router;