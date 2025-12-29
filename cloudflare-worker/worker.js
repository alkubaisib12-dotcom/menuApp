/**
 * Cloudflare Worker for SweetWeb Email Service
 * Handles order notifications, cancellations, customer confirmations, and report emails via Resend API
 *
 * Deployment:
 * 1) https://dash.cloudflare.com
 * 2) Workers & Pages > Create application > Create Worker
 * 3) Paste this file content
 * 4) Add Secret: RESEND_API_KEY = <your-resend-api-key>
 * 5) Deploy
 */

const FROM_EMAIL = 'SweetWeb <onboarding@resend.dev>';

// CORS headers for Flutter web app
const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type',
};

function jsonResponse(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

function requireEnv(apiKey) {
  if (!apiKey || typeof apiKey !== 'string' || apiKey.trim().length < 10) {
    return jsonResponse({ success: false, error: 'Missing RESEND_API_KEY' }, 500);
  }
  return null;
}

function toNumber(v, fallback = 0) {
  const n = typeof v === 'number' ? v : Number(v);
  return Number.isFinite(n) ? n : fallback;
}

function toArray(v) {
  return Array.isArray(v) ? v : [];
}

function safeText(v, fallback = '') {
  if (v === null || v === undefined) return fallback;
  const s = String(v);
  return s.trim().length ? s : fallback;
}

async function sendViaResend({ apiKey, to, subject, html }) {
  const envErr = requireEnv(apiKey);
  if (envErr) return envErr;

  const toEmail = safeText(to);
  if (!toEmail) return jsonResponse({ success: false, error: 'Missing toEmail' }, 400);

  const subj = safeText(subject, 'SweetWeb Notification');
  const bodyHtml = safeText(html, '<p>Notification</p>');

  const response = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${apiKey}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      from: FROM_EMAIL,
      to: toEmail,
      subject: subj,
      html: bodyHtml,
    }),
  });

  const result = await response.json().catch(() => ({}));

  if (!response.ok) {
    return jsonResponse(
      { success: false, error: result?.message || 'Failed to send email', details: result },
      500
    );
  }

  return jsonResponse({ success: true, messageId: result.id });
}

export default {
  async fetch(request, env) {
    // Handle CORS preflight
    if (request.method === 'OPTIONS') {
      return new Response(null, { headers: corsHeaders });
    }

    if (request.method !== 'POST') {
      return new Response('Method not allowed', { status: 405, headers: corsHeaders });
    }

    try {
      const body = await request.json();
      const action = body?.action;
      const data = body?.data;

      if (!action || typeof action !== 'string') {
        return jsonResponse({ success: false, error: 'Missing action' }, 400);
      }
      if (!data || typeof data !== 'object') {
        return jsonResponse({ success: false, error: 'Missing data' }, 400);
      }

      const apiKey = env?.RESEND_API_KEY;

      if (action === 'order-notification') {
        return await sendOrderNotification(data, apiKey);
      }
      if (action === 'order-cancellation') {
        return await sendOrderCancellation(data, apiKey);
      }
      if (action === 'customer-confirmation') {
        return await sendCustomerConfirmation(data, apiKey);
      }
      if (action === 'report') {
        return await sendReport(data, apiKey);
      }

      return jsonResponse({ success: false, error: 'Invalid action' }, 400);
    } catch (error) {
      return jsonResponse({ success: false, error: error?.message || 'Unknown error' }, 500);
    }
  },
};

async function sendOrderNotification(data, apiKey) {
  const orderNo = safeText(data.orderNo, '—');
  const table = safeText(data.table, '');
  const items = toArray(data.items);
  const subtotal = toNumber(data.subtotal, 0);
  const timestamp = safeText(data.timestamp, '');
  const merchantName = safeText(data.merchantName, 'SweetWeb');
  const dashboardUrl = safeText(data.dashboardUrl, '#');
  const toEmail = safeText(data.toEmail, '');

  const html = orderNotificationTemplate({
    orderNo,
    table,
    items,
    subtotal,
    timestamp,
    merchantName,
    dashboardUrl,
  });

  const subject = `🔔 New Order ${orderNo}${table ? ` - Table ${table}` : ''}`;

  return await sendViaResend({ apiKey, to: toEmail, subject, html });
}

async function sendOrderCancellation(data, apiKey) {
  const orderNo = safeText(data.orderNo, '—');
  const table = safeText(data.table, '');
  const items = toArray(data.items);
  const subtotal = toNumber(data.subtotal, 0);
  const timestamp = safeText(data.timestamp, '');
  const merchantName = safeText(data.merchantName, 'SweetWeb');
  const dashboardUrl = safeText(data.dashboardUrl, '#');
  const toEmail = safeText(data.toEmail, '');
  const cancellationReason = safeText(data.cancellationReason, '');

  const html = orderCancellationTemplate({
    orderNo,
    table,
    items,
    subtotal,
    timestamp,
    merchantName,
    dashboardUrl,
    cancellationReason,
  });

  const subject = `❌ Order Cancelled ${orderNo}${table ? ` - Table ${table}` : ''}`;

  return await sendViaResend({ apiKey, to: toEmail, subject, html });
}

async function sendCustomerConfirmation(data, apiKey) {
  const orderNo = safeText(data.orderNo, '—');
  const table = safeText(data.table, '');
  const items = toArray(data.items);
  const subtotal = toNumber(data.subtotal, 0);
  const timestamp = safeText(data.timestamp, '');
  const merchantName = safeText(data.merchantName, 'SweetWeb');
  const estimatedTime = safeText(data.estimatedTime, '');
  const toEmail = safeText(data.toEmail, '');

  const html = customerConfirmationTemplate({
    orderNo,
    table,
    items,
    subtotal,
    timestamp,
    merchantName,
    estimatedTime,
  });

  const subject = `✅ Order Confirmed ${orderNo} - ${merchantName}`;

  return await sendViaResend({ apiKey, to: toEmail, subject, html });
}

async function sendReport(data, apiKey) {
  const merchantName = safeText(data.merchantName, 'SweetWeb');
  const dateRange = safeText(data.dateRange, '');
  const totalOrders = toNumber(data.totalOrders, 0);
  const totalRevenue = toNumber(data.totalRevenue, 0);
  const servedOrders = toNumber(data.servedOrders, 0);
  const cancelledOrders = toNumber(data.cancelledOrders, 0);
  const averageOrder = toNumber(data.averageOrder, 0);
  const topItems = toArray(data.topItems);
  const ordersByStatus = toArray(data.ordersByStatus);
  const toEmail = safeText(data.toEmail, '');

  const html = reportTemplate({
    merchantName,
    dateRange,
    totalOrders,
    totalRevenue,
    servedOrders,
    cancelledOrders,
    averageOrder,
    topItems,
    ordersByStatus,
  });

  const subject = `📊 Sales Report - ${dateRange || 'Report'}`;

  return await sendViaResend({ apiKey, to: toEmail, subject, html });
}

function orderNotificationTemplate(data) {
  const items = toArray(data.items);

  const itemsHtml = items
    .map((item) => {
      const name = safeText(item?.name, 'Item');
      const qty = toNumber(item?.qty, 1);
      const note = safeText(item?.note, '');
      const price = toNumber(item?.price, 0);

      return `
      <tr>
        <td style="padding: 8px; border-bottom: 1px solid #eee;">
          ${name} ${qty > 1 ? `(x${qty})` : ''}
          ${note ? `<br/><span style="font-size: 12px; color: #666;">Note: ${note}</span>` : ''}
        </td>
        <td style="padding: 8px; border-bottom: 1px solid #eee; text-align: right;">
          ${price.toFixed(3)} BHD
        </td>
      </tr>
    `;
    })
    .join('');

  const subtotal = toNumber(data.subtotal, 0);

  return `
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
</head>
<body style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; margin: 0; padding: 20px; background-color: #f5f5f5;">
  <div style="max-width: 600px; margin: 0 auto; background: white; border-radius: 8px; box-shadow: 0 2px 8px rgba(0,0,0,0.1);">
    <div style="background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; padding: 24px; border-radius: 8px 8px 0 0;">
      <h1 style="margin: 0; font-size: 24px;">🔔 New Order Received!</h1>
      <p style="margin: 8px 0 0 0; opacity: 0.9;">You have a new order at ${safeText(
        data.merchantName,
        'SweetWeb'
      )}</p>
    </div>
    <div style="padding: 24px;">
      <div style="background: #f8f9fa; padding: 16px; border-radius: 6px; margin-bottom: 20px;">
        <h2 style="margin: 0 0 12px 0; font-size: 18px; color: #333;">Order Details</h2>
        <table style="width: 100%;">
          <tr>
            <td style="padding: 4px 0; color: #666;">Order Number:</td>
            <td style="padding: 4px 0; text-align: right; font-weight: 600; color: #667eea;">${safeText(
              data.orderNo,
              '—'
            )}</td>
          </tr>
          ${
            safeText(data.table, '')
              ? `
          <tr>
            <td style="padding: 4px 0; color: #666;">Table:</td>
            <td style="padding: 4px 0; text-align: right; font-weight: 600;">${safeText(
              data.table,
              ''
            )}</td>
          </tr>
          `
              : ''
          }
          <tr>
            <td style="padding: 4px 0; color: #666;">Time:</td>
            <td style="padding: 4px 0; text-align: right;">${safeText(data.timestamp, '')}</td>
          </tr>
          <tr>
            <td style="padding: 4px 0; color: #666;">Status:</td>
            <td style="padding: 4px 0; text-align: right;">
              <span style="background: #fef3c7; color: #92400e; padding: 4px 12px; border-radius: 12px; font-size: 12px; font-weight: 600;">
                PENDING
              </span>
            </td>
          </tr>
        </table>
      </div>
      <h3 style="margin: 0 0 12px 0; font-size: 16px; color: #333;">Items</h3>
      <table style="width: 100%; border-collapse: collapse;">
        ${itemsHtml || '<tr><td style="padding:8px;">No items</td><td></td></tr>'}
        <tr>
          <td style="padding: 16px 8px 8px 8px; font-weight: 600; font-size: 16px;">Subtotal</td>
          <td style="padding: 16px 8px 8px 8px; text-align: right; font-weight: 600; font-size: 16px; color: #667eea;">
            ${subtotal.toFixed(3)} BHD
          </td>
        </tr>
      </table>
      <div style="margin-top: 24px; text-align: center;">
        <a href="${safeText(
          data.dashboardUrl,
          '#'
        )}" style="display: inline-block; background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; text-decoration: none; padding: 12px 32px; border-radius: 6px; font-weight: 600;">
          View in Dashboard →
        </a>
      </div>
    </div>
    <div style="padding: 16px 24px; background: #f8f9fa; border-radius: 0 0 8px 8px; text-align: center; color: #666; font-size: 12px;">
      <p style="margin: 0;">This is an automated notification from SweetWeb</p>
    </div>
  </div>
</body>
</html>
  `;
}

function reportTemplate(data) {
  const topItems = toArray(data.topItems);
  const ordersByStatus = toArray(data.ordersByStatus);

  const topItemsHtml = topItems
    .slice(0, 5)
    .map((item, idx) => {
      const name = safeText(item?.name, 'Item');
      const count = toNumber(item?.count, 0);
      const revenue = toNumber(item?.revenue, 0);
      return `
      <tr>
        <td style="padding: 8px; border-bottom: 1px solid #eee;">${idx + 1}. ${name}</td>
        <td style="padding: 8px; border-bottom: 1px solid #eee; text-align: center;">${count}</td>
        <td style="padding: 8px; border-bottom: 1px solid #eee; text-align: right;">${revenue.toFixed(
          3
        )} BHD</td>
      </tr>
    `;
    })
    .join('');

  const totalOrders = Math.max(1, toNumber(data.totalOrders, 0));
  const statusHtml = ordersByStatus
    .map((s) => {
      const status = safeText(s?.status, 'status');
      const count = toNumber(s?.count, 0);
      const width = Math.max(0, Math.min(100, (count / totalOrders) * 100));
      return `
      <div style="margin-bottom: 8px;">
        <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 4px;">
          <span style="font-size: 14px; text-transform: capitalize;">${status}</span>
          <span style="font-weight: 600;">${count}</span>
        </div>
        <div style="background: #e5e7eb; height: 8px; border-radius: 4px; overflow: hidden;">
          <div style="background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); height: 100%; width: ${width}%;"></div>
        </div>
      </div>
    `;
    })
    .join('');

  const totalRevenue = toNumber(data.totalRevenue, 0);
  const averageOrder = toNumber(data.averageOrder, 0);
  const cancelledOrders = toNumber(data.cancelledOrders, 0);

  return `
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
</head>
<body style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; margin: 0; padding: 20px; background-color: #f5f5f5;">
  <div style="max-width: 700px; margin: 0 auto; background: white; border-radius: 8px; box-shadow: 0 2px 8px rgba(0,0,0,0.1);">
    <div style="background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; padding: 24px; border-radius: 8px 8px 0 0;">
      <h1 style="margin: 0; font-size: 24px;">📊 Sales Report</h1>
      <p style="margin: 8px 0 0 0; opacity: 0.9;">${safeText(
        data.merchantName,
        'SweetWeb'
      )} • ${safeText(data.dateRange, '')}</p>
    </div>
    <div style="padding: 24px;">
      <div style="display: grid; grid-template-columns: repeat(2, 1fr); gap: 16px; margin-bottom: 24px;">
        <div style="background: #f0fdf4; padding: 16px; border-radius: 6px; border-left: 4px solid #22c55e;">
          <div style="font-size: 12px; color: #166534; font-weight: 600; margin-bottom: 4px;">TOTAL REVENUE</div>
          <div style="font-size: 24px; font-weight: 700; color: #15803d;">${totalRevenue.toFixed(
            3
          )} BHD</div>
        </div>
        <div style="background: #eff6ff; padding: 16px; border-radius: 6px; border-left: 4px solid #3b82f6;">
          <div style="font-size: 12px; color: #1e40af; font-weight: 600; margin-bottom: 4px;">TOTAL ORDERS</div>
          <div style="font-size: 24px; font-weight: 700; color: #1e3a8a;">${toNumber(
            data.totalOrders,
            0
          )}</div>
        </div>
        <div style="background: #fef3c7; padding: 16px; border-radius: 6px; border-left: 4px solid #f59e0b;">
          <div style="font-size: 12px; color: #92400e; font-weight: 600; margin-bottom: 4px;">AVG ORDER VALUE</div>
          <div style="font-size: 24px; font-weight: 700; color: #b45309;">${averageOrder.toFixed(
            3
          )} BHD</div>
        </div>
        <div style="background: #fef2f2; padding: 16px; border-radius: 6px; border-left: 4px solid #ef4444;">
          <div style="font-size: 12px; color: #991b1b; font-weight: 600; margin-bottom: 4px;">CANCELLED</div>
          <div style="font-size: 24px; font-weight: 700; color: #b91c1c;">${cancelledOrders}</div>
        </div>
      </div>

      <div style="margin-bottom: 24px;">
        <h2 style="margin: 0 0 12px 0; font-size: 18px; color: #333;">🏆 Top Selling Items</h2>
        <table style="width: 100%; border-collapse: collapse;">
          <thead>
            <tr style="background: #f8f9fa;">
              <th style="padding: 8px; text-align: left; font-size: 12px; color: #666;">Item</th>
              <th style="padding: 8px; text-align: center; font-size: 12px; color: #666;">Orders</th>
              <th style="padding: 8px; text-align: right; font-size: 12px; color: #666;">Revenue</th>
            </tr>
          </thead>
          <tbody>
            ${topItemsHtml || '<tr><td style="padding:8px;">No data</td><td></td><td></td></tr>'}
          </tbody>
        </table>
      </div>

      <div style="margin-bottom: 24px;">
        <h2 style="margin: 0 0 12px 0; font-size: 18px; color: #333;">📈 Orders by Status</h2>
        ${statusHtml || '<div>No status data</div>'}
      </div>
    </div>

    <div style="padding: 16px 24px; background: #f8f9fa; border-radius: 0 0 8px 8px; text-align: center; color: #666; font-size: 12px;">
      <p style="margin: 0;">Generated by SweetWeb</p>
    </div>
  </div>
</body>
</html>
  `;
}

function customerConfirmationTemplate(data) {
  const items = toArray(data.items);

  const itemsHtml = items
    .map((item) => {
      const name = safeText(item?.name, 'Item');
      const qty = Math.max(1, toNumber(item?.qty, 1));
      const note = safeText(item?.note, '');
      const price = toNumber(item?.price, 0);

      return `
      <tr>
        <td style="padding: 12px 8px; border-bottom: 1px solid #eee;">
          <div style="font-weight: 500; margin-bottom: 4px;">${name}</div>
          ${note ? `<div style="font-size: 12px; color: #666; font-style: italic;">Note: ${note}</div>` : ''}
        </td>
        <td style="padding: 12px 8px; border-bottom: 1px solid #eee; text-align: center; color: #666;">
          x${qty}
        </td>
        <td style="padding: 12px 8px; border-bottom: 1px solid #eee; text-align: right; font-weight: 500;">
          ${price.toFixed(3)} BHD
        </td>
      </tr>
    `;
    })
    .join('');

  const subtotal = toNumber(data.subtotal, 0);

  return `
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
</head>
<body style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; margin: 0; padding: 20px; background-color: #f5f5f5;">
  <div style="max-width: 600px; margin: 0 auto; background: white; border-radius: 8px; box-shadow: 0 2px 8px rgba(0,0,0,0.1);">
    <div style="background: linear-gradient(135deg, #10b981 0%, #059669 100%); color: white; padding: 32px 24px; border-radius: 8px 8px 0 0; text-align: center;">
      <div style="font-size: 48px; margin-bottom: 8px;">✅</div>
      <h1 style="margin: 0; font-size: 28px; font-weight: 700;">Order Confirmed!</h1>
      <p style="margin: 12px 0 0 0; opacity: 0.95; font-size: 16px;">Thank you for your order</p>
    </div>

    <div style="padding: 32px 24px;">
      <div style="background: #f0fdf4; padding: 20px; border-radius: 8px; margin-bottom: 24px; border-left: 4px solid #10b981;">
        <table style="width: 100%;">
          <tr>
            <td style="padding: 6px 0; color: #666; font-size: 14px;">Order Number:</td>
            <td style="padding: 6px 0; text-align: right; font-weight: 700; font-size: 18px; color: #059669;">${safeText(
              data.orderNo,
              '—'
            )}</td>
          </tr>
          <tr>
            <td style="padding: 6px 0; color: #666; font-size: 14px;">Restaurant:</td>
            <td style="padding: 6px 0; text-align: right; font-weight: 600; color: #333;">${safeText(
              data.merchantName,
              'SweetWeb'
            )}</td>
          </tr>
          ${
            safeText(data.table, '')
              ? `
          <tr>
            <td style="padding: 6px 0; color: #666; font-size: 14px;">Table Number:</td>
            <td style="padding: 6px 0; text-align: right; font-weight: 600; color: #333;">${safeText(
              data.table,
              ''
            )}</td>
          </tr>
          `
              : ''
          }
          <tr>
            <td style="padding: 6px 0; color: #666; font-size: 14px;">Order Time:</td>
            <td style="padding: 6px 0; text-align: right; color: #333;">${safeText(data.timestamp, '')}</td>
          </tr>
          ${
            safeText(data.estimatedTime, '')
              ? `
          <tr>
            <td style="padding: 6px 0; color: #666; font-size: 14px;">Estimated Time:</td>
            <td style="padding: 6px 0; text-align: right; font-weight: 600; color: #059669;">${safeText(
              data.estimatedTime,
              ''
            )}</td>
          </tr>
          `
              : ''
          }
        </table>
      </div>

      <div style="text-align: center; margin-bottom: 24px;">
        <div style="display: inline-block; background: #fef3c7; color: #92400e; padding: 12px 24px; border-radius: 24px; font-weight: 600; font-size: 14px;">
          🕐 Your order is being prepared
        </div>
      </div>

      <h2 style="margin: 0 0 16px 0; font-size: 18px; color: #333; padding-bottom: 8px; border-bottom: 2px solid #f3f4f6;">Order Details</h2>
      <table style="width: 100%; border-collapse: collapse; margin-bottom: 20px;">
        <thead>
          <tr style="background: #f9fafb;">
            <th style="padding: 10px 8px; text-align: left; font-size: 13px; color: #6b7280; font-weight: 600;">Item</th>
            <th style="padding: 10px 8px; text-align: center; font-size: 13px; color: #6b7280; font-weight: 600;">Qty</th>
            <th style="padding: 10px 8px; text-align: right; font-size: 13px; color: #6b7280; font-weight: 600;">Price</th>
          </tr>
        </thead>
        <tbody>
          ${itemsHtml || '<tr><td style="padding:10px;">No items</td><td></td><td></td></tr>'}
        </tbody>
      </table>

      <div style="background: #f9fafb; padding: 20px; border-radius: 8px; margin-bottom: 24px;">
        <div style="display: flex; justify-content: space-between; align-items: center;">
          <span style="font-size: 18px; font-weight: 600; color: #333;">Total Amount</span>
          <span style="font-size: 24px; font-weight: 700; color: #059669;">${subtotal.toFixed(3)} BHD</span>
        </div>
      </div>

      <div style="text-align: center; padding: 24px; background: linear-gradient(135deg, #f0fdf4 0%, #dcfce7 100%); border-radius: 8px;">
        <p style="margin: 0 0 8px 0; font-size: 16px; color: #333; font-weight: 500;">Thank you for choosing ${safeText(
          data.merchantName,
          'SweetWeb'
        )}!</p>
        <p style="margin: 0; font-size: 14px; color: #666;">We're preparing your order with care</p>
      </div>
    </div>

    <div style="padding: 20px 24px; background: #f9fafb; border-radius: 0 0 8px 8px; text-align: center; color: #6b7280; font-size: 12px; border-top: 1px solid #e5e7eb;">
      <p style="margin: 0 0 8px 0;">This is an automated confirmation email from SweetWeb</p>
      <p style="margin: 0; color: #9ca3af;">Please do not reply to this email</p>
    </div>
  </div>
</body>
</html>
  `;
}

function orderCancellationTemplate(data) {
  const items = toArray(data.items);

  const itemsHtml = items
    .map((item) => {
      const name = safeText(item?.name, 'Item');
      const qty = toNumber(item?.qty, 1);
      const note = safeText(item?.note, '');
      const price = toNumber(item?.price, 0);

      return `
      <tr>
        <td style="padding: 8px; border-bottom: 1px solid #eee;">
          ${name} ${qty > 1 ? `(x${qty})` : ''}
          ${note ? `<br/><span style="font-size: 12px; color: #666;">Note: ${note}</span>` : ''}
        </td>
        <td style="padding: 8px; border-bottom: 1px solid #eee; text-align: right;">
          ${price.toFixed(3)} BHD
        </td>
      </tr>
    `;
    })
    .join('');

  const subtotal = toNumber(data.subtotal, 0);
  const cancellationReason = safeText(data.cancellationReason, '');

  return `
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
</head>
<body style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; margin: 0; padding: 20px; background-color: #f5f5f5;">
  <div style="max-width: 600px; margin: 0 auto; background: white; border-radius: 8px; box-shadow: 0 2px 8px rgba(0,0,0,0.1);">
    <div style="background: linear-gradient(135deg, #ef4444 0%, #dc2626 100%); color: white; padding: 24px; border-radius: 8px 8px 0 0;">
      <h1 style="margin: 0; font-size: 24px;">❌ Order Cancelled</h1>
      <p style="margin: 8px 0 0 0; opacity: 0.9;">Order has been cancelled at ${safeText(
        data.merchantName,
        'SweetWeb'
      )}</p>
    </div>
    <div style="padding: 24px;">
      <div style="background: #fef2f2; padding: 16px; border-radius: 6px; margin-bottom: 20px; border-left: 4px solid #ef4444;">
        <h2 style="margin: 0 0 12px 0; font-size: 18px; color: #333;">Order Details</h2>
        <table style="width: 100%;">
          <tr>
            <td style="padding: 4px 0; color: #666;">Order Number:</td>
            <td style="padding: 4px 0; text-align: right; font-weight: 600; color: #ef4444;">${safeText(
              data.orderNo,
              '—'
            )}</td>
          </tr>
          ${
            safeText(data.table, '')
              ? `
          <tr>
            <td style="padding: 4px 0; color: #666;">Table:</td>
            <td style="padding: 4px 0; text-align: right; font-weight: 600;">${safeText(
              data.table,
              ''
            )}</td>
          </tr>
          `
              : ''
          }
          <tr>
            <td style="padding: 4px 0; color: #666;">Cancelled At:</td>
            <td style="padding: 4px 0; text-align: right;">${safeText(data.timestamp, '')}</td>
          </tr>
          <tr>
            <td style="padding: 4px 0; color: #666;">Status:</td>
            <td style="padding: 4px 0; text-align: right;">
              <span style="background: #fee2e2; color: #991b1b; padding: 4px 12px; border-radius: 12px; font-size: 12px; font-weight: 600;">
                CANCELLED
              </span>
            </td>
          </tr>
        </table>
      </div>

      ${
        cancellationReason
          ? `
      <div style="background: #fffbeb; padding: 16px; border-radius: 6px; margin-bottom: 20px; border-left: 4px solid #f59e0b;">
        <h3 style="margin: 0 0 8px 0; font-size: 14px; color: #92400e; font-weight: 600;">Cancellation Reason</h3>
        <p style="margin: 0; color: #78350f; font-size: 14px;">${cancellationReason}</p>
      </div>
      `
          : ''
      }

      <h3 style="margin: 0 0 12px 0; font-size: 16px; color: #333;">Items</h3>
      <table style="width: 100%; border-collapse: collapse;">
        ${itemsHtml || '<tr><td style="padding:8px;">No items</td><td></td></tr>'}
        <tr>
          <td style="padding: 16px 8px 8px 8px; font-weight: 600; font-size: 16px;">Subtotal</td>
          <td style="padding: 16px 8px 8px 8px; text-align: right; font-weight: 600; font-size: 16px; color: #ef4444;">
            ${subtotal.toFixed(3)} BHD
          </td>
        </tr>
      </table>
      <div style="margin-top: 24px; text-align: center;">
        <a href="${safeText(
          data.dashboardUrl,
          '#'
        )}" style="display: inline-block; background: linear-gradient(135deg, #ef4444 0%, #dc2626 100%); color: white; text-decoration: none; padding: 12px 32px; border-radius: 6px; font-weight: 600;">
          View in Dashboard →
        </a>
      </div>
    </div>
    <div style="padding: 16px 24px; background: #f8f9fa; border-radius: 0 0 8px 8px; text-align: center; color: #666; font-size: 12px;">
      <p style="margin: 0;">This is an automated notification from SweetWeb</p>
    </div>
  </div>
</body>
</html>
  `;
}
