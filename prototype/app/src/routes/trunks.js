const express = require('express');
const { body, param, validationResult } = require('express-validator');
const db = require('../db');
const { authenticate, requireAdmin } = require('../middleware/auth');

const router = express.Router();
router.use(authenticate);

router.get('/', (req, res) => {
  const trunks = db.prepare(
    'SELECT id, name, host, port, username, technology, status, created_at FROM trunks ORDER BY name'
  ).all();
  res.json(trunks);
});

router.get('/:id', [param('id').isInt()], (req, res) => {
  const trunk = db.prepare(
    'SELECT id, name, host, port, username, technology, status, created_at FROM trunks WHERE id = ?'
  ).get(req.params.id);
  if (!trunk) return res.status(404).json({ error: 'Trunk not found' });
  res.json(trunk);
});

router.post('/', requireAdmin, [
  body('name').notEmpty().trim().withMessage('Name required'),
  body('host').notEmpty().trim().withMessage('Host required'),
  body('port').optional().isInt({ min: 1, max: 65535 }),
  body('username').optional({ nullable: true }).trim(),
  body('technology').optional().isIn(['SIP', 'PJSIP', 'IAX2']),
  body('status').optional().isIn(['active', 'inactive']),
], (req, res) => {
  const errors = validationResult(req);
  if (!errors.isEmpty()) return res.status(400).json({ errors: errors.array() });

  const { name, host, port = 5060, username = null, technology = 'PJSIP', status = 'active' } = req.body;

  try {
    const result = db
      .prepare('INSERT INTO trunks (name, host, port, username, technology, status) VALUES (?, ?, ?, ?, ?, ?)')
      .run(name, host, port, username, technology, status);
    res.status(201).json({ id: result.lastInsertRowid, name, host, port, username, technology, status });
  } catch (e) {
    res.status(500).json({ error: 'Internal server error' });
  }
});

router.put('/:id', requireAdmin, [
  param('id').isInt(),
  body('name').optional().notEmpty().trim(),
  body('host').optional().notEmpty().trim(),
  body('port').optional().isInt({ min: 1, max: 65535 }),
  body('technology').optional().isIn(['SIP', 'PJSIP', 'IAX2']),
  body('status').optional().isIn(['active', 'inactive']),
], (req, res) => {
  const errors = validationResult(req);
  if (!errors.isEmpty()) return res.status(400).json({ errors: errors.array() });

  const trunk = db.prepare('SELECT * FROM trunks WHERE id = ?').get(req.params.id);
  if (!trunk) return res.status(404).json({ error: 'Trunk not found' });

  const name       = req.body.name       ?? trunk.name;
  const host       = req.body.host       ?? trunk.host;
  const port       = req.body.port       ?? trunk.port;
  const username   = req.body.username   !== undefined ? req.body.username : trunk.username;
  const technology = req.body.technology ?? trunk.technology;
  const status     = req.body.status     ?? trunk.status;

  db.prepare('UPDATE trunks SET name = ?, host = ?, port = ?, username = ?, technology = ?, status = ? WHERE id = ?')
    .run(name, host, port, username, technology, status, req.params.id);

  res.json({ id: Number(req.params.id), name, host, port, username, technology, status });
});

router.delete('/:id', requireAdmin, [param('id').isInt()], (req, res) => {
  const result = db.prepare('DELETE FROM trunks WHERE id = ?').run(req.params.id);
  if (result.changes === 0) return res.status(404).json({ error: 'Trunk not found' });
  res.status(204).end();
});

module.exports = router;
