import express from 'express';
import crypto from 'crypto';
import pino from 'pino';
import cors from 'cors';
import { Firestore } from '@google-cloud/firestore';
import { initializeApp, getApps } from 'firebase-admin/app';
import { getMessaging } from 'firebase-admin/messaging';

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

let messaging;
function getMessagingService() {
  if (!messaging) {
    if (getApps().length === 0) initializeApp();
    messaging = getMessaging();
  }
  return messaging;
}

async function sendFcmToUser({ userId, title, body }) {
  if (!userId) return { ok: false, reason: 'user_id_missing' };
  try {
    const db = getFirestore();
    const userDoc = await db.collection('kullanicilar').doc(userId).get();
    if (!userDoc.exists) {
      logger.warn({ userId }, '[FCM] user document not found');
      return { ok: false, reason: 'user_not_found' };
    }
    const fcmToken = (userDoc.data() || {}).fcmToken;
    if (!fcmToken) {
      logger.warn({ userId }, '[FCM] token not found on user document');
      return { ok: false, reason: 'token_missing' };
    }
    const messageId = await getMessagingService().send({
      token: fcmToken,
      notification: { title, body },
      android: { notification: { sound: 'default', priority: 'high' } },
      apns: { payload: { aps: { sound: 'default' } } },
    });
    logger.info({ userId, messageId }, '[FCM] push sent');
    return { ok: true, reason: 'sent', messageId };
  } catch (e) {
    logger.warn({ err: e, userId }, '[FCM] sendFcmToUser error');
    return { ok: false, reason: 'send_error', error: String(e?.message || e) };
  }
}

const PORT = process.env.PORT || 8080;
const FIRESTORE_COLLECTION = process.env.FIRESTORE_COLLECTION || 'kurumlar';
const SMS_PROVIDER_COLLECTION = process.env.SMS_PROVIDER_COLLECTION || 'sms_providers';
const SMS_PROVIDER_FIELD = process.env.SMS_PROVIDER_FIELD || 'smsProviderId';
const DEFAULT_TIME_ZONE = process.env.DEFAULT_TIME_ZONE || 'Europe/Istanbul';
const BOOKING_ORGS_COLLECTION = process.env.BOOKING_ORGS_COLLECTION || 'orgs';
const BOOKING_SERVICES_SUBCOLLECTION = process.env.BOOKING_SERVICES_SUBCOLLECTION || 'services';
const BOOKINGS_COLLECTION = process.env.BOOKINGS_COLLECTION || 'bookings';
const BOOKING_LOCKS_COLLECTION = process.env.BOOKING_LOCKS_COLLECTION || 'bookingLocks';
const PERMISSION_RECEIVE_ALL_RESERVATION_NOTIFICATIONS =
  'can_receive_all_reservation_notifications';

function asMap(value) {
  if (value && typeof value === 'object' && !Array.isArray(value)) {
    return value;
  }
  return {};
}

/**
 * Org belgesini önce `orgs` koleksiyonunda, bulamazsa `kurumlar` koleksiyonunda arar.
 * Flutter'ın OrgPublicService ile aynı mantık.
 * @returns {{ snap: FirebaseFirestore.DocumentSnapshot, ref: FirebaseFirestore.DocumentReference, bookingEnabled: boolean, settings: object } | null}
 */
async function resolveOrgData(db, orgId) {
  if (!orgId) return null;

  // Önce `orgs` koleksiyonuna bak
  const orgsSnap = await db.collection(BOOKING_ORGS_COLLECTION).doc(orgId).get();
  if (orgsSnap.exists) {
    const raw = orgsSnap.data() || {};
    return {
      snap: orgsSnap,
      ref: orgsSnap.ref,
      bookingEnabled: raw.bookingEnabled === true,
      settings: asMap(raw.bookingSettings),
      workingHours: asMap(raw.workingHours),
    };
  }

  // Fallback: `kurumlar` koleksiyonu (legacy)
  const legacySnap = await db.collection('kurumlar').doc(orgId).get();
  if (!legacySnap.exists) return null;

  const raw = legacySnap.data() || {};
  const rootSettings = asMap(raw.settings);
  const onlineBooking = asMap(rootSettings.onlineBooking);
  const settings = Object.keys(asMap(raw.bookingSettings)).length > 0
    ? asMap(raw.bookingSettings)
    : onlineBooking;
  const bookingEnabled = raw.bookingEnabled === true || settings.enabled === true;
  const workingHours = Object.keys(asMap(raw.workingHours)).length > 0
    ? asMap(raw.workingHours)
    : asMap(onlineBooking.workingHours);

  return {
    snap: legacySnap,
    ref: legacySnap.ref,
    bookingEnabled,
    settings,
    workingHours,
  };
}

function normalizePhone(value) {
  if (!value) return '';
  let digits = String(value).replace(/\D/g, '');
  if (digits.startsWith('90') && digits.length === 12) digits = digits.slice(2);
  if (digits.startsWith('0') && digits.length === 11) digits = digits.slice(1);
  return digits;
}

function buildShortName(fullName) {
  const parts = String(fullName || '').trim().split(/\s+/).filter(Boolean);
  if (parts.length === 0) return '-';
  if (parts.length === 1) return parts[0];
  return `${parts[0]} ${parts[parts.length - 1][0].toUpperCase()}`;
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

function hasExplicitPermission(userData, permissionKey) {
  if (!permissionKey) return false;
  const raw = userData?.yetkiler;
  if (!Array.isArray(raw)) return false;
  return raw
    .map((item) => String(item || '').trim().toLowerCase())
    .includes(String(permissionKey).trim().toLowerCase());
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
    const raw = value.trim();
    const ymd = raw.match(/^(\d{4})[-./](\d{2})[-./](\d{2})$/);
    if (ymd) return { month: Number(ymd[2]), day: Number(ymd[3]) };
    const dmy = raw.match(/^(\d{2})[-./](\d{2})[-./](\d{4})$/);
    if (dmy) return { month: Number(dmy[2]), day: Number(dmy[1]) };
    const parsed = new Date(raw);
    if (!Number.isNaN(parsed.getTime())) {
      const parts = getDatePartsInTimeZone(parsed, timeZone);
      return { month: parts.month, day: parts.day };
    }
    return null;
  }
  if (value?.toDate) {
    const d = value.toDate();
    const parts = getDatePartsInTimeZone(d, timeZone);
    return { month: parts.month, day: parts.day };
  }
  if (typeof value === 'number') {
    const parsed = new Date(value);
    if (!Number.isNaN(parsed.getTime())) {
      const parts = getDatePartsInTimeZone(parsed, timeZone);
      return { month: parts.month, day: parts.day };
    }
  }
  if (typeof value === 'object' && value && Number.isFinite(value._seconds)) {
    const parsed = new Date(Number(value._seconds) * 1000);
    if (!Number.isNaN(parsed.getTime())) {
      const parts = getDatePartsInTimeZone(parsed, timeZone);
      return { month: parts.month, day: parts.day };
    }
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

app.post('/sms/otp', async (req, res) => {
  const requestId = crypto.randomUUID();
  logger.info({ requestId, route: 'sms/otp' }, '[sms] otp request received');
  try {
    const body = req.body || {};
    const kurumId = String(body.kurum_id || body.kurumId || '').trim();
    const phone = String(body.phone || '').trim();
    const orgName = String(body.org_name || body.orgName || '').trim();

    if (!phone) return res.status(400).json({ error: 'phone_required' });

    const kurum = await getKurumData(kurumId);
    const kurumData = kurum.data || {};

    const providerId = String(
      body.provider_id || body.providerId || kurumData[SMS_PROVIDER_FIELD] || kurumData.smsProviderId || ''
    ).trim();
    if (!providerId) return res.status(422).json({ error: 'sms_provider_missing' });

    const provider = await getSmsProviderData(providerId);
    const credentials = buildCredentials(kurumData);

    // 6 haneli rastgele OTP kodu oluştur
    const code = String(Math.floor(100000 + Math.random() * 900000));
    const label = orgName ? `${orgName} online` : 'Online randevu';
    const message = `${label} sistemine giris kodunuz: ${code}`;

    const payload = buildSmsPayload({
      provider: provider.data,
      credentials,
      message,
      recipients: [phone],
      personalizedMessages: [],
    });

    const providerRequest = await requestProvider({
      providerData: provider.data,
      credentials,
      payload,
      usePersonalized: false,
    });

    logger.info(
      { requestId, providerId, status: providerRequest.response.status },
      '[sms] otp provider response'
    );

    if (!providerRequest.response.ok) {
      return res.status(502).json({
        error: 'sms_provider_failed',
        status: providerRequest.response.status,
      });
    }

    const businessError = extractProviderError(providerRequest.decoded);
    if (businessError) {
      return res.status(422).json({ error: 'sms_provider_business_error', message: businessError });
    }

    return res.status(200).json({ ok: true, code });
  } catch (err) {
    logger.error({ err, requestId }, '[sms] otp error');
    if (err.message === 'kurum_id_missing') return res.status(400).json({ error: 'kurum_id_required' });
    if (err.message === 'kurum_not_found') return res.status(404).json({ error: 'kurum_not_found' });
    if (err.message === 'sms_provider_missing') return res.status(422).json({ error: 'sms_provider_missing' });
    if (err.message === 'sms_provider_not_found') return res.status(404).json({ error: 'sms_provider_not_found' });
    return res.status(500).json({ error: 'otp_send_failed', detail: err.message });
  }
});

app.post('/registration/check', async (req, res) => {
  try {
    const body = req.body || {};
    const email = String(body.email || '').trim().toLowerCase();
    const phone = String(body.phone || '').trim();

    const db = getFirestore();
    const results = await Promise.all([
      email
        ? db.collection('kullanicilar').where('email', '==', email).limit(1).get()
        : Promise.resolve(null),
      phone
        ? db.collection('kullanicilar').where('telefon', '==', phone).limit(1).get()
        : Promise.resolve(null),
    ]);

    return res.status(200).json({
      ok: true,
      emailExists: results[0] ? !results[0].empty : false,
      phoneExists: results[1] ? !results[1].empty : false,
    });
  } catch (err) {
    logger.error({ err }, '[registration] check error');
    return res.status(500).json({ error: 'check_failed', detail: err.message });
  }
});

app.post('/sms/registration-otp', async (req, res) => {
  const requestId = crypto.randomUUID();
  logger.info({ requestId, route: 'sms/registration-otp' }, '[sms] registration otp request received');
  try {
    const body = req.body || {};
    const phone = String(body.phone || '').trim();
    if (!phone) return res.status(400).json({ error: 'phone_required' });

    const systemKurumId = process.env.SYSTEM_KURUM_ID || '';
    const systemSlug = process.env.SYSTEM_KURUM_SLUG || 'mebs';

    let kurumData;
    if (systemKurumId) {
      const doc = await getFirestore().collection(FIRESTORE_COLLECTION).doc(systemKurumId).get();
      if (!doc.exists) return res.status(404).json({ error: 'system_kurum_not_found' });
      kurumData = doc.data() || {};
    } else {
      const query = await getFirestore()
        .collection(FIRESTORE_COLLECTION)
        .where('slug', '==', systemSlug)
        .limit(1)
        .get();
      if (query.empty) return res.status(404).json({ error: 'system_kurum_not_found' });
      kurumData = query.docs[0].data() || {};
    }
    const providerId = String(kurumData[SMS_PROVIDER_FIELD] || '').trim();
    if (!providerId) return res.status(422).json({ error: 'sms_provider_missing' });

    const provider = await getSmsProviderData(providerId);
    const credentials = buildCredentials(kurumData);

    const code = String(Math.floor(100000 + Math.random() * 900000));
    const message = `Mebs Kurum Takip uygulamasi kayit islemi icin dogrulama kodunuz: ${code}`;

    const payload = buildSmsPayload({
      provider: provider.data,
      credentials,
      message,
      recipients: [phone],
      usePersonalized: false,
    });

    const providerRequest = await requestProvider({
      providerData: provider.data,
      credentials,
      payload,
      usePersonalized: false,
    });

    logger.info(
      { requestId, providerId, status: providerRequest.response.status },
      '[sms] registration otp provider response'
    );

    if (!providerRequest.response.ok) {
      return res.status(502).json({ error: 'sms_provider_failed' });
    }

    const businessError = extractProviderError(providerRequest.decoded);
    if (businessError) {
      return res.status(422).json({ error: 'sms_provider_business_error', message: businessError });
    }

    return res.status(200).json({ ok: true, code });
  } catch (err) {
    logger.error({ err, requestId }, '[sms] registration otp error');
    if (err.message === 'sms_provider_missing') return res.status(422).json({ error: 'sms_provider_missing' });
    if (err.message === 'sms_provider_not_found') return res.status(404).json({ error: 'sms_provider_not_found' });
    return res.status(500).json({ error: 'registration_otp_failed', detail: err.message });
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
      const timeZone = resolveTimeZone(kurumData);
      const today = getDatePartsInTimeZone(now, timeZone);
      const result = { kurumId: kurumDoc.id, sent: 0, skipped: 0, total: 0 };
      const skipReasons = {};

      if (!providerId) {
        skipReasons.smsProvider = 1;
        results.push({ ...result, reason: 'sms_provider_missing', skipReasons });
        continue;
      }

      const settings = asMap(asMap(kurumData.settings).messageSettings);
      const birthday = asMap(settings.birthday);
      if (birthday.enabled !== true) {
        skipReasons.birthdayDisabled = 1;
        results.push({ ...result, reason: 'birthday_disabled', skipReasons });
        continue;
      }

      const sendTimeMinutes = Number(birthday.sendTimeMinutes ?? 9 * 60);
      const nowMinutes = minutesOfDayInTimeZone(now, timeZone);
      if (Math.abs(nowMinutes - sendTimeMinutes) > 15) {
        skipReasons.outOfWindow = 1;
        results.push({ ...result, reason: 'out_of_send_window', skipReasons });
        continue;
      }

      const provider = await getSmsProviderData(providerId);
      const credentials = buildCredentials(kurumData);
      const studentsSnap = await kurumDoc.ref.collection('danisanlar').get();
      result.total = studentsSnap.size;

      for (const studentDoc of studentsSnap.docs) {
        const student = studentDoc.data() || {};
        const birth = parseBirthDate(student.dogumtarihi, timeZone);
        if (!birth || birth.month !== today.month || birth.day !== today.day) {
          result.skipped += 1;
          skipReasons.notBirthday = (skipReasons.notBirthday || 0) + 1;
          continue;
        }

        const sentKey = dateKeyInTimeZone(now, timeZone);
        if (String(student.birthdaySmsLastSentDate || '') === sentKey) {
          result.skipped += 1;
          skipReasons.alreadySentToday = (skipReasons.alreadySentToday || 0) + 1;
          continue;
        }

        const phone = normalizePhone(student.telefon || student.ogrencitel || '');
        if (!phone) {
          result.skipped += 1;
          skipReasons.phoneMissing = (skipReasons.phoneMissing || 0) + 1;
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
          result.sent += 1;
          await studentDoc.ref.set(
            {
              birthdaySmsLastSentDate: sentKey,
              birthdaySmsLastSentAt: new Date()
            },
            { merge: true }
          );
        } else {
          result.skipped += 1;
          skipReasons.providerError = (skipReasons.providerError || 0) + 1;
        }
      }

      results.push({ ...result, skipReasons });
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

function parseIsoDate(value) {
  if (!value) return null;
  const parsed = new Date(value);
  if (Number.isNaN(parsed.getTime())) return null;
  return parsed;
}

function toDateKey(date) {
  const year = date.getFullYear().toString().padStart(4, '0');
  const month = String(date.getMonth() + 1).padStart(2, '0');
  const day = String(date.getDate()).padStart(2, '0');
  return `${year}-${month}-${day}`;
}

function parseTimeOfDay(value) {
  const parts = String(value || '').split(':');
  if (parts.length !== 2) return null;
  const hour = Number(parts[0]);
  const minute = Number(parts[1]);
  if (!Number.isFinite(hour) || !Number.isFinite(minute)) return null;
  if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
  return { hour, minute };
}

function withDayAndTime(day, hour, minute) {
  return new Date(day.getFullYear(), day.getMonth(), day.getDate(), hour, minute, 0, 0);
}

function overlaps(leftStart, leftEnd, rightStart, rightEnd) {
  return leftStart < rightEnd && leftEnd > rightStart;
}

function asDate(value) {
  if (!value) return null;
  if (value instanceof Date) return Number.isNaN(value.getTime()) ? null : value;
  if (value?.toDate) {
    const converted = value.toDate();
    return converted instanceof Date && !Number.isNaN(converted.getTime()) ? converted : null;
  }
  const parsed = new Date(value);
  return Number.isNaN(parsed.getTime()) ? null : parsed;
}

function buildLockIds({ orgId, staffId, startTime, endTime, stepMinutes }) {
  const safeStep = Number.isFinite(stepMinutes) && stepMinutes > 0 ? stepMinutes : 15;
  const lockIds = [];
  for (let cursor = new Date(startTime); cursor < endTime; ) {
    const staffPart = String(staffId || 'global').trim() || 'global';
    lockIds.push(`${orgId}_${staffPart}_${cursor.toISOString()}`);
    cursor = new Date(cursor.getTime() + safeStep * 60000);
  }
  return lockIds;
}

app.post('/booking/availability', async (req, res) => {
  const body = req.body || {};
  const orgId = String(body.orgId || '').trim();
  const serviceId = String(body.serviceId || '').trim();
  const date = parseIsoDate(body.date);
  const staffId = String(body.staffId || '').trim() || null;
  const mekanId = String(body.mekanId || '').trim() || null;
  const mekanIds = Array.isArray(body.mekanIds)
    ? body.mekanIds
        .map((value) => String(value || '').trim())
        .filter((value) => value)
    : [];
  const targetMekanIds = mekanIds.length > 0
    ? Array.from(new Set(mekanIds))
    : (mekanId ? [mekanId] : []);

  if (!orgId || !serviceId || !date) {
    return res.status(400).json({ ok: false, error: 'invalid_request' });
  }

  try {
    const db = getFirestore();
    const orgData = await resolveOrgData(db, orgId);
    if (!orgData) {
      return res.status(404).json({ ok: false, error: 'org_not_found' });
    }

    const { ref: orgRef, bookingEnabled, settings } = orgData;
    if (!bookingEnabled || settings.enabled === false) {
      return res.status(200).json({ ok: true, slots: [] });
    }

    const serviceRef = orgRef.collection(BOOKING_SERVICES_SUBCOLLECTION).doc(serviceId);
    const serviceSnap = await serviceRef.get();
    if (!serviceSnap.exists) {
      return res.status(404).json({ ok: false, error: 'service_not_found' });
    }
    const service = serviceSnap.data() || {};
    if (service.active === false) {
      return res.status(200).json({ ok: true, slots: [] });
    }

    const durationMinutes = Number(service.durationMinutes || 30);
    const slotMinutes = Number(settings.slotMinutes || 15);
    const minHoursBefore = Number(settings.minHoursBefore || 2);
    const allowSameDay = settings.allowSameDay !== false;
    const workingHours = orgData.workingHours;
    const closedDates = (workingHours.closedDates || []).map((value) => String(value));
    const dayKey = toDateKey(date);

    if (closedDates.includes(dayKey)) {
      return res.status(200).json({ ok: true, slots: [] });
    }

    const weekday = date.getDay() === 0 ? 7 : date.getDay();
    const dayConfig = asMap(workingHours[String(weekday)]);
    if (dayConfig.isOpen === false) {
      return res.status(200).json({ ok: true, slots: [] });
    }

    const windows = Array.isArray(dayConfig.windows) ? dayConfig.windows : [];
    if (windows.length === 0) {
      return res.status(200).json({ ok: true, slots: [] });
    }

    const now = new Date();
    const minAllowed = new Date(now.getTime() + minHoursBefore * 3600000);
    if (!allowSameDay && toDateKey(now) === dayKey) {
      return res.status(200).json({ ok: true, slots: [] });
    }

    const dayStart = new Date(date.getFullYear(), date.getMonth(), date.getDate(), 0, 0, 0, 0);
    const dayEnd = new Date(dayStart.getTime() + 24 * 3600000);

    const rezervasyonlarSnap = await db
      .collection('kurumlar')
      .doc(orgId)
      .collection('rezervasyonlar')
      .where('date', '>=', dayStart)
      .where('date', '<', dayEnd)
      .get();

    const occupiedByMekan = new Map();
    const staffOccupied = [];
    const globalOccupied = [];

    for (const doc of rezervasyonlarSnap.docs) {
      const item = doc.data() || {};
      const status = String(item.status || '').trim();
      if (status === 'cancelled' || status === 'iptal') continue;

      const startMin = Number(item.startMinutes || 0);
      const endMin = Number(item.endMinutes || 0);
      if (!(endMin > startMin)) continue;

      const interval = {
        startTime: new Date(dayStart.getTime() + startMin * 60000),
        endTime: new Date(dayStart.getTime() + endMin * 60000),
      };
      if (!(interval.endTime > interval.startTime)) continue;

      const itemLocationId = String(item.locationId || '').trim();
      if (itemLocationId) {
        const list = occupiedByMekan.get(itemLocationId) || [];
        list.push(interval);
        occupiedByMekan.set(itemLocationId, list);
      } else {
        // Konumu olmayan bloklar/rezervasyonlar tüm mekanları etkiler.
        globalOccupied.push(interval);
      }

      const assignedUserId = String(item.assignedUserId || '').trim();
      if (staffId && assignedUserId === staffId) {
        staffOccupied.push(interval);
      }
    }

    const conflicts = (intervals, start, end) =>
      intervals.some((entry) => overlaps(start, end, entry.startTime, entry.endTime));

    const slots = [];
    for (const rawWindow of windows) {
      const window = asMap(rawWindow);
      const startParts = parseTimeOfDay(window.start);
      const endParts = parseTimeOfDay(window.end);
      if (!startParts || !endParts) continue;

      const windowStart = withDayAndTime(date, startParts.hour, startParts.minute);
      const windowEnd = withDayAndTime(date, endParts.hour, endParts.minute);
      if (!(windowEnd > windowStart)) continue;

      for (let cursor = new Date(windowStart); ; ) {
        const slotEnd = new Date(cursor.getTime() + durationMinutes * 60000);
        if (slotEnd > windowEnd) break;
        if (cursor < minAllowed) {
          cursor = new Date(cursor.getTime() + slotMinutes * 60000);
          continue;
        }

        if (staffId && conflicts(staffOccupied, cursor, slotEnd)) {
          cursor = new Date(cursor.getTime() + slotMinutes * 60000);
          continue;
        }

        if (targetMekanIds.length > 0) {
          let selectedMekanId = null;
          for (const currentMekanId of targetMekanIds) {
            const mekanOccupied = occupiedByMekan.get(currentMekanId) || [];
            const busy =
              conflicts(globalOccupied, cursor, slotEnd) ||
              conflicts(mekanOccupied, cursor, slotEnd);
            if (!busy) {
              selectedMekanId = currentMekanId;
              break;
            }
          }
          if (selectedMekanId) {
            slots.push({
              start: cursor.toISOString(),
              end: slotEnd.toISOString(),
              mekanId: selectedMekanId,
            });
          }
        } else {
          // Mekan kısıtı yoksa global çakışmaları baz al.
          if (!conflicts(globalOccupied, cursor, slotEnd)) {
            slots.push({
              start: cursor.toISOString(),
              end: slotEnd.toISOString(),
            });
          }
        }
        cursor = new Date(cursor.getTime() + slotMinutes * 60000);
      }
    }

    return res.status(200).json({ ok: true, slots });
  } catch (err) {
    logger.error({ err }, '[booking] availability error');
    return res.status(500).json({ ok: false, error: 'availability_failed' });
  }
});

app.post('/booking/create', async (req, res) => {
  const body = req.body || {};
  const orgId = String(body.orgId || '').trim();
  const customerId = String(body.customerId || '').trim();
  const customerName = String(body.customerName || '').trim();
  const customerPhone = normalizePhone(body.customerPhone || '');
  const serviceId = String(body.serviceId || '').trim();
  const serviceName = String(body.serviceName || '').trim();
  const source = String(body.source || 'online').trim() || 'online';
  const notes = String(body.notes || '').trim();
  const staffId = String(body.staffId || '').trim();
  const staffName = String(body.staffName || '').trim();
  const mekanId = String(body.mekanId || '').trim();
  const paketId = String(body.paketId || '').trim();
  const paketAdi = String(body.paketAdi || '').trim();
  const paketOperationId = String(body.paketOperationId || '').trim();

  const bookingDate = parseIsoDate(body.bookingDate);
  const startTime = parseIsoDate(body.startTime);
  const endTime = parseIsoDate(body.endTime);

  if (
    !orgId ||
    !customerId ||
    !customerName ||
    !customerPhone ||
    !serviceId ||
    !serviceName ||
    !bookingDate ||
    !startTime ||
    !endTime
  ) {
    return res.status(400).json({ ok: false, error: 'invalid_request' });
  }
  if (!(endTime > startTime)) {
    return res.status(400).json({ ok: false, error: 'invalid_time_range' });
  }

  try {
    const db = getFirestore();
    const orgData = await resolveOrgData(db, orgId);
    if (!orgData) {
      return res.status(404).json({ ok: false, error: 'org_not_found' });
    }

    const { bookingEnabled, settings } = orgData;
    if (!bookingEnabled || settings.enabled === false) {
      return res.status(403).json({ ok: false, error: 'booking_closed' });
    }

    const minHoursBefore = Number(settings.minHoursBefore || 2);
    const minAllowed = new Date(Date.now() + minHoursBefore * 3600000);
    if (startTime < minAllowed) {
      return res.status(422).json({ ok: false, error: 'too_close_to_now' });
    }

    const maxDaysAhead = Number(settings.maxDaysAhead || 30);
    const maxAllowed = new Date();
    maxAllowed.setDate(maxAllowed.getDate() + maxDaysAhead);
    if (startTime > maxAllowed) {
      return res.status(422).json({ ok: false, error: 'too_far_in_future' });
    }

    const stepMinutes = Number(settings.slotMinutes || 15);
    const lockIds = buildLockIds({ orgId, staffId, startTime, endTime, stepMinutes });

    // Mekan adını Firestore'dan çek (locationName için)
    let locationName = '';
    if (mekanId) {
      try {
        const mekanDoc = await db
          .collection('kurumlar').doc(orgId)
          .collection('mekanlar').doc(mekanId)
          .get();
        if (mekanDoc.exists) {
          locationName = String((mekanDoc.data() || {}).adi || '').trim();
        }
      } catch (_) {}
    }

    // startMinutes / endMinutes: gün başından itibaren dakika (timezone-agnostic)
    const dayStart = new Date(
      bookingDate.getFullYear(),
      bookingDate.getMonth(),
      bookingDate.getDate(),
      0, 0, 0, 0
    );
    const dayEnd = new Date(dayStart.getTime() + 24 * 3600000);
    const startMinutes = Math.round((startTime.getTime() - bookingDate.getTime()) / 60000);
    const endMinutes = Math.round((endTime.getTime() - bookingDate.getTime()) / 60000);

    const rezervasyonRef = db
      .collection('kurumlar')
      .doc(orgId)
      .collection('rezervasyonlar')
      .doc();

    await db.runTransaction(async (tx) => {
      // Aynı gün içindeki rezervasyonları oku ve çakışma kontrolü yap.
      const overlapQuery = db
        .collection('kurumlar')
        .doc(orgId)
        .collection('rezervasyonlar')
        .where('date', '>=', dayStart)
        .where('date', '<', dayEnd);

      const overlapSnap = await tx.get(overlapQuery);
      const overlapping = overlapSnap.docs.some((doc) => {
        const item = doc.data() || {};
        const status = String(item.status || '');
        if (status === 'cancelled' || status === 'iptal') return false;
        // Mekan kontrolü: farklı mekanlara ait rezervasyonlar çakışma oluşturmaz
        const itemLocationId = String(item.locationId || '').trim();
        const requestedMekanId = String(mekanId || '').trim();
        if (itemLocationId && requestedMekanId && itemLocationId !== requestedMekanId) return false;
        if (staffId && String(item.assignedUserId || '') !== staffId) return false;
        const left = Number(item.startMinutes || 0);
        const right = Number(item.endMinutes || 0);
        if (right <= left) return false;
        return startMinutes < right && endMinutes > left;
      });
      if (overlapping) {
        const err = new Error('slot_unavailable');
        err.code = 'slot_unavailable';
        throw err;
      }

      const now = new Date();
      for (const lockId of lockIds) {
        const lockRef = db.collection(BOOKING_LOCKS_COLLECTION).doc(lockId);
        const lockSnap = await tx.get(lockRef);
        if (lockSnap.exists) {
          // Süresi dolmuş kilitleri yoksay
          const lockData = lockSnap.data() || {};
          const expiresAt = lockData.expiresAt?.toDate?.() ?? new Date(0);
          if (expiresAt > now) {
            const err = new Error('slot_locked');
            err.code = 'slot_locked';
            throw err;
          }
        }
        tx.set(lockRef, {
          orgId,
          staffId: staffId || null,
          lockStart: startTime,
          lockEnd: endTime,
          bookingId: rezervasyonRef.id,
          createdAt: new Date(),
          expiresAt: new Date(startTime.getTime() + 2 * 3600000)
        });
      }

      const docData = {
        date: startTime,
        startMinutes,
        endMinutes,
        customerId,
        customerName,
        customerShortName: buildShortName(customerName),
        customerPhone,
        operationName: serviceName,
        operationId: serviceId,
        status: 'online',
        source,
        olusturan: 'Online',
        createdByName: 'Online',
        createdAt: new Date(),
      };
      if (notes) docData.aciklama = notes;
      if (staffId) docData.assignedUserId = staffId;
      if (staffName) docData.assignedUserName = staffName;
      if (mekanId) docData.locationId = mekanId;
      if (locationName) docData.locationName = locationName;
      if (paketId) docData.paketId = paketId;
      if (paketAdi) docData.paketAdi = paketAdi;
      if (paketOperationId) docData.paketOperationId = paketOperationId;

      tx.set(rezervasyonRef, docData);
    });

    // Kilitleri temizle — rezervasyon oluşturuldu, artık gerek yok (fire-and-forget).
    lockIds.forEach((lockId) => {
      db.collection(BOOKING_LOCKS_COLLECTION).doc(lockId).delete().catch(() => {});
    });

    // Yöneticilere bildirim gönder (fire-and-forget, hata rezervasyonu etkilemez).
    logger.info(
      {
        orgId,
        bookingId: rezervasyonRef.id,
        customerId,
        staffId: staffId || null,
      },
      '[booking] triggering notifications'
    );
    sendBookingNotificationToManagers({
      db,
      orgId,
      bookingId: rezervasyonRef.id,
      customerId,
      customerName,
      startTime,
      assignedUserId: staffId || '',
      assignedUserName: staffName || '',
    }).catch((e) => logger.warn({ err: e }, '[booking] notification error'));

    return res.status(200).json({ ok: true, bookingId: rezervasyonRef.id });
  } catch (err) {
    logger.error({ err }, '[booking] create error');
    if (err.code === 'slot_unavailable' || err.code === 'slot_locked') {
      return res.status(409).json({ ok: false, error: 'slot_not_available' });
    }
    return res.status(500).json({
      ok: false,
      error: 'booking_create_failed',
      detail: String(err?.message || 'unknown_error')
    });
  }
});

// Flutter fallback path'inden çağrılır: rezervasyon doğrudan Firestore'a yazılmış,
// sadece bildirim göndermesi isteniyor.
app.post('/notify-managers', async (req, res) => {
  const body = req.body || {};
  const orgId = String(body.orgId || '').trim();
  const customerName = String(body.customerName || '').trim();
  const customerId = String(body.customerId || '').trim();
  const bookingId = String(body.bookingId || '').trim();
  const assignedUserId = String(body.assignedUserId || '').trim();
  const assignedUserName = String(body.assignedUserName || '').trim();
  const startTimeRaw = body.startTime;

  if (!orgId || !customerName) {
    return res.status(400).json({ ok: false, error: 'invalid_request' });
  }

  const startTime = startTimeRaw ? new Date(startTimeRaw) : new Date();

  try {
    const db = getFirestore();
    await sendBookingNotificationToManagers({
      db,
      orgId,
      bookingId,
      customerId,
      customerName,
      startTime,
      assignedUserId,
      assignedUserName,
    });
    return res.status(200).json({ ok: true });
  } catch (err) {
    logger.error({ err }, '[notify-managers] error');
    return res.status(500).json({ ok: false, error: 'notification_failed' });
  }
});

// Flutter admin uygulaması tarafından çağrılır: Firestore bildirimi yazıldıktan sonra
// FCM push bildirimi gönder.
app.post('/send-fcm', async (req, res) => {
  const body = req.body || {};
  const userId = String(body.userId || '').trim();
  const title = String(body.title || '').trim();
  const fcmBody = String(body.body || '').trim();
  if (!userId) return res.status(400).json({ ok: false, error: 'userId_required' });
  const result = await sendFcmToUser({ userId, title, body: fcmBody });
  if (result?.ok) {
    return res.status(200).json({ ok: true, result });
  }
  // Tanı için 200 dönmeye devam ediyoruz; client logları reason bilgisini alır.
  return res.status(200).json({ ok: false, result });
});

async function sendBookingNotificationToManagers({
  db,
  orgId,
  bookingId,
  customerId,
  customerName,
  startTime,
  assignedUserId = '',
  assignedUserName = '',
}) {
  const pad = (n) => String(n).padStart(2, '0');
  const dateStr = `${pad(startTime.getDate())}.${pad(startTime.getMonth() + 1)}.${startTime.getFullYear()} ${pad(startTime.getHours())}:${pad(startTime.getMinutes())}`;

  const usersSnap = await db
    .collection('kullanicilar')
    .where('kurumkodu', '==', orgId)
    .get();

  const veri = {
    rezervasyonId: bookingId,
    kurumkodu: orgId,
    ...(customerId ? { danisanId: customerId } : {}),
  };
  const baslik = 'Yeni Online Rezervasyon';
  const mesaj = `${customerName} — ${dateStr}`;
  const assignedLabel = String(assignedUserName || assignedUserId || '').trim();
  const writes = [];
  const notifiedUserIds = new Set();

  for (const doc of usersSnap.docs) {
    const data = doc.data() || {};
    const rol = String(data.rol || '').trim().toUpperCase();
    if (rol !== 'YÖNETİCİ') continue;
    if (!hasExplicitPermission(data, PERMISSION_RECEIVE_ALL_RESERVATION_NOTIFICATIONS)) {
      continue;
    }

    // Bildirim çanı user.data['uid'] = doc.id olarak override edildiğinden doc.id kullan.
    writes.push(
      db.collection('kullanicilar').doc(doc.id).collection('bildirimler').add({
        baslik,
        mesaj,
        tip: 'rezervasyon',
        okundu: false,
        tarih: new Date(),
        veri,
      })
    );

    // FCM push bildirimi gönder (token yoksa sessizce atlanır).
    writes.push(sendFcmToUser({ userId: doc.id, title: baslik, body: mesaj }));
    notifiedUserIds.add(doc.id);
  }

  const trimmedAssignedUserId = String(assignedUserId || '').trim();
  if (trimmedAssignedUserId && !notifiedUserIds.has(trimmedAssignedUserId)) {
    const assignmentTitle = 'Yeni İşlem Ataması';
    const assignmentBody = `${customerName} için ${dateStr} tarihli online randevu ${
      assignedLabel || trimmedAssignedUserId
    } kişisine atandı.`;
    writes.push(
      db.collection('kullanicilar').doc(trimmedAssignedUserId).collection('bildirimler').add({
        baslik: assignmentTitle,
        mesaj: assignmentBody,
        tip: 'atama',
        okundu: false,
        tarih: new Date(),
        veri,
      })
    );
    writes.push(
      sendFcmToUser({
        userId: trimmedAssignedUserId,
        title: assignmentTitle,
        body: assignmentBody,
      })
    );
    logger.info(
      { orgId, bookingId, assignedUserId: trimmedAssignedUserId },
      '[booking] assignment notification queued'
    );
  }

  await Promise.all(writes);
}

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
