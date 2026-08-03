const mongoose = require('mongoose');

// One document per installation (device id). `data` is intentionally
// schemaless (Mixed) so the app can send/receive its full local dataset
// (patients, notes, x-ray images as base64, ...) without the backend
// needing to know the exact shape or be updated every time the app's
// data model changes.
const userDataSchema = new mongoose.Schema(
  {
    deviceId: { type: String, required: true, unique: true, index: true },
    data: { type: mongoose.Schema.Types.Mixed, required: true },
    updatedAt: { type: Date, default: Date.now },
  },
  { collection: 'users' }
);

module.exports = mongoose.model('User', userDataSchema);
