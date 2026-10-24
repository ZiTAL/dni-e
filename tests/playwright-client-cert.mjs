// SPDX-License-Identifier: GPL-3.0-or-later
// Headless Chromium client-certificate test driven by Playwright.
// Environment: URL, ORIGIN, CLIENT_CERT, CLIENT_KEY, CHROMIUM_PATH.
import { createRequire } from 'node:module';
const require = createRequire(import.meta.url);
const { chromium } = require('playwright');

const url = process.env.URL;
const origin = process.env.ORIGIN;
const certPath = process.env.CLIENT_CERT;
const keyPath = process.env.CLIENT_KEY;
const executablePath = process.env.CHROMIUM_PATH;

if (!url || !origin || !certPath || !keyPath) {
  console.error('missing URL/ORIGIN/CLIENT_CERT/CLIENT_KEY');
  process.exit(2);
}

const browser = await chromium.launch({
  headless: true,
  executablePath: executablePath || undefined,
  args: ['--no-sandbox'],
});

try {
  const context = await browser.newContext({
    ignoreHTTPSErrors: true,
    clientCertificates: [{ origin, certPath, keyPath }],
  });
  const page = await context.newPage();
  const response = await page.goto(url, { waitUntil: 'domcontentloaded' });
  const status = response ? response.status() : 0;
  console.log(`status=${status}`);
  if (status !== 200) {
    process.exit(1);
  }
} finally {
  await browser.close();
}
