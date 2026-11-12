
'use strict';

const router = require('express').Router();
const { requireRole } = require('../lib/auth');
const { queryAs } = require('../lib/db');
const crypto = require('node:crypto');

router.get('/delivery', requireRole('Delivery'), async (req, res, next) => {
    try {
        const userId = Number(req.session.user.id);

        if (!req.session.deliveryCsrfToken) {
            req.session.deliveryCsrfToken = crypto.randomBytes(32).toString('hex');
        }

        const csrfToken = req.session.deliveryCsrfToken;


        const result = await queryAs('delivery', userId, `
            SELECT
                DeliveryRequestId,
                OrderId,
                Direction,
                Status,
                Fee,
                ScheduledAt,
                CreatedAt
            FROM dlv.DeliveryRequests
            ORDER BY CreatedAt DESC
        `);

        
res.render('delivery/index', {
    title: 'Quản lý giao hàng',
    deliveries: result.recordset,
    csrfToken: csrfToken
});

    } catch (err) {
        next(err);
    }
});

router.post('/delivery/:id/status', requireRole('Delivery'), async (req, res, next) => {
    try {
        const userId = Number(req.session.user.id);

        const sessionToken = req.session.deliveryCsrfToken;
        const submittedToken = req.body._csrf;

        if (
            typeof sessionToken !== 'string' ||
            typeof submittedToken !== 'string' ||
            !/^[a-f0-9]{64}$/.test(sessionToken) ||
            !/^[a-f0-9]{64}$/.test(submittedToken) ||
            !crypto.timingSafeEqual(
                Buffer.from(sessionToken, 'hex'),
                Buffer.from(submittedToken, 'hex')
            )
        ) {
            return res.status(403).send('Yêu cầu không hợp lệ (CSRF token).');
        }

        const deliveryId = Number(req.params.id);
        const newStatus = req.body.status;
        const note = String(req.body.note || '').trim();

        if (!Number.isSafeInteger(deliveryId) || deliveryId <= 0) {
            return res.status(400).send('Mã giao hàng không hợp lệ');
        }

        if (!['PickedUp', 'Delivered', 'Failed'].includes(newStatus)) {
            return res.status(400).send('Trạng thái không hợp lệ');
        }

        if (newStatus === 'Failed' && !note) {
            return res.status(400).send('Vui lòng nhập lý do giao thất bại');
        }

        await req.callProc('dlv.sp_UpdateDeliveryStatus', {
            DeliveryRequestId: deliveryId,
            ActorUserId: userId,
            NewStatus: newStatus,
            Note: note || null,
            FailureReason: newStatus === 'Failed' ? note : null
        });

        return res.redirect('/delivery');
    } catch (err) {
        next(err);
    }
});

module.exports = router;
