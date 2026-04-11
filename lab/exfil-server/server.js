const http = require('http');

const PORT = parseInt(process.env.PORT || '9999', 10);

const server = http.createServer((req, res) => {
  if (req.method === 'POST' && req.url === '/exfil') {
    let body = '';
    req.on('data', chunk => { body += chunk; });
    req.on('end', () => {
      const timestamp = new Date().toISOString();
      console.log(`\n${'='.repeat(60)}`);
      console.log(`EXFILTRATION RECEIVED [${timestamp}]`);
      console.log('='.repeat(60));
      try {
        console.log(JSON.stringify(JSON.parse(body), null, 2));
      } catch {
        console.log(body);
      }
      console.log('='.repeat(60) + '\n');
      res.writeHead(200, { 'Content-Type': 'text/plain' });
      res.end('ok');
    });
  } else {
    res.writeHead(404);
    res.end();
  }
});

server.listen(PORT, '0.0.0.0', () => {
  console.log(`exfil-server listening on :${PORT}`);
});
