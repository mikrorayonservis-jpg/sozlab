'use strict';
// E-poçt (yalnız EMAIL_CONFIRM=on olanda lazımdır).
// cPanel-də: Email Accounts → məs. noreply@saytiniz.az yaradın, sonra
// SMTP_HOST=mail.saytiniz.az, SMTP_PORT=465, SMTP_USER/SMTP_PASS həmin hesab.
// Hostinqin öz poçtu olduğu üçün Supabase-dəki "kod gəlmir" problemi yoxdur.
const { config } = require('./config');

let transport = null;
function getTransport() {
  if (transport) return transport;
  let nodemailer;
  try { nodemailer = require('nodemailer'); }
  catch (e) { throw new Error('nodemailer quraşdırılmayıb — cPanel-də "Run NPM Install" düyməsini basın'); }
  transport = nodemailer.createTransport({
    host: config.smtp.host, port: config.smtp.port, secure: config.smtp.secure,
    auth: { user: config.smtp.user, pass: config.smtp.pass },
  });
  return transport;
}

async function sendOtp(to, code) {
  if (process.env.SOZLAB_TEST_MAIL) {                    // yalnız avtomatik testlər üçün
    require('fs').appendFileSync(process.env.SOZLAB_TEST_MAIL, JSON.stringify({ to, code }) + '\n');
    return;
  }
  const from = config.smtp.from || config.smtp.user;
  await getTransport().sendMail({
    from: `SözLab <${from}>`, to,
    subject: `SözLab təsdiq kodu: ${code}`,
    text: `Salam!\n\nSözLab qeydiyyatını tamamlamaq üçün kodunuz: ${code}\n\nKod 15 dəqiqə etibarlıdır. Bu sorğunu siz etməmisinizsə, məktubu nəzərə almayın.`,
    html: `<div style="font-family:Arial,sans-serif;font-size:15px;color:#172033">
      <p>Salam!</p><p>SözLab qeydiyyatını tamamlamaq üçün kodunuz:</p>
      <p style="font-size:30px;font-weight:bold;letter-spacing:6px;margin:18px 0">${code}</p>
      <p style="color:#475569">Kod 15 dəqiqə etibarlıdır. Bu sorğunu siz etməmisinizsə, məktubu nəzərə almayın.</p></div>`,
  });
}

module.exports = { sendOtp };
