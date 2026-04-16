const Database = require('better-sqlite3');
const path = require('path');
const fs = require('fs');

const dataDir = path.join(__dirname, '..', 'data');
if (!fs.existsSync(dataDir)) fs.mkdirSync(dataDir, { recursive: true });

const db = new Database(path.join(dataDir, 'voip.db'));

db.pragma('journal_mode = WAL');
db.pragma('foreign_keys = ON');

db.exec(`
  CREATE TABLE IF NOT EXISTS users (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    email         TEXT    UNIQUE NOT NULL,
    password_hash TEXT    NOT NULL,
    role          TEXT    NOT NULL DEFAULT 'operator' CHECK (role IN ('admin', 'operator')),
    created_at    DATETIME DEFAULT CURRENT_TIMESTAMP
  );

  CREATE TABLE IF NOT EXISTS extensions (
    id         INTEGER PRIMARY KEY AUTOINCREMENT,
    number     TEXT    UNIQUE NOT NULL,
    name       TEXT    NOT NULL,
    user_id    INTEGER REFERENCES users(id) ON DELETE SET NULL,
    status     TEXT    NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'inactive')),
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
  );

  CREATE TABLE IF NOT EXISTS trunks (
    id         INTEGER PRIMARY KEY AUTOINCREMENT,
    name       TEXT    NOT NULL,
    host       TEXT    NOT NULL,
    port       INTEGER NOT NULL DEFAULT 5060,
    username   TEXT,
    technology TEXT    NOT NULL DEFAULT 'PJSIP' CHECK (technology IN ('SIP', 'PJSIP', 'IAX2')),
    status     TEXT    NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'inactive')),
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
  );

  CREATE TABLE IF NOT EXISTS call_records (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    src_extension TEXT    NOT NULL,
    dst_number    TEXT    NOT NULL,
    trunk_id      INTEGER REFERENCES trunks(id) ON DELETE SET NULL,
    duration_sec  INTEGER NOT NULL DEFAULT 0,
    status        TEXT    NOT NULL DEFAULT 'answered'
                  CHECK (status IN ('answered', 'no-answer', 'busy', 'failed')),
    started_at    DATETIME DEFAULT CURRENT_TIMESTAMP
  );
`);

module.exports = db;
