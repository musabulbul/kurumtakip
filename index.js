import express from 'express';
import crypto from 'crypto';
import pino from 'pino';
import { Firestore } from '@google-cloud/firestore';
import {
  makeWASocket,
  useMultiFileAuthState,
  fetchLatestBaileysVersion,
  DisconnectReason,
  delay
} from '@whiskeysockets/baileys';
import { ensureSessionDir, downloadSessionFromGCS, uploadSessionToGCS } from './storage.js';

const app = express();
app.use(express.json());

if (!globalThis.crypto) {
  globalThis.crypto = crypto.webcrypto;
}

const logger = pino({ level: process.env.LOG_LEVEL || 'info' });

let firestore;
function getFirestore() {
  if (!firestore) firestore = new Firestore();
  return firestore;
}

const PORT = process.env.PORT || 8080;
const GCS_BUCKET = process.env.GCS_BUCKET;
const SESSION_ROOT = process.env.SESSION_ROOT || '/tmp/whatsapp-sessions';
const FIRESTORE_COLLECTION = process.env.FIRESTORE_COLLECTION || 'kurumlar';
const FIRESTORE_SESSION_FIELD = process.env.FIRESTORE_SESSION_FIELD || 'session_id';
const DEFAULT_SESSION_ID = process.env.DEFAULT_SESSION_ID || '';

const sessions = new Map();
const sessionInit = new Map();

function randomDelayMs(minSeconds, maxSeconds) {
  const minMs = Math.max(0, Math.floor(minSeconds * 1000));
  const maxMs = Math.max(minMs, Math.floor(maxSeconds * 1000));
  return Math.floor(Math.random() * (maxMs - minMs + 1)) + minMs;
}

function normalizeRecipient(recipient) {
  if (!recipient) return '';
  if (recipient.includes('@')) return recipient;
  const digits = recipient.replace(/\D/g, '');
  return `${digits}@s.whatsapp.net`;
}

async function getSessionIdForKurum(kurumId) {
  if (!kurumId) {
    if (DEFAULT_SESSION_ID) return DEFAULT_SESSION_ID;
    throw new Error('kurum_id_missing');
  }
  const doc = await getFirestore().collection(FIRESTORE_COLLECTION).doc(kurumId).get();
  if (!doc.exists) throw new Error('kurum_not_found');
  const sessionId = doc.get(FIRESTORE_SESSION_FIELD);
  if (!sessionId) throw new Error('session_id_missing');
  return String(sessionId);
}

async function waitForConnection(sessionInfo, timeoutMs) {
  if (sessionInfo.connection === 'open') return;
  await new Promise((resolve, reject) => {
    const timeout = setTimeout(() => {
      sessionInfo.listeners.delete(listener);
      reject(new Error('connection_timeout'));
    }, timeoutMs);
    const listener = () => {
      if (sessionInfo.connection === 'open') {
        clearTimeout(timeout);
        sessionInfo.listeners.delete(listener);
        resolve();
      }
    };
    sessionInfo.listeners.add(listener);
  });
}

async function initSession(sessionId) {
  if (sessions.has(sessionId)) return sessions.get(sessionId);
  if (sessionInit.has(sessionId)) return sessionInit.get(sessionId);

  const initPromise = (async () => {
    const localDir = await ensureSessionDir(SESSION_ROOT, sessionId);
    await downloadSessionFromGCS(GCS_BUCKET, sessionId, localDir);

    const { state, saveCreds } = await useMultiFileAuthState(localDir);
    const { version } = await fetchLatestBaileysVersion();

    const sock = makeWASocket({
      auth: state,
      version,
      printQRInTerminal: false,
      
      logger,
      browser: ['KurumTakip', 'Chrome', '1.0.0'], // Engel yememek için tarayıcı kimliği
      syncFullHistory: false // Bağlantıyı hızlandırmak için geçmişi çekme
    });

    const sessionInfo = {
      sessionId,
      localDir,
      sock,
      connection: 'connecting',
      lastDisconnect: null,
      listeners: new Set()
    };

    sock.ev.on('creds.update', async () => {
      await saveCreds();
      await uploadSessionToGCS(GCS_BUCKET, sessionId, localDir);
    });

    sock.ev.on('connection.update', (update) => {
      if (update.connection) {
        sessionInfo.connection = update.connection;
        for (const listener of sessionInfo.listeners) listener();
      }
      if (update.lastDisconnect) {
        sessionInfo.lastDisconnect = update.lastDisconnect;
        const statusCode = update.lastDisconnect?.error?.output?.statusCode;
        if (statusCode === DisconnectReason.loggedOut) {
          logger.warn({ sessionId }, 'Session logged out');
        } else {
          logger.warn({ sessionId, statusCode }, 'Connection closed');
        }
      }
    });

    sessions.set(sessionId, sessionInfo);
    return sessionInfo;
  })();

  sessionInit.set(sessionId, initPromise);
  try {
    return await initPromise;
  } finally {
    sessionInit.delete(sessionId);
  }
}

app.get('/health', (req, res) => {
  res.status(200).json({ ok: true });
});

app.get('/get-code', async (req, res) => {
  try {
    const phone = String(req.query.phone || '');
    if (!phone) return res.status(400).json({ error: 'phone_required' });

    const kurumId = String(req.query.kurum_id || '');
    const sessionId = await getSessionIdForKurum(kurumId);
    const sessionInfo = await initSession(sessionId);

    if (sessionInfo.sock.authState?.creds?.registered) {
      return res.status(409).json({ error: 'session_already_registered' });
    }

    await delay(500);
    await delay(2000); // Bağlantının oturması için süreyi artırdık
    const code = await sessionInfo.sock.requestPairingCode(phone);
    return res.status(200).json({ code });
  } catch (err) {
    logger.error({ err }, 'Pairing code error');
    if (err.message === 'kurum_id_missing') return res.status(400).json({ error: 'kurum_id_required' });
    if (err.message === 'kurum_not_found') return res.status(404).json({ error: 'kurum_not_found' });
    if (err.message === 'session_id_missing') return res.status(422).json({ error: 'session_id_missing' });
    return res.status(500).json({ error: 'pairing_code_failed' });
  }
});

app.post('/send-message', async (req, res) => {
  try {
    const { recipient, message, kurum_id: kurumId, delay_min, delay_max } = req.body || {};
    if (!recipient || !message) {
      return res.status(400).json({ error: 'recipient_and_message_required' });
    }

    const sessionId = await getSessionIdForKurum(kurumId ? String(kurumId) : '');
    const sessionInfo = await initSession(sessionId);

    if (sessionInfo.connection !== 'open') {
      await waitForConnection(sessionInfo, 15000);
    }

    if (sessionInfo.connection !== 'open') {
      return res.status(503).json({ error: 'whatsapp_not_connected' });
    }

    const minDelay = Number.isFinite(Number(delay_min)) ? Number(delay_min) : 10;
    const maxDelay = Number.isFinite(Number(delay_max)) ? Number(delay_max) : 20;
    const waitMs = randomDelayMs(minDelay, maxDelay);
    await delay(waitMs);

    const jid = normalizeRecipient(String(recipient));
    await sessionInfo.sock.sendMessage(jid, { text: String(message) });
    return res.status(200).json({ ok: true, delayed_ms: waitMs });
  } catch (err) {
    logger.error({ err }, 'Send message error');
    if (err.message === 'kurum_id_missing') return res.status(400).json({ error: 'kurum_id_required' });
    if (err.message === 'kurum_not_found') return res.status(404).json({ error: 'kurum_not_found' });
    if (err.message === 'session_id_missing') return res.status(422).json({ error: 'session_id_missing' });
    if (err.message === 'connection_timeout') return res.status(504).json({ error: 'whatsapp_connection_timeout' });
    return res.status(500).json({ error: 'send_message_failed' });
  }
});

const server = app.listen(PORT, '0.0.0.0', () => {
  logger.info({ port: PORT }, 'WhatsApp automation service running');
});

// Graceful shutdown for Cloud Run
process.on('SIGTERM', () => {
  logger.info('SIGTERM signal received.');
  server.close(() => {
    logger.info('Http server closed.');
  });
});

process.on('uncaughtException', (err) => {
  logger.error({ err }, 'Uncaught Exception');
});

process.on('unhandledRejection', (reason, promise) => {
  logger.error({ reason, promise }, 'Unhandled Rejection');
});
