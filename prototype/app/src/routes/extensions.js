const express = require('express');
const { body, param, validationResult } = require('express-validator');
const db = require('../db');
const { authenticate } = require('../middleware/auth');

const router = express.Router();
router.use(authenticate);

router.get('/', (req, res) => {
  const { status } = req.query;
  let sql = 'SELECT e.*, u.email as user_email FROM extensions e LEFT JOIN users u ON e.user_id = u.id';
  const params = [];
  if (status) {
    sql += ' WHERE e.status = ?';
    params.push(status);
  }
  sql += ' ORDER BY e.number';
  res.json(db.prepare(sql).all(...params));
});

router.get('/:id', [
  param('id').isInt(),
], (req, res) => {
  const ext = db.prepare(
    'SELECT e.*, u.email as user_email FROM extensions e LEFT JOIN users u ON e.user_id = u.id WHERE e.id = ?'
  ).get(req.params.id);
  if (!ext) return res.status(404).json({ error: 'Extension not found' });
  res.json(ext);
});

router.post('/', [
  body('number').notEmpty().trim().withMessage('Extension number required'),
  body('name').notEmpty().trim().withMessage('Name required'),
  body('user_id').optional({ nullable: true }).isInt(),
  body('status').optional().isIn(['active', 'inactive']),
], (req, res) => {
  const errors = validationResult(req);
  if (!errors.isEmpty()) return res.status(400).json({ errors: errors.array() });

  const { number, name, user_id = null, status = 'active' } = req.body;

  try {
    const result = db
      .prepare('INSERT INTO extensions (number, name, user_id, status) VALUES (?, ?, ?, ?)')
      .run(number, name, user_id, status);
    res.status(201).json({ id: result.lastInsertRowid, number, name, user_id, status });
  } catch (e) {
    if (e.message.includes('UNIQUE')) {
      return res.status(409).json({ error: 'Extension number already exists' });
    }
    res.status(500).json({ error: 'Internal server error' });
  }
});

router.put('/:id', [
  param('id').isInt(),
  body('name').optional().notEmpty().trim(),
  body('user_id').optional({ nullable: true }).isInt(),
  body('status').optional().isIn(['active', 'inactive']),
], (req, res) => {
  const errors = validationResult(req);
  if (!errors.isEmpty()) return res.status(400).json({ errors: errors.array() });

  const ext = db.prepare('SELECT * FROM extensions WHERE id = ?').get(req.params.id);
  if (!ext) return res.status(404).json({ error: 'Extension not found' });

  const name = req.body.name ?? ext.name;
  const user_id = req.body.user_id !== undefined ? req.body.user_id : ext.user_id;
  const status = req.body.status ?? ext.status;

  db.prepare('UPDATE extensions SET name = ?, user_id = ?, status = ? WHERE id = ?')
    .run(name, user_id, status, req.params.id);

  res.json({ id: Number(req.params.id), number: ext.number, name, user_id, status });
});

router.delete('/:id', [param('id').isInt()], (req, res) => {
  const result = db.prepare('DELETE FROM extensions WHERE id = ?').run(req.params.id);
  if (result.changes === 0) return res.status(404).json({ error: 'Extension not found' });
  res.status(204).end();
});

module.exports = router;
