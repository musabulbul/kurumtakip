import express from 'express';
import crypto from 'crypto';
import pino from 'pino';
import cors from 'cors';
import { Firestore } from '@google-cloud/firestore';

const app = express();
app.use(
  cors({
    origin: true,
    methods: ['GET', 'POST', 'OPTIONS'],
    allowedHeaders: ['Content-Type', 'Authorization']
  })
);
app.options('*', cors());
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
const FIRESTORE_COLLECTION = process.env.FIRESTORE_COLLECTION || 'kurumlar';
const SMS_PROVIDER_COLLECTION = process.env.SMS_PROVIDER_COLLECTION || 'sms_providers';
const SMS_PROVIDER_FIELD = process.env.SMS_PROVIDER_FIELD || 'smsProviderId';
const DEFAULT_TIME_ZONE = process.env.DEFAULT_TIME_ZONE || 'Europe/Istanbul';

function asMap(value) {
  if (value && typeof value === 'object' && !Array.isArray(value)) {
    return value;
  }
  return {};
}

function normalizePhone(value) {
  if (!value) return '';
  let digits = String(value).replace(/\D/g, '');
  if (digits.startsWith('90') && digits.length === 12) digits = digits.slice(2);
  if (digits.startsWith('0') && digits.length === 11) digits = digits.slice(1);
  return digits;
}

function joinUrl(baseUrl, path) {
  const rawPath = String(path || '').trim();
  if (/^https?:\/\//i.test(rawPath)) return rawPath;
  const trimmedBase = String(baseUrl || '').replace(/\/+$/, '');
  const trimmedPath = rawPath.replace(/^\/+/, '');
  if (!trimmedBase) return trimmedPath;
  if (!trimmedPath) return trimmedBase;
  return `${trimmedBase}/${trimmedPath}`;
}

function interpolateTemplate(value, variables) {
  if (typeof value !== 'string') return value;
  return value.replace(/\{\{\s*([a-zA-Z0-9_]+)\s*\}\}/g, (match, key) => {
    if (Object.prototype.hasOwnProperty.call(variables, key)) {
      return String(variables[key] ?? '');
    }
    return match;
  });
}

function resolveParamKey(paramMap, key, fallback) {
  const mapped = String(paramMap?.[key] || '').trim();
  return mapped || fallback || key;
}

function parseProviderBody(rawText) {
  try {
    return JSON.parse(rawText);
  } catch (_) {
    return null;
  }
}

function extractProviderError(decoded) {
  if (!decoded || typeof decoded !== 'object' || Array.isArray(decoded)) return null;
  const status = String(decoded.status || '').trim().toLowerCase();
  const description = String(decoded.description || '').trim();
  const message = String(decoded.message || '').trim();
  const error = String(decoded.error || '').trim();
  const code = Number(decoded.code);
  const hasErrorStatus = status === 'error' || status === 'failed';
  const hasErrorCode = Number.isFinite(code) && code >= 400;
  if (!hasErrorStatus && !hasErrorCode) return null;
  return description || message || error || 'sms_provider_business_error';
}

function extractCredit(decoded) {
  if (!decoded || typeof decoded !== 'object' || Array.isArray(decoded)) return null;
  const data = asMap(decoded.data);
  const raw = data.credit ?? decoded.credit ?? data.smsCredit ?? data.smsKredi ?? data.smsBalance;
  if (raw === null || raw === undefined) return null;
  const numeric = Number(String(raw).replace(',', '.'));
  return Number.isFinite(numeric) ? numeric : null;
}

function buildCredentials(kurumData) {
  return {
    username: String(kurumData.smsApiUsername || kurumData.smsUsername || '').trim(),
    password: String(kurumData.smsApiPassword || kurumData.smsPassword || '').trim(),
    apiKey: String(
      kurumData.smsApiPassword ||
        kurumData.smsPassword ||
        kurumData.smsApiKey ||
        kurumData.smsKey ||
        ''
    ).trim(),
    sender: String(kurumData.smsApiBaslik || kurumData.smsSender || '').trim(),
    tur: String(kurumData.smsApiTur || kurumData.smsType || 'turkce').trim() || 'turkce',
    messageContentType: String(
      kurumData.smsApiIcerikTuru || kurumData.smsContentType || 'bilgi'
    ).trim() || 'bilgi'
  };
}

function buildSmsPayload({
  provider,
  credentials,
  message,
  recipients,
  personalizedMessages,
  sendDate,
  expireDate
}) {
  const paramMap = asMap(provider?.paramMap);
  const payload = {};

  const normalizedRecipients = (recipients || [])
    .map(normalizePhone)
    .filter((value) => value);

  const normalizedPersonalized = (personalizedMessages || [])
    .map((entry) => ({
      phone: normalizePhone(entry.phone || entry.receiver || entry.recipient),
      message: entry.message || entry.text || ''
    }))
    .filter((entry) => entry.phone && entry.message);

  const usePersonalized = normalizedPersonalized.length > 0;
  if (usePersonalized) {
    const messagesField = resolveParamKey(paramMap, 'messages', 'Messages');
    const receiverField = resolveParamKey(paramMap, 'receiver', 'Receiver');
    const messageField = resolveParamKey(paramMap, 'message', 'Message');
    payload[messagesField] = normalizedPersonalized.map((entry) => ({
      [receiverField]: entry.phone,
      [messageField]: entry.message
    }));
  } else {
    const messageField = resolveParamKey(paramMap, 'message', 'Message');
    const receiversField = resolveParamKey(paramMap, 'receivers', 'Receivers');
    payload[messageField] = String(message || '');
    payload[receiversField] = normalizedRecipients;
  }

  if (sendDate) {
    payload[resolveParamKey(paramMap, 'sendDate', 'SendDate')] = sendDate;
  }
  if (expireDate) {
    payload[resolveParamKey(paramMap, 'expireDate', 'ExpireDate')] = expireDate;
  }

  if (credentials?.username) {
    payload[resolveParamKey(paramMap, 'username', 'api_id')] = credentials.username;
  }
  if (credentials?.password) {
    payload[resolveParamKey(paramMap, 'password', 'Password')] = credentials.password;
  }
  if (credentials?.apiKey) {
    payload[resolveParamKey(paramMap, 'apiKey', 'api_key')] = credentials.apiKey;
  }
  if (credentials?.sender) {
    payload[resolveParamKey(paramMap, 'sender', 'sender')] = credentials.sender;
  }
  if (credentials?.tur) {
    payload[resolveParamKey(paramMap, 'messageType', 'message_type')] = credentials.tur;
  }
  if (credentials?.messageContentType) {
    payload[resolveParamKey(paramMap, 'messageContentType', 'message_content_type')] =
      credentials.messageContentType;
  }

  const templateVariables = {
    username: credentials?.username || '',
    password: credentials?.password || '',
    apiKey: credentials?.apiKey || '',
    sender: credentials?.sender || '',
    tur: credentials?.tur || 'turkce',
    messageType: credentials?.tur || 'turkce',
    messageContentType: credentials?.messageContentType || 'bilgi',
    sendDate: sendDate || '',
    expireDate: expireDate || '',
    message: String(message || '')
  };
  const extraParams =
    provider?.extraParams || provider?.defaultPayload || provider?.payloadDefaults || {};
  if (extraParams && typeof extraParams === 'object') {
    for (const [key, value] of Object.entries(extraParams)) {
      payload[key] = interpolateTemplate(value, templateVariables);
    }
  }

  return payload;
}

async function getKurumData(kurumId) {
  if (!kurumId) throw new Error('kurum_id_missing');
  const doc = await getFirestore().collection(FIRESTORE_COLLECTION).doc(kurumId).get();
  if (!doc.exists) throw new Error('kurum_not_found');
  return { id: doc.id, data: doc.data() || {}, ref: doc.ref };
}

async function getSmsProviderData(providerId) {
  if (!providerId) throw new Error('sms_provider_missing');
  const doc = await getFirestore().collection(SMS_PROVIDER_COLLECTION).doc(providerId).get();
  if (!doc.exists) throw new Error('sms_provider_not_found');
  return { id: doc.id, data: doc.data() || {} };
}

async function syncCreditToInstitution(kurumRef, decodedBody) {
  const credit = extractCredit(decodedBody);
  if (!Number.isFinite(credit)) return;
  const normalized = Number.isInteger(credit) ? credit : Number(credit.toFixed(2));
  await kurumRef.set(
    {
      smsCredit: normalized,
      smsKredi: normalized,
      smsBalance: normalized
    },
    { merge: true }
  );
}

async function requestProvider({ providerData, credentials, payload, usePersonalized }) {
  const sendConfig = asMap(providerData.send);
  const oneToMany = asMap(sendConfig.oneToMany || sendConfig.one_to_many || sendConfig.send_1_n);
  const manyToMany = asMap(sendConfig.manyToMany || sendConfig.many_to_many || sendConfig.send_n_n);
  const selected = usePersonalized && Object.keys(manyToMany).length > 0 ? manyToMany : oneToMany;
  const baseUrl = String(providerData.baseUrl || providerData.base_url || '').trim();
  const sendPath = String(selected.path || sendConfig.path || '').trim();
  const method = String(selected.method || sendConfig.method || 'POST').trim().toUpperCase();
  if (!baseUrl || !sendPath) {
    const err = new Error('sms_provider_config_invalid');
    err.httpStatus = 422;
    throw err;
  }

  const headers = {
    'Content-Type': String(selected.contentType || sendConfig.contentType || sendConfig.content_type || 'application/json')
  };
  const headerConfig = asMap(providerData.headers);
  for (const [key, value] of Object.entries(headerConfig)) {
    headers[key] = interpolateTemplate(value, credentials);
  }

  const url = joinUrl(baseUrl, sendPath);
  const response = await fetch(url, {
    method,
    headers,
    body: method === 'GET' ? undefined : JSON.stringify(payload)
  });
  const text = await response.text();
  const decoded = parseProviderBody(text);
  return { url, method, response, text, decoded };
}

async function fetchProviderUserInfo({ providerData, credentials }) {
  const paramMap = asMap(providerData.paramMap);
  const payload = {};
  const usernameKey = resolveParamKey(paramMap, 'username', 'api_id');
  const apiKeyKey = resolveParamKey(paramMap, 'apiKey', 'api_key');
  payload[usernameKey] = credentials.username;
  payload[apiKeyKey] = credentials.apiKey;

  const baseUrl = String(providerData.baseUrl || providerData.base_url || '').trim();
  const infoPath = String(providerData.userInfoPath || '/api/v1/user/information').trim();
  if (!baseUrl || !infoPath) {
    const err = new Error('sms_provider_config_invalid');
    err.httpStatus = 422;
    throw err;
  }

  const url = joinUrl(baseUrl, infoPath);
  const response = await fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(payload)
  });
  const text = await response.text();
  const decoded = parseProviderBody(text);
  return { url, response, text, decoded };
}

function resolveTimeZone(kurumData) {
  const candidates = [
    kurumData?.timeZone,
    kurumData?.timezone,
    kurumData?.saatDilimi,
    asMap(kurumData?.settings)?.timeZone,
    asMap(kurumData?.settings)?.timezone
  ]
    .map((value) => String(value || '').trim())
    .filter(Boolean);

  for (const candidate of candidates) {
    try {
      new Intl.DateTimeFormat('tr-TR', { timeZone: candidate }).format(new Date());
      return candidate;
    } catch (_) {
      // Invalid timezone values are ignored and fallback is used.
    }
  }

  return DEFAULT_TIME_ZONE;
}

function getDatePartsInTimeZone(date, timeZone) {
  const formatter = new Intl.DateTimeFormat('en-GB', {
    timeZone,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    hour12: false
  });
  const parts = formatter.formatToParts(date);
  const lookup = Object.fromEntries(parts.map((part) => [part.type, part.value]));
  return {
    year: Number(lookup.year),
    month: Number(lookup.month),
    day: Number(lookup.day),
    hour: Number(lookup.hour),
    minute: Number(lookup.minute)
  };
}

function formatDateTR(date, timeZone = DEFAULT_TIME_ZONE) {
  return new Intl.DateTimeFormat('tr-TR', {
    timeZone,
    day: '2-digit',
    month: '2-digit',
    year: 'numeric'
  }).format(date);
}

function formatTimeTR(date, timeZone = DEFAULT_TIME_ZONE) {
  return new Intl.DateTimeFormat('tr-TR', {
    timeZone,
    hour: '2-digit',
    minute: '2-digit',
    hour12: false
  }).format(date);
}

function toName(student, nameFormat = 'first') {
  const name = String(student.adi || '').trim();
  const surname = String(student.soyadi || '').trim();
  if (nameFormat === 'full') {
    return [name, surname].filter(Boolean).join(' ').trim() || 'Danışan';
  }
  return name || [name, surname].filter(Boolean).join(' ').trim() || 'Danışan';
}

function composeReminderMessage({ student, reservation, settings, timeZone }) {
  const salutation = String(settings.salutation || 'Sevgili').trim();
  const name = toName(student, settings.nameFormat);
  const body = String(settings.body || 'randevunuzu hatırlatırız.').trim();
  const includeOperation = settings.includeOperation !== false;
  const operationName = String(
    reservation.operationName ||
      (Array.isArray(reservation.operations) && reservation.operations[0]?.operationName) ||
      ''
  ).trim();
  const date = reservation.date?.toDate ? reservation.date.toDate() : null;
  const dateLabel = date ? formatDateTR(date, timeZone) : 'Belirtilen tarihte';
  const timeLabel = date ? formatTimeTR(date, timeZone) : 'belirtilen saatte';
  const operationSegment = includeOperation && operationName ? ` ${operationName}` : '';
  return `${salutation} ${name}. ${dateLabel} tarihinde saat ${timeLabel} için${operationSegment} ${body}`;
}

function composeBirthdayMessage({ student, settings }) {
  const salutation = String(settings.salutation || 'Sevgili').trim();
  const name = toName(student, settings.nameFormat);
  const body = String(settings.body || 'doğum gününüzü kutlar, sağlıklı ve mutlu yıllar dileriz.').trim();
  return `${salutation} ${name}. ${body}`;
}

function parseBirthDate(value, timeZone = DEFAULT_TIME_ZONE) {
  if (!value) return null;
  if (typeof value === 'string') {
    const match = value.match(/^(\d{4})-(\d{2})-(\d{2})$/);
    if (match) return { month: Number(match[2]), day: Number(match[3]) };
    const trMatch = value.match(/^(\d{2})\.(\d{2})\.(\d{4})$/);
    if (trMatch) return { month: Number(trMatch[2]), day: Number(trMatch[1]) };
    return null;
  }
  if (value?.toDate) {
    const d = value.toDate();
    const parts = getDatePartsInTimeZone(d, timeZone);
    return { month: parts.month, day: parts.day };
  }
  return null;
}

function minutesOfDayInTimeZone(date, timeZone = DEFAULT_TIME_ZONE) {
  const parts = getDatePartsInTimeZone(date, timeZone);
  return parts.hour * 60 + parts.minute;
}

function dateKeyInTimeZone(date, timeZone = DEFAULT_TIME_ZONE) {
  const parts = getDatePartsInTimeZone(date, timeZone);
  const mm = String(parts.month).padStart(2, '0');
  const dd = String(parts.day).padStart(2, '0');
  return `${parts.year}-${mm}-${dd}`;
}

function isNowInWindow(nowMinutes, startMinutes, endMinutes) {
  if (startMinutes <= endMinutes) {
    return nowMinutes >= startMinutes && nowMinutes <= endMinutes;
  }
  return nowMinutes >= startMinutes || nowMinutes <= endMinutes;
}

app.get('/health', (req, res) => {
  res.status(200).json({ ok: true });
});

app.post('/sms/send', async (req, res) => {
  const requestId = crypto.randomUUID();
  const startedAt = Date.now();
  logger.info({ requestId, route: 'sms/send' }, '[sms] request received');
  try {
    const body = req.body || {};
    const kurumId = String(body.kurum_id || body.kurumId || '').trim();
    const message = body.message ?? body.text ?? '';
    const recipients = body.recipients || body.phones || [];
    const personalizedMessages =
      body.personalized_messages || body.personalizedMessages || body.messages || [];
    const sendDate = body.send_date || body.sendDate || '';
    const expireDate = body.expire_date || body.expireDate || '';
    const messageContentTypeOverride =
      String(body.message_content_type || body.messageContentType || '').trim();

    if ((!message || String(message).trim() === '') && (!personalizedMessages || personalizedMessages.length === 0)) {
      return res.status(400).json({ error: 'message_required' });
    }

    const kurum = await getKurumData(kurumId);
    const kurumData = kurum.data || {};

    const providerId =
      String(body.provider_id || body.providerId || kurumData[SMS_PROVIDER_FIELD] || kurumData.smsProviderId || '').trim();
    if (!providerId) return res.status(422).json({ error: 'sms_provider_missing' });

    const provider = await getSmsProviderData(providerId);
    const credentials = buildCredentials(kurumData);
    if (messageContentTypeOverride) {
      credentials.messageContentType = messageContentTypeOverride;
    }
    const payload = buildSmsPayload({
      provider: provider.data,
      credentials,
      message,
      recipients,
      personalizedMessages,
      sendDate,
      expireDate
    });

    const providerRequest = await requestProvider({
      providerData: provider.data,
      credentials,
      payload,
      usePersonalized: Array.isArray(personalizedMessages) && personalizedMessages.length > 0
    });

    logger.info(
      {
        requestId,
        providerId,
        url: providerRequest.url,
        status: providerRequest.response.status,
        durationMs: Date.now() - startedAt
      },
      '[sms] provider response'
    );

    if (!providerRequest.response.ok) {
      return res.status(502).json({
        error: 'sms_provider_failed',
        status: providerRequest.response.status,
        body: providerRequest.text
      });
    }

    const businessError = extractProviderError(providerRequest.decoded);
    if (businessError) {
      return res.status(422).json({
        error: 'sms_provider_business_error',
        message: businessError,
        body: providerRequest.decoded || providerRequest.text
      });
    }

    try {
      const userInfo = await fetchProviderUserInfo({ providerData: provider.data, credentials });
      if (userInfo.response.ok) {
        await syncCreditToInstitution(kurum.ref, userInfo.decoded);
      }
    } catch (creditErr) {
      logger.warn({ requestId, creditErr }, '[sms] credit sync failed');
    }

    return res.status(200).json({
      ok: true,
      provider_id: providerId,
      provider_status: providerRequest.response.status,
      provider_response: providerRequest.decoded || { body: providerRequest.text }
    });
  } catch (err) {
    logger.error({ err, requestId }, '[sms] error');
    if (err.message === 'kurum_id_missing') return res.status(400).json({ error: 'kurum_id_required' });
    if (err.message === 'kurum_not_found') return res.status(404).json({ error: 'kurum_not_found' });
    if (err.message === 'sms_provider_missing') return res.status(422).json({ error: 'sms_provider_missing' });
    if (err.message === 'sms_provider_not_found') return res.status(404).json({ error: 'sms_provider_not_found' });
    if (err.message === 'sms_provider_config_invalid') return res.status(422).json({ error: 'sms_provider_config_invalid' });
    return res.status(500).json({ error: 'sms_send_failed', detail: err.message });
  }
});

app.post('/sms/user-info', async (req, res) => {
  const requestId = crypto.randomUUID();
  logger.info({ requestId, route: 'sms/user-info' }, '[sms] user-info request received');
  try {
    const body = req.body || {};
    const kurumId = String(body.kurum_id || body.kurumId || '').trim();
    const kurum = await getKurumData(kurumId);
    const kurumData = kurum.data || {};
    const providerId = String(body.provider_id || body.providerId || kurumData[SMS_PROVIDER_FIELD] || '').trim();
    if (!providerId) return res.status(422).json({ error: 'sms_provider_missing' });

    const provider = await getSmsProviderData(providerId);
    const credentials = buildCredentials(kurumData);
    const infoResponse = await fetchProviderUserInfo({ providerData: provider.data, credentials });

    if (!infoResponse.response.ok) {
      return res.status(502).json({
        error: 'sms_provider_failed',
        status: infoResponse.response.status,
        body: infoResponse.text
      });
    }

    const businessError = extractProviderError(infoResponse.decoded);
    if (businessError) {
      return res.status(422).json({
        error: 'sms_provider_business_error',
        message: businessError,
        body: infoResponse.decoded || infoResponse.text
      });
    }

    await syncCreditToInstitution(kurum.ref, infoResponse.decoded);
    const credit = extractCredit(infoResponse.decoded);

    return res.status(200).json({
      ok: true,
      provider_id: providerId,
      credit,
      data: infoResponse.decoded?.data || infoResponse.decoded || null,
      provider_response: infoResponse.decoded || { body: infoResponse.text }
    });
  } catch (err) {
    logger.error({ err, requestId }, '[sms] user-info error');
    if (err.message === 'kurum_id_missing') return res.status(400).json({ error: 'kurum_id_required' });
    if (err.message === 'kurum_not_found') return res.status(404).json({ error: 'kurum_not_found' });
    if (err.message === 'sms_provider_missing') return res.status(422).json({ error: 'sms_provider_missing' });
    if (err.message === 'sms_provider_not_found') return res.status(404).json({ error: 'sms_provider_not_found' });
    if (err.message === 'sms_provider_config_invalid') return res.status(422).json({ error: 'sms_provider_config_invalid' });
    return res.status(500).json({ error: 'sms_user_info_failed', detail: err.message });
  }
});

app.post('/jobs/reminders/send', async (req, res) => {
  const requestId = crypto.randomUUID();
  const startedAt = Date.now();
  const body = req.body || {};
  const kurumId = String(body.kurum_id || body.kurumId || '').trim();
  const now = new Date();
  const results = [];

  try {
    let kurumDocs = [];
    if (kurumId) {
      const one = await getFirestore().collection(FIRESTORE_COLLECTION).doc(kurumId).get();
      if (one.exists) kurumDocs = [one];
    } else {
      const snap = await getFirestore().collection(FIRESTORE_COLLECTION).get();
      kurumDocs = snap.docs;
    }

    for (const kurumDoc of kurumDocs) {
      const kurumData = kurumDoc.data() || {};
      const providerId = String(kurumData[SMS_PROVIDER_FIELD] || kurumData.smsProviderId || '').trim();
      if (!providerId) continue;
      const timeZone = resolveTimeZone(kurumData);

      const settings = asMap(asMap(kurumData.settings).messageSettings);
      const reminder = asMap(settings.reminder);
      if (reminder.enabled === false) continue;

      const hoursBefore = Number(reminder.hoursBefore || 1);
      const sendWindow = asMap(reminder.sendWindow);
      const startMinutes = Number(sendWindow.startMinutes ?? 9 * 60);
      const endMinutes = Number(sendWindow.endMinutes ?? 21 * 60);
      const nowMinutes = minutesOfDayInTimeZone(now, timeZone);
      if (!isNowInWindow(nowMinutes, startMinutes, endMinutes)) {
        continue;
      }

      const provider = await getSmsProviderData(providerId);
      const credentials = buildCredentials(kurumData);
      const reservationsSnap = await kurumDoc.ref.collection('rezervasyonlar').get();
      const studentCache = new Map();
      let sent = 0;
      let skipped = 0;

      for (const reservationDoc of reservationsSnap.docs) {
        const reservation = reservationDoc.data() || {};
        const reservationDate = reservation.date?.toDate ? reservation.date.toDate() : null;
        if (!reservationDate) {
          skipped += 1;
          continue;
        }

        const targetDate = new Date(reservationDate.getTime() - hoursBefore * 60 * 60 * 1000);
        const diffMs = now.getTime() - targetDate.getTime();
        if (diffMs < 0 || diffMs > 15 * 60 * 1000) {
          skipped += 1;
          continue;
        }

        const reminderKey = `${hoursBefore}:${reservationDate.toISOString()}`;
        const reminderMeta = asMap(reservation.reminderSms);
        if (String(reminderMeta.lastSentKey || '') === reminderKey) {
          skipped += 1;
          continue;
        }

        const customerId = String(reservation.customerId || '').trim();
        if (!customerId) {
          skipped += 1;
          continue;
        }

        let student = studentCache.get(customerId);
        if (!student) {
          const studentDoc = await kurumDoc.ref.collection('danisanlar').doc(customerId).get();
          if (!studentDoc.exists) {
            skipped += 1;
            continue;
          }
          student = studentDoc.data() || {};
          studentCache.set(customerId, student);
        }

        const phone = normalizePhone(student.telefon || student.ogrencitel || '');
        if (!phone) {
          skipped += 1;
          continue;
        }

        const message = composeReminderMessage({
          student,
          reservation,
          settings: reminder,
          timeZone
        });
        const payload = buildSmsPayload({
          provider: provider.data,
          credentials,
          message,
          recipients: [phone],
          personalizedMessages: []
        });
        const sendResponse = await requestProvider({
          providerData: provider.data,
          credentials,
          payload,
          usePersonalized: false
        });

        if (sendResponse.response.ok && !extractProviderError(sendResponse.decoded)) {
          sent += 1;
          await reservationDoc.ref.set(
            {
              reminderSms: {
                lastSentAt: new Date(),
                lastSentKey: reminderKey
              }
            },
            { merge: true }
          );
        }
      }

      results.push({ kurumId: kurumDoc.id, sent, skipped, total: reservationsSnap.size });
    }

    return res.status(200).json({
      ok: true,
      requestId,
      durationMs: Date.now() - startedAt,
      results
    });
  } catch (err) {
    logger.error({ err, requestId }, '[jobs] reminders error');
    return res.status(500).json({ ok: false, error: 'reminders_job_failed', detail: err.message });
  }
});

app.post('/jobs/birthdays/send', async (req, res) => {
  const requestId = crypto.randomUUID();
  const startedAt = Date.now();
  const body = req.body || {};
  const kurumId = String(body.kurum_id || body.kurumId || '').trim();
  const now = new Date();
  const results = [];

  try {
    let kurumDocs = [];
    if (kurumId) {
      const one = await getFirestore().collection(FIRESTORE_COLLECTION).doc(kurumId).get();
      if (one.exists) kurumDocs = [one];
    } else {
      const snap = await getFirestore().collection(FIRESTORE_COLLECTION).get();
      kurumDocs = snap.docs;
    }

    for (const kurumDoc of kurumDocs) {
      const kurumData = kurumDoc.data() || {};
      const providerId = String(kurumData[SMS_PROVIDER_FIELD] || kurumData.smsProviderId || '').trim();
      if (!providerId) continue;
      const timeZone = resolveTimeZone(kurumData);
      const today = getDatePartsInTimeZone(now, timeZone);

      const settings = asMap(asMap(kurumData.settings).messageSettings);
      const birthday = asMap(settings.birthday);
      if (birthday.enabled !== true) continue;

      const sendTimeMinutes = Number(birthday.sendTimeMinutes ?? 9 * 60);
      const nowMinutes = minutesOfDayInTimeZone(now, timeZone);
      if (Math.abs(nowMinutes - sendTimeMinutes) > 15) {
        continue;
      }

      const provider = await getSmsProviderData(providerId);
      const credentials = buildCredentials(kurumData);
      const studentsSnap = await kurumDoc.ref.collection('danisanlar').get();
      let sent = 0;
      let skipped = 0;

      for (const studentDoc of studentsSnap.docs) {
        const student = studentDoc.data() || {};
        const birth = parseBirthDate(student.dogumtarihi, timeZone);
        if (!birth || birth.month !== today.month || birth.day !== today.day) {
          skipped += 1;
          continue;
        }

        const sentKey = dateKeyInTimeZone(now, timeZone);
        if (String(student.birthdaySmsLastSentDate || '') === sentKey) {
          skipped += 1;
          continue;
        }

        const phone = normalizePhone(student.telefon || student.ogrencitel || '');
        if (!phone) {
          skipped += 1;
          continue;
        }

        const message = composeBirthdayMessage({ student, settings: birthday });
        const payload = buildSmsPayload({
          provider: provider.data,
          credentials,
          message,
          recipients: [phone],
          personalizedMessages: []
        });
        const sendResponse = await requestProvider({
          providerData: provider.data,
          credentials,
          payload,
          usePersonalized: false
        });

        if (sendResponse.response.ok && !extractProviderError(sendResponse.decoded)) {
          sent += 1;
          await studentDoc.ref.set(
            {
              birthdaySmsLastSentDate: sentKey,
              birthdaySmsLastSentAt: new Date()
            },
            { merge: true }
          );
        }
      }

      results.push({ kurumId: kurumDoc.id, sent, skipped, total: studentsSnap.size });
    }

    return res.status(200).json({
      ok: true,
      requestId,
      durationMs: Date.now() - startedAt,
      results
    });
  } catch (err) {
    logger.error({ err, requestId }, '[jobs] birthdays error');
    return res.status(500).json({ ok: false, error: 'birthdays_job_failed', detail: err.message });
  }
});

const server = app.listen(PORT, '0.0.0.0', () => {
  logger.info({ port: PORT }, 'SMS gateway service running');
});

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
