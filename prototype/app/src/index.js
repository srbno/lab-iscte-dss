const express = require('express');

const app = express();
const PORT = process.env.PORT || 3000;

app.use(express.json());

// Routes
app.use('/auth',           require('./routes/auth'));
app.use('/api/extensions', require('./routes/extensions'));
app.use('/api/trunks',     require('./routes/trunks'));
app.use('/api/calls',      require('./routes/calls'));

// Health check
app.get('/health', (req, res) => {
  res.json({ status: 'ok', service: 'voip-manager-api', version: '1.0.0' });
});

// 404 handler
app.use((req, res) => {
  res.status(404).json({ error: 'Not found' });
});

// Global error handler
app.use((err, req, res, next) => {
  console.error(err);
  res.status(500).json({ error: 'Internal server error' });
});

app.listen(PORT, () => {
  console.log(`VoIP Manager API running on port ${PORT}`);
});

module.exports = app;
