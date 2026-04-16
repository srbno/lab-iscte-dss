const express = require('express');
const { body, query, param, validationResult } = require('express-validator');
const _ = require('lodash');
const db = require('../db');
const { authenticate } = require('../middleware/auth');

const router = express.Router();
router.use(authenticate);

// GET /api/calls — CDR with optional filters
router.get('/', [
  query('extension').optional().trim(),
  query('status').optional().isIn(['answered', 'no-answer', 'busy', 'failed']),
  query('from').optional().isISO8601().withMessage('from must be ISO 8601 date'),
  query('to').optional().isISO8601().withMessage('to must be ISO 8601 date'),
  query('limit').optional().isInt({ min: 1, max: 1000 }).toInt(),
], (req, res) => {
  const errors = validationResult(req);
  if (!errors.isEmpty()) return res.status(400).json({ errors: errors.array() });

  let sql = 'SELECT cr.*, t.name as trunk_name FROM call_records cr LEFT JOIN trunks t ON cr.trunk_id = t.id WHERE 1=1';
  const params = [];

  if (req.query.extension) { sql += ' AND cr.src_extension = ?'; params.push(req.query.extension); }
  if (req.query.status)    { sql += ' AND cr.status = ?';        params.push(req.query.status); }
  if (req.query.from)      { sql += ' AND cr.started_at >= ?';   params.push(req.query.from); }
  if (req.query.to)        { sql += ' AND cr.started_at <= ?';   params.push(req.query.to); }

  sql += ' ORDER BY cr.started_at DESC LIMIT ?';
  params.push(req.query.limit || 200);

  res.json(db.prepare(sql).all(...params));
});

// GET /api/calls/stats — aggregated CDR statistics (uses lodash)
router.get('/stats', (req, res) => {
  const records = db.prepare('SELECT * FROM call_records').all();

  if (records.length === 0) {
    return res.json({ total: 0, message: 'No call records found' });
  }

  const byExtension = _.mapValues(
    _.groupBy(records, 'src_extension'),
    (calls) => ({
      count: calls.length,
      total_duration_sec: _.sumBy(calls, 'duration_sec'),
      avg_duration_sec: Math.round(_.meanBy(calls, 'duration_sec')),
      by_status: _.countBy(calls, 'status'),
    })
  );

  const stats = {
    total: records.length,
    total_duration_sec: _.sumBy(records, 'duration_sec'),
    avg_duration_sec: Math.round(_.meanBy(records, 'duration_sec')),
    by_status: _.countBy(records, 'status'),
    by_extension: byExtension,
  };

  res.json(stats);
});

// GET /api/calls/:id
router.get('/:id', [param('id').isInt()], (req, res) => {
  const record = db.prepare(
    'SELECT cr.*, t.name as trunk_name FROM call_records cr LEFT JOIN trunks t ON cr.trunk_id = t.id WHERE cr.id = ?'
  ).get(req.params.id);
  if (!record) return res.status(404).json({ error: 'Call record not found' });
  res.json(record);
});

// POST /api/calls — register a call record (e.g. posted by Asterisk AGI/ARI)
router.post('/', [
  body('src_extension').notEmpty().trim().withMessage('Source extension required'),
  body('dst_number').notEmpty().trim().withMessage('Destination number required'),
  body('duration_sec').isInt({ min: 0 }).withMessage('Duration must be a non-negative integer'),
  body('status').isIn(['answered', 'no-answer', 'busy', 'failed']).withMessage('Invalid status'),
  body('trunk_id').optional({ nullable: true }).isInt(),
], (req, res) => {
  const errors = validationResult(req);
  if (!errors.isEmpty()) return res.status(400).json({ errors: errors.array() });

  const { src_extension, dst_number, trunk_id = null, duration_sec, status } = req.body;

  const result = db
    .prepare('INSERT INTO call_records (src_extension, dst_number, trunk_id, duration_sec, status) VALUES (?, ?, ?, ?, ?)')
    .run(src_extension, dst_number, trunk_id, duration_sec, status);

  res.status(201).json({ id: result.lastInsertRowid, src_extension, dst_number, trunk_id, duration_sec, status });
});

module.exports = router;
