import { readFileSync, writeFileSync, mkdirSync, chmodSync, existsSync } from 'fs';
import { join } from 'path';
import { homedir } from 'os';

const CREDS_DIR = join(homedir(), '.mactaverne');
const CREDS_FILE = join(CREDS_DIR, '.hotelier-creds');

export function readCredentials() {
  if (!existsSync(CREDS_FILE)) {
    throw new Error(
      `No credentials found. Call hotelier_set_credentials first.\nExpected: ${CREDS_FILE}`
    );
  }
  try {
    return JSON.parse(readFileSync(CREDS_FILE, 'utf8'));
  } catch {
    throw new Error(`Credentials file is corrupted. Re-run hotelier_set_credentials.`);
  }
}

export function writeCredentials(username, password) {
  if (!existsSync(CREDS_DIR)) {
    mkdirSync(CREDS_DIR, { recursive: true, mode: 0o700 });
  }
  writeFileSync(CREDS_FILE, JSON.stringify({ username, password }, null, 2), 'utf8');
  chmodSync(CREDS_FILE, 0o600);
  return CREDS_FILE;
}

export function credentialsExist() {
  return existsSync(CREDS_FILE);
}
