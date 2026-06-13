#!/usr/bin/env node
import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import { z } from 'zod';
import { writeCredentials, credentialsExist } from './credentials.js';
import { fetchHotelierData, fetchBookingsForRange, evaluateBookings } from './scraper.js';
import { writeDailyBrief, getBriefsDir } from './brief-writer.js';

const server = new McpServer({
  name: 'hotelier-mcp',
  version: '1.0.0',
});

// ─── Tool: set credentials ────────────────────────────────────────────────────
server.tool(
  'hotelier_set_credentials',
  'Store Little Hotelier login credentials in a secure local file (~/.mactaverne/.hotelier-creds, chmod 600). Run this once before using any other hotelier tool.',
  {
    username: z.string().describe('Little Hotelier email / username'),
    password: z.string().describe('Little Hotelier password'),
  },
  async ({ username, password }) => {
    const path = writeCredentials(username, password);
    return {
      content: [{ type: 'text', text: `Credentials saved to ${path} (chmod 600). You can now use the other hotelier tools.` }],
    };
  }
);

// ─── Tool: fetch morning brief ────────────────────────────────────────────────
server.tool(
  'hotelier_fetch_morning_brief',
  'Log into Little Hotelier, scrape today\'s arrivals, departures, occupancy stats, and upcoming bookings. Returns structured data and writes a markdown brief to ~/MacTaverne/bud/briefs/YYYY-MM-DD.md.',
  {
    forecast_days: z.number().int().min(1).max(30).optional().default(7)
      .describe('How many days ahead to include in the upcoming bookings list'),
    write_brief: z.boolean().optional().default(true)
      .describe('If true, write the markdown brief to the Bud briefs folder'),
  },
  async ({ forecast_days, write_brief }) => {
    if (!credentialsExist()) {
      return {
        content: [{ type: 'text', text: 'No credentials found. Call hotelier_set_credentials first.' }],
        isError: true,
      };
    }

    let data;
    try {
      data = await fetchHotelierData({ forecastDays: forecast_days });
    } catch (err) {
      return {
        content: [{ type: 'text', text: `Failed to fetch data from Little Hotelier: ${err.message}` }],
        isError: true,
      };
    }

    const evaluation = evaluateBookings(data);
    let briefPath = null;

    if (write_brief) {
      try {
        const result = writeDailyBrief(data, evaluation);
        briefPath = result.filepath;
      } catch (err) {
        // Non-fatal — still return data even if file write fails
        evaluation.flags.push({ type: 'warning', message: `Could not write brief file: ${err.message}` });
      }
    }

    const summary = [
      `Date: ${data.date}`,
      `Arrivals: ${data.arrivals.length}`,
      `Departures: ${data.departures.length}`,
      `Upcoming (${forecast_days}d): ${data.upcoming.length}`,
      '',
      evaluation.summary,
      '',
      briefPath ? `Brief written to: ${briefPath}` : '',
    ].filter(l => l !== undefined).join('\n');

    return {
      content: [
        { type: 'text', text: summary },
        { type: 'text', text: '\n\n**Raw data:**\n```json\n' + JSON.stringify(data, null, 2) + '\n```' },
      ],
    };
  }
);

// ─── Tool: get bookings for date range ────────────────────────────────────────
server.tool(
  'hotelier_get_bookings',
  'Fetch bookings from Little Hotelier for a specific date range.',
  {
    start_date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).describe('Start date (YYYY-MM-DD)'),
    end_date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).describe('End date (YYYY-MM-DD)'),
  },
  async ({ start_date, end_date }) => {
    if (!credentialsExist()) {
      return {
        content: [{ type: 'text', text: 'No credentials found. Call hotelier_set_credentials first.' }],
        isError: true,
      };
    }

    let result;
    try {
      result = await fetchBookingsForRange(start_date, end_date);
    } catch (err) {
      return {
        content: [{ type: 'text', text: `Failed to fetch bookings: ${err.message}` }],
        isError: true,
      };
    }

    return {
      content: [{
        type: 'text',
        text: `Found ${result.count} booking(s) from ${start_date} to ${end_date}:\n\n\`\`\`json\n${JSON.stringify(result, null, 2)}\n\`\`\``,
      }],
    };
  }
);

// ─── Tool: evaluate bookings ──────────────────────────────────────────────────
server.tool(
  'hotelier_evaluate_bookings',
  'Evaluate booking data for flags: pending confirmations, unpaid balances, special requests, overbookings. Pass the raw data from hotelier_fetch_morning_brief.',
  {
    data: z.object({
      date: z.string(),
      arrivals: z.array(z.object({
        guest: z.string(),
        room: z.string().optional(),
        checkIn: z.string().optional(),
        status: z.string().optional(),
        notes: z.string().optional(),
      })),
      departures: z.array(z.object({
        guest: z.string(),
        room: z.string().optional(),
        checkOut: z.string().optional(),
        status: z.string().optional(),
      })),
      upcoming: z.array(z.record(z.string())),
      occupancy: z.array(z.record(z.string())).optional().default([]),
      scrapedAt: z.string().optional(),
    }).describe('Hotelier data object returned by hotelier_fetch_morning_brief'),
  },
  async ({ data }) => {
    const evaluation = evaluateBookings(data);
    return {
      content: [{
        type: 'text',
        text: `**Evaluation summary:** ${evaluation.summary}\n\n**Flags (${evaluation.flags.length}):**\n${evaluation.flags.map(f => `- [${f.type.toUpperCase()}] ${f.message}`).join('\n') || 'None'}`,
      }],
    };
  }
);

// ─── Tool: write daily brief ──────────────────────────────────────────────────
server.tool(
  'hotelier_write_daily_brief',
  'Format and write the daily morning brief markdown file to ~/MacTaverne/bud/briefs/YYYY-MM-DD.md.',
  {
    data: z.object({
      date: z.string(),
      arrivals: z.array(z.record(z.string())),
      departures: z.array(z.record(z.string())),
      upcoming: z.array(z.record(z.string())),
      occupancy: z.array(z.record(z.string())).optional().default([]),
      scrapedAt: z.string().optional().default(new Date().toISOString()),
    }).describe('Hotelier data to format'),
    flags: z.array(z.object({
      type: z.string(),
      message: z.string(),
    })).optional().default([]).describe('Evaluation flags to include in the brief'),
  },
  async ({ data, flags }) => {
    try {
      const { filepath, content } = writeDailyBrief(data, { flags });
      return {
        content: [{ type: 'text', text: `Brief written to: ${filepath}\n\n---\n${content}` }],
      };
    } catch (err) {
      return {
        content: [{ type: 'text', text: `Failed to write brief: ${err.message}` }],
        isError: true,
      };
    }
  }
);

// ─── Tool: status check ───────────────────────────────────────────────────────
server.tool(
  'hotelier_status',
  'Check if credentials are configured and show the briefs output directory.',
  {},
  async () => {
    const hasCreds = credentialsExist();
    const briefsDir = getBriefsDir();
    return {
      content: [{
        type: 'text',
        text: [
          `Credentials configured: ${hasCreds ? 'Yes' : 'No — run hotelier_set_credentials'}`,
          `Briefs directory: ${briefsDir}`,
        ].join('\n'),
      }],
    };
  }
);

// ─── Start ────────────────────────────────────────────────────────────────────
const transport = new StdioServerTransport();
await server.connect(transport);
