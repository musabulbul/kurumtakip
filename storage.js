import { Storage } from '@google-cloud/storage';
import fs from 'fs/promises';
import path from 'path';

let storage;
function getStorage() {
  if (!storage) storage = new Storage();
  return storage;
}

function buildPrefix(sessionId, prefix) {
  const cleanedPrefix = (prefix ?? '').trim().replace(/^\/+|\/+$/g, '');
  if (!cleanedPrefix) {
    return `${sessionId}/`;
  }
  return `${cleanedPrefix}/${sessionId}/`;
}

export async function ensureSessionDir(sessionRoot, sessionId) {
  const localDir = path.join(sessionRoot, sessionId);
  await fs.mkdir(localDir, { recursive: true });
  return localDir;
}

export async function downloadSessionFromGCS(
  bucketName,
  sessionId,
  localDir,
  prefix
) {
  if (!bucketName) return;
  const bucket = getStorage().bucket(bucketName);
  const gcsPrefix = buildPrefix(sessionId, prefix);
  const [files] = await bucket.getFiles({ prefix: gcsPrefix });

  await Promise.all(
    files.map(async (file) => {
      const relative = file.name.slice(gcsPrefix.length);
      if (!relative) return;
      const destPath = path.join(localDir, relative);
      await fs.mkdir(path.dirname(destPath), { recursive: true });
      await file.download({ destination: destPath });
    })
  );
}

async function listLocalFiles(dir) {
  const entries = await fs.readdir(dir, { withFileTypes: true });
  const files = await Promise.all(
    entries.map(async (entry) => {
      const fullPath = path.join(dir, entry.name);
      if (entry.isDirectory()) return listLocalFiles(fullPath);
      return [fullPath];
    })
  );
  return files.flat();
}

export async function uploadSessionToGCS(
  bucketName,
  sessionId,
  localDir,
  prefix
) {
  if (!bucketName) return;
  const bucket = getStorage().bucket(bucketName);
  const files = await listLocalFiles(localDir);
  const gcsPrefix = buildPrefix(sessionId, prefix).replace(/\/$/, '');

  await Promise.all(
    files.map((filePath) => {
      const relative = path.relative(localDir, filePath);
      const destination = path.posix.join(
        gcsPrefix,
        relative.split(path.sep).join('/')
      );
      return bucket.upload(filePath, { destination });
    })
  );
}
