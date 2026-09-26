'use strict';
// Konfiqurasiya: cPanel → "Setup Node.js App" → Environment variables
// bölməsindən VƏ YA server qovluğundakı .env faylından oxunur.
const fs = require('fs');
const path = require('path');

function loadDotEnv(file) {
  if (!fs.existsSync(file)) return;
  for (const line of fs.readFileSync(file, 'utf8').split(/\r?\n/)) {
    const m = line.match(/^\s*([A-Z0-9_]+)\s*=\s*(.*)\s*$/);
    if (!m || line.trim().startsWith('#')) continue;
    let v = m[2];
    if ((v.startsWith('"') && v.endsWith('"')) || (v.startsWith("'") && v.endsWith("'"))) v = v.slice(1, -1);
    if (process.env[m[1]] === undefined) process.env[m[1]] = v;   // panel dəyəri üstündür
  }
}
loadDotEnv(path.join(__dirname, '..', '.env'));

const env = (k, d) => (process.env[k] === undefined || process.env[k] === '' ? d : process.env[k]);
const bool = (k, d) => { const v = env(k); return v === undefined ? d : /^(1|true|on|yes)$/i.test(v); };

const config = {
  port: Number(env('PORT', 3000)),
  db: {
    host: env('DB_HOST', 'localhost'),
    port: Number(env('DB_PORT', 3306)),
    user: env('DB_USER', ''),
    password: env('DB_PASSWORD', ''),
    database: env('DB_NAME', ''),
    connectionLimit: Number(env('DB_POOL', 8)),
  },
  // Saytın faylları (index.html, sw.js, ikonlar ...). Default: tətbiq qovluğundakı public/
  publicDir: path.resolve(env('PUBLIC_DIR', path.join(__dirname, '..', 'public'))),
  uploadDir: path.resolve(env('UPLOAD_DIR', path.join(__dirname, '..', 'uploads'))),
  sessionDays: Number(env('SESSION_DAYS', 30)),
  // E-poçt təsdiqi: OFF → şagird qeydiyyatdan keçən kimi daxil olur.
  // ON → 6 rəqəmli kod SMTP ilə göndərilir (SMTP_* doldurulmalıdır).
  emailConfirm: bool('EMAIL_CONFIRM', false),
  smtp: {
    host: env('SMTP_HOST', ''),
    port: Number(env('SMTP_PORT', 465)),
    secure: bool('SMTP_SECURE', true),
    user: env('SMTP_USER', ''),
    pass: env('SMTP_PASS', ''),
    from: env('SMTP_FROM', ''),
  },
  maxUploadBytes: Number(env('MAX_UPLOAD_MB', 8)) * 1024 * 1024,
  trustProxy: bool('TRUST_PROXY', true),
};

function checkConfig() {
  const miss = ['DB_USER', 'DB_NAME'].filter(k => !env(k));
  if (miss.length) {
    return 'Çatışmayan ayarlar: ' + miss.join(', ') + ' — cPanel → Setup Node.js App → Environment variables';
  }
  if (config.emailConfirm && (!config.smtp.host || !config.smtp.user)) {
    return 'EMAIL_CONFIRM=on, amma SMTP_HOST/SMTP_USER boşdur — təsdiq kodu göndərilə bilməz';
  }
  return null;
}

module.exports = { config, checkConfig };
