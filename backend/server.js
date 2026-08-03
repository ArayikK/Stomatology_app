require('dotenv').config();
const express = require('express');
const cors = require('cors');
const mongoose = require('mongoose');

const UserData = require('./models/UserData');

const PORT = process.env.PORT || 3000;
const MONGODB_URI = process.env.MONGODB_URI;

if (!MONGODB_URI) {
  console.error('Missing MONGODB_URI environment variable. Copy .env.example to .env and fill it in.');
  process.exit(1);
}

const app = express();
app.use(cors());
// Images are embedded as base64, so allow a generous body size.
app.use(express.json({ limit: '50mb' }));

app.get('/', (_req, res) => {
  res.json({ status: 'ok', service: 'stom-backend' });
});

// Fetch everything stored for this device.
app.get('/api/user/:deviceId', async (req, res) => {
  const { deviceId } = req.params;
  try {
    const record = await UserData.findOne({ deviceId }).lean();
    if (!record) {
      return res.status(404).json({ error: 'No data found for this device yet.' });
    }
    res.json(record);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Internal server error.' });
  }
});

// Replace everything stored for this device with the given payload
// (create the record on first call, update it on every call after).
app.put('/api/user/:deviceId', async (req, res) => {
  const { deviceId } = req.params;
  const { data } = req.body ?? {};
  if (data === undefined) {
    return res.status(400).json({ error: '"data" field is required in the request body.' });
  }
  try {
    const record = await UserData.findOneAndUpdate(
      { deviceId },
      { deviceId, data, updatedAt: new Date() },
      { new: true, upsert: true }
    );
    res.json(record);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Internal server error.' });
  }
});

mongoose
  .connect(MONGODB_URI)
  .then(() => {
    console.log('Connected to MongoDB');
    app.listen(PORT, () => console.log(`Stom backend listening on port ${PORT}`));
  })
  .catch((err) => {
    console.error('Failed to connect to MongoDB:', err.message);
    process.exit(1);
  });
