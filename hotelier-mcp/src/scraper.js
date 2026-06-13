import { chromium } from 'playwright';
import { readCredentials } from './credentials.js';

const LOGIN_URL = 'https://app.littlehotelier.com/hotelier/signin';

async function login(page, creds) {
  await page.goto(LOGIN_URL, { waitUntil: 'domcontentloaded', timeout: 30000 });

  // Little Hotelier login form
  await page.waitForSelector('input[type="email"], input[name="email"], #email, input[name="username"]', {
    timeout: 10000,
  });

  await page.fill(
    'input[type="email"], input[name="email"], #email, input[name="username"]',
    creds.username
  );
  await page.fill(
    'input[type="password"], input[name="password"], #password',
    creds.password
  );

  await Promise.all([
    page.waitForNavigation({ waitUntil: 'networkidle', timeout: 20000 }),
    page.click('button[type="submit"], input[type="submit"], .sign-in-btn, [data-testid="login-button"]'),
  ]);

  // Detect login failure
  const url = page.url();
  if (url.includes('signin') || url.includes('login')) {
    const errEl = await page.$('.error, .alert-danger, [class*="error"], [class*="alert"]');
    const errText = errEl ? await errEl.innerText() : 'Unknown login error';
    throw new Error(`Little Hotelier login failed: ${errText.trim()}`);
  }
}

async function scrapeArrivalsAndDepartures(page, targetDate) {
  // Navigate to front desk / arrivals view
  // Little Hotelier typically has a front desk or arrivals section
  const arrivals = [];
  const departures = [];

  try {
    // Try to find arrivals section — LH uses "Arrivals" tab in front desk
    const arrivalsNav = await page.$('a[href*="arrival"], a[href*="front-desk"], [data-section="arrivals"]');
    if (arrivalsNav) await arrivalsNav.click();

    await page.waitForTimeout(2000);

    // Scrape arrival rows — each booking row typically has guest name, room, time
    const arrivalRows = await page.$$eval(
      '[class*="arrival"] [class*="row"], [class*="arrival"] tr, [data-type="arrival"]',
      rows => rows.map(r => ({
        guest: r.querySelector('[class*="guest"], [class*="name"], td:nth-child(1)')?.innerText?.trim() || '',
        room: r.querySelector('[class*="room"], td:nth-child(2)')?.innerText?.trim() || '',
        checkIn: r.querySelector('[class*="time"], [class*="date"], td:nth-child(3)')?.innerText?.trim() || '',
        status: r.querySelector('[class*="status"], td:last-child')?.innerText?.trim() || '',
        notes: r.querySelector('[class*="note"], [class*="special"]')?.innerText?.trim() || '',
      }))
    );
    arrivals.push(...arrivalRows.filter(r => r.guest));
  } catch {
    // Arrivals section not found at this path — will try alternate route
  }

  try {
    const departuresNav = await page.$('a[href*="departure"], [data-section="departures"]');
    if (departuresNav) await departuresNav.click();

    await page.waitForTimeout(2000);

    const departureRows = await page.$$eval(
      '[class*="departure"] [class*="row"], [class*="departure"] tr, [data-type="departure"]',
      rows => rows.map(r => ({
        guest: r.querySelector('[class*="guest"], [class*="name"], td:nth-child(1)')?.innerText?.trim() || '',
        room: r.querySelector('[class*="room"], td:nth-child(2)')?.innerText?.trim() || '',
        checkOut: r.querySelector('[class*="time"], [class*="date"], td:nth-child(3)')?.innerText?.trim() || '',
        status: r.querySelector('[class*="status"], td:last-child')?.innerText?.trim() || '',
      }))
    );
    departures.push(...departureRows.filter(r => r.guest));
  } catch {
    // Departures section not found
  }

  return { arrivals, departures };
}

async function scrapeOccupancy(page) {
  try {
    // Dashboard or occupancy widget
    const stats = await page.$$eval(
      '[class*="occupancy"], [class*="stat"], [class*="kpi"], [class*="metric"]',
      els => els.slice(0, 6).map(el => ({
        label: el.querySelector('[class*="label"], [class*="title"]')?.innerText?.trim() || el.innerText.split('\n')[0]?.trim(),
        value: el.querySelector('[class*="value"], [class*="number"]')?.innerText?.trim() || el.innerText.split('\n')[1]?.trim(),
      }))
    );
    return stats.filter(s => s.label && s.value);
  } catch {
    return [];
  }
}

async function scrapeUpcomingBookings(page, days = 7) {
  const bookings = [];
  try {
    // Navigate to reservations list filtered for next N days
    const reservationsLink = await page.$('a[href*="reservation"], a[href*="booking"]');
    if (reservationsLink) {
      await reservationsLink.click();
      await page.waitForTimeout(2000);
    }

    const rows = await page.$$eval(
      'table tbody tr, [class*="reservation"] [class*="row"], [class*="booking"] [class*="row"]',
      (rows, maxRows) => rows.slice(0, maxRows).map(r => {
        const cells = r.querySelectorAll('td');
        return {
          id: cells[0]?.innerText?.trim() || '',
          guest: cells[1]?.innerText?.trim() || r.querySelector('[class*="guest"], [class*="name"]')?.innerText?.trim() || '',
          checkIn: cells[2]?.innerText?.trim() || '',
          checkOut: cells[3]?.innerText?.trim() || '',
          room: cells[4]?.innerText?.trim() || r.querySelector('[class*="room"]')?.innerText?.trim() || '',
          status: cells[5]?.innerText?.trim() || r.querySelector('[class*="status"]')?.innerText?.trim() || '',
          amount: cells[6]?.innerText?.trim() || r.querySelector('[class*="amount"], [class*="total"]')?.innerText?.trim() || '',
        };
      }),
      50
    );
    bookings.push(...rows.filter(r => r.guest));
  } catch {
    // Could not scrape reservations list
  }
  return bookings;
}

export async function fetchHotelierData(options = {}) {
  const creds = readCredentials();
  const browser = await chromium.launch({
    headless: true,
    args: ['--no-sandbox', '--disable-setuid-sandbox'],
  });

  const context = await browser.newContext({
    userAgent:
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    viewport: { width: 1440, height: 900 },
  });

  const page = await context.newPage();
  // Suppress noisy console output from the LH app
  page.on('console', () => {});

  try {
    await login(page, creds);

    const today = new Date().toISOString().split('T')[0];
    const [{ arrivals, departures }, occupancyStats, upcomingBookings] = await Promise.all([
      scrapeArrivalsAndDepartures(page, today),
      scrapeOccupancy(page),
      scrapeUpcomingBookings(page, options.forecastDays || 7),
    ]);

    return {
      date: today,
      arrivals,
      departures,
      occupancy: occupancyStats,
      upcoming: upcomingBookings,
      scrapedAt: new Date().toISOString(),
    };
  } finally {
    await browser.close();
  }
}

export async function fetchBookingsForRange(startDate, endDate) {
  const creds = readCredentials();
  const browser = await chromium.launch({ headless: true, args: ['--no-sandbox'] });
  const context = await browser.newContext({
    userAgent:
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    viewport: { width: 1440, height: 900 },
  });
  const page = await context.newPage();

  try {
    await login(page, creds);

    // Navigate to reservations with date filter
    const reservationUrl =
      `${page.url().split('/hotelier')[0]}/hotelier/reservations?start=${startDate}&end=${endDate}`;
    await page.goto(reservationUrl, { waitUntil: 'networkidle', timeout: 20000 });

    const bookings = await page.$$eval(
      'table tbody tr, [class*="reservation"] [class*="row"]',
      rows => rows.map(r => {
        const cells = r.querySelectorAll('td');
        return {
          id: cells[0]?.innerText?.trim() || '',
          guest: cells[1]?.innerText?.trim() || '',
          checkIn: cells[2]?.innerText?.trim() || '',
          checkOut: cells[3]?.innerText?.trim() || '',
          room: cells[4]?.innerText?.trim() || '',
          status: cells[5]?.innerText?.trim() || '',
          amount: cells[6]?.innerText?.trim() || '',
          channel: cells[7]?.innerText?.trim() || '',
        };
      }).filter(r => r.guest)
    );

    return { startDate, endDate, bookings, count: bookings.length };
  } finally {
    await browser.close();
  }
}

export function evaluateBookings(data) {
  const flags = [];

  const { arrivals, departures, upcoming } = data;

  if (arrivals.length === 0 && departures.length === 0) {
    flags.push({ type: 'info', message: 'No arrivals or departures today.' });
  }

  const pendingArrivals = arrivals.filter(a =>
    a.status && (a.status.toLowerCase().includes('pending') || a.status.toLowerCase().includes('unconfirm'))
  );
  if (pendingArrivals.length > 0) {
    flags.push({
      type: 'warning',
      message: `${pendingArrivals.length} arrival(s) with unconfirmed status.`,
      bookings: pendingArrivals,
    });
  }

  const specialRequests = arrivals.filter(a => a.notes && a.notes.length > 0);
  if (specialRequests.length > 0) {
    flags.push({
      type: 'note',
      message: `${specialRequests.length} arrival(s) have special requests.`,
      bookings: specialRequests,
    });
  }

  const unpaidBookings = upcoming.filter(b =>
    b.status && (b.status.toLowerCase().includes('unpaid') || b.status.toLowerCase().includes('balance due'))
  );
  if (unpaidBookings.length > 0) {
    flags.push({
      type: 'alert',
      message: `${unpaidBookings.length} upcoming booking(s) with outstanding balance.`,
      bookings: unpaidBookings,
    });
  }

  return { flags, summary: buildEvalSummary(data, flags) };
}

function buildEvalSummary(data, flags) {
  const lines = [
    `Today: ${data.arrivals.length} arrival(s), ${data.departures.length} departure(s).`,
    `Upcoming (7 days): ${data.upcoming.length} booking(s).`,
  ];
  if (flags.length > 0) {
    lines.push(`Flags: ${flags.map(f => f.message).join(' | ')}`);
  }
  return lines.join(' ');
}
