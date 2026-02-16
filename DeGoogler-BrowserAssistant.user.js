// ==UserScript==
// @name         DeGoogler Browser Assistant
// @namespace    https://github.com/SysAdminDoc
// @version      0.0.5
// @description  Automates Google Takeout selection, exports YouTube subscriptions, audits connected apps/OAuth services, tracks migration of every account tied to your Google login, and assists with Gmail forwarding setup during the degoogling process.
// @author       SysAdminDoc
// @match        https://takeout.google.com/*
// @match        https://myaccount.google.com/*
// @match        https://mail.google.com/*
// @match        https://www.youtube.com/*
// @match        https://sysadmindoc.github.io/DeGoogler/*
// @grant        GM_getValue
// @grant        GM_setValue
// @grant        GM_addStyle
// @grant        GM_download
// @grant        GM_xmlhttpRequest
// @run-at       document-start
// ==/UserScript==

(function() {
    'use strict';

    // ── TrustedTypes policy (required by Google CSP) ──
    const TTP = (typeof trustedTypes !== 'undefined' && trustedTypes.createPolicy)
        ? trustedTypes.createPolicy('degoogler', { createHTML: s => s })
        : { createHTML: s => s };
    // ── Anti-FOUC ──
    const antiFouc = document.createElement('style');
    antiFouc.id = 'degoogler-antifouc';
    antiFouc.textContent = '.degoogler-panel{opacity:0;transition:opacity .3s ease}';
    document.documentElement.appendChild(antiFouc);

    // ── Config ──
    const CFG = {
        accentColor: '#3b82f6',
        bgDark: '#0f1117',
        bgPanel: '#161822',
        bgCard: '#1c1e2e',
        bgHover: '#252840',
        border: '#2a2d42',
        text: '#e2e4f0',
        textMuted: '#6b7094',
        green: '#22c55e',
        orange: '#f59e0b',
        red: '#ef4444',
        fontStack: "-apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif",
    };

    // ── CSS ──
    const STYLES = `
        /* DeGoogler Panel Base */
        .dg-panel {
            position: fixed;
            top: 12px;
            right: 12px;
            width: 380px;
            max-height: calc(100vh - 24px);
            background: ${CFG.bgPanel};
            border: 1px solid ${CFG.border};
            border-radius: 14px;
            box-shadow: 0 8px 32px rgba(0,0,0,0.6), 0 0 0 1px rgba(59,130,246,0.08);
            z-index: 999999;
            font-family: ${CFG.fontStack};
            color: ${CFG.text};
            overflow: hidden;
            transition: all 0.3s cubic-bezier(0.4,0,0.2,1);
            pointer-events: auto;
        }
        .dg-panel.dg-collapsed {
            width: 52px;
            height: 52px;
            border-radius: 14px;
            cursor: pointer;
            overflow: hidden;
        }
        .dg-panel.dg-collapsed .dg-body,
        .dg-panel.dg-collapsed .dg-header-text { display: none; }
        .dg-panel.dg-collapsed .dg-header { padding: 12px; justify-content: center; border: none; }
        .dg-header {
            display: flex;
            align-items: center;
            gap: 10px;
            padding: 14px 16px;
            border-bottom: 1px solid ${CFG.border};
            background: ${CFG.bgDark};
            cursor: move;
            user-select: none;
        }
        .dg-logo {
            width: 28px;
            height: 28px;
            border-radius: 8px;
            background: linear-gradient(135deg, ${CFG.accentColor}, #7c3aed);
            display: flex;
            align-items: center;
            justify-content: center;
            font-size: 12px;
            font-weight: 800;
            color: #fff;
            flex-shrink: 0;
        }
        .dg-header-text {
            flex: 1;
            min-width: 0;
        }
        .dg-header-text h3 {
            margin: 0;
            font-size: 13px;
            font-weight: 700;
            color: ${CFG.text};
        }
        .dg-header-text p {
            margin: 2px 0 0;
            font-size: 10px;
            color: ${CFG.textMuted};
        }
        .dg-close {
            width: 28px;
            height: 28px;
            border: none;
            background: transparent;
            color: ${CFG.textMuted};
            cursor: pointer;
            border-radius: 6px;
            font-size: 16px;
            display: flex;
            align-items: center;
            justify-content: center;
            transition: all 0.15s;
        }
        .dg-close:hover { background: ${CFG.bgHover}; color: ${CFG.text}; }
        .dg-body {
            overflow-y: auto;
            max-height: calc(100vh - 120px);
            padding: 12px;
        }
        .dg-body::-webkit-scrollbar { width: 6px; }
        .dg-body::-webkit-scrollbar-track { background: transparent; }
        .dg-body::-webkit-scrollbar-thumb { background: ${CFG.border}; border-radius: 3px; }
        .dg-section {
            background: ${CFG.bgCard};
            border: 1px solid ${CFG.border};
            border-radius: 10px;
            padding: 14px;
            margin-bottom: 10px;
        }
        .dg-section h4 {
            margin: 0 0 8px;
            font-size: 12px;
            font-weight: 700;
            color: ${CFG.text};
            display: flex;
            align-items: center;
            gap: 6px;
        }
        .dg-section p {
            margin: 0;
            font-size: 11px;
            color: ${CFG.textMuted};
            line-height: 1.5;
        }
        .dg-btn {
            display: inline-flex;
            align-items: center;
            gap: 6px;
            padding: 8px 16px;
            border: none;
            border-radius: 8px;
            font-size: 12px;
            font-weight: 600;
            cursor: pointer;
            font-family: inherit;
            transition: all 0.15s;
        }
        .dg-btn-primary {
            background: ${CFG.accentColor};
            color: #fff;
        }
        .dg-btn-primary:hover { background: #2563eb; transform: translateY(-1px); }
        .dg-btn-secondary {
            background: ${CFG.bgHover};
            color: ${CFG.text};
            border: 1px solid ${CFG.border};
        }
        .dg-btn-secondary:hover { background: ${CFG.border}; }
        .dg-btn-success {
            background: ${CFG.green};
            color: #fff;
        }
        .dg-btn-row {
            display: flex;
            gap: 8px;
            margin-top: 10px;
            flex-wrap: wrap;
        }
        .dg-checklist {
            list-style: none;
            padding: 0;
            margin: 8px 0 0;
        }
        .dg-checklist li {
            display: flex;
            align-items: flex-start;
            gap: 8px;
            padding: 6px 0;
            font-size: 11px;
            color: ${CFG.text};
            border-bottom: 1px solid rgba(42,45,66,0.5);
        }
        .dg-checklist li:last-child { border-bottom: none; }
        .dg-check {
            width: 16px;
            height: 16px;
            border-radius: 4px;
            border: 2px solid ${CFG.border};
            flex-shrink: 0;
            margin-top: 1px;
            cursor: pointer;
            display: flex;
            align-items: center;
            justify-content: center;
            font-size: 10px;
            transition: all 0.15s;
        }
        .dg-check.checked {
            background: ${CFG.green};
            border-color: ${CFG.green};
            color: #fff;
        }
        .dg-badge {
            display: inline-flex;
            padding: 2px 8px;
            border-radius: 4px;
            font-size: 10px;
            font-weight: 600;
        }
        .dg-badge-green { background: rgba(34,197,94,0.12); color: ${CFG.green}; }
        .dg-badge-orange { background: rgba(245,158,11,0.12); color: ${CFG.orange}; }
        .dg-badge-blue { background: rgba(59,130,246,0.12); color: ${CFG.accentColor}; }
        .dg-progress {
            height: 4px;
            background: ${CFG.bgDark};
            border-radius: 2px;
            margin-top: 8px;
            overflow: hidden;
        }
        .dg-progress-fill {
            height: 100%;
            background: linear-gradient(90deg, ${CFG.accentColor}, ${CFG.green});
            border-radius: 2px;
            transition: width 0.4s cubic-bezier(0.4,0,0.2,1);
        }
        .dg-toast {
            position: fixed;
            bottom: 20px;
            right: 20px;
            background: ${CFG.bgPanel};
            color: ${CFG.text};
            border: 1px solid ${CFG.border};
            padding: 12px 18px;
            border-radius: 10px;
            font-size: 12px;
            font-family: ${CFG.fontStack};
            box-shadow: 0 8px 24px rgba(0,0,0,0.5);
            z-index: 9999999;
            opacity: 0;
            transform: translateY(10px);
            transition: all 0.3s ease;
        }
        .dg-toast.visible { opacity: 1; transform: none; }

        /* Connected Services Auditor */
        .dg-app-card {
            background: ${CFG.bgDark};
            border: 1px solid ${CFG.border};
            border-radius: 8px;
            padding: 10px 12px;
            margin-bottom: 6px;
            transition: all 0.15s;
        }
        .dg-app-card:hover { border-color: ${CFG.accentColor}33; }
        .dg-app-row {
            display: flex;
            align-items: center;
            gap: 8px;
        }
        .dg-app-name {
            flex: 1;
            font-size: 12px;
            font-weight: 600;
            color: ${CFG.text};
            min-width: 0;
            overflow: hidden;
            text-overflow: ellipsis;
            white-space: nowrap;
        }
        .dg-app-type {
            font-size: 9px;
            padding: 2px 6px;
            border-radius: 3px;
            font-weight: 600;
            flex-shrink: 0;
        }
        .dg-type-oauth { background: rgba(139,92,246,0.15); color: #a78bfa; }
        .dg-type-email { background: rgba(59,130,246,0.15); color: #60a5fa; }
        .dg-type-billing { background: rgba(245,158,11,0.15); color: ${CFG.orange}; }
        .dg-app-steps {
            display: flex;
            gap: 4px;
            margin-top: 8px;
        }
        .dg-step-pill {
            font-size: 9px;
            padding: 3px 8px;
            border-radius: 4px;
            cursor: pointer;
            border: 1px solid ${CFG.border};
            background: transparent;
            color: ${CFG.textMuted};
            font-family: inherit;
            transition: all 0.15s;
            white-space: nowrap;
        }
        .dg-step-pill:hover { border-color: ${CFG.accentColor}66; color: ${CFG.text}; }
        .dg-step-pill.done {
            background: ${CFG.green}22;
            border-color: ${CFG.green}44;
            color: ${CFG.green};
        }
        .dg-step-pill.active {
            background: ${CFG.accentColor}22;
            border-color: ${CFG.accentColor}55;
            color: ${CFG.accentColor};
        }
        .dg-priority-label {
            font-size: 9px;
            padding: 1px 6px;
            border-radius: 3px;
            font-weight: 700;
            flex-shrink: 0;
        }
        .dg-pri-critical { background: ${CFG.red}22; color: ${CFG.red}; }
        .dg-pri-important { background: ${CFG.orange}22; color: ${CFG.orange}; }
        .dg-pri-optional { background: ${CFG.border}; color: ${CFG.textMuted}; }
        .dg-input-row {
            display: flex;
            gap: 6px;
            margin-top: 8px;
        }
        .dg-input {
            flex: 1;
            padding: 7px 10px;
            border: 1px solid ${CFG.border};
            border-radius: 6px;
            background: ${CFG.bgDark};
            color: ${CFG.text};
            font-size: 12px;
            font-family: inherit;
            outline: none;
            transition: border-color 0.15s;
        }
        .dg-input:focus { border-color: ${CFG.accentColor}; }
        .dg-input::placeholder { color: ${CFG.textMuted}; }
        .dg-select {
            padding: 7px 8px;
            border: 1px solid ${CFG.border};
            border-radius: 6px;
            background: ${CFG.bgDark};
            color: ${CFG.text};
            font-size: 11px;
            font-family: inherit;
            outline: none;
            cursor: pointer;
        }
        .dg-tabs {
            display: flex;
            gap: 4px;
            margin-bottom: 10px;
        }
        .dg-tab {
            padding: 5px 10px;
            border: 1px solid ${CFG.border};
            border-radius: 6px;
            background: transparent;
            color: ${CFG.textMuted};
            font-size: 11px;
            font-family: inherit;
            cursor: pointer;
            transition: all 0.15s;
        }
        .dg-tab:hover { color: ${CFG.text}; }
        .dg-tab.active {
            background: ${CFG.accentColor}22;
            border-color: ${CFG.accentColor}55;
            color: ${CFG.accentColor};
        }
        .dg-counter {
            display: inline-flex;
            align-items: center;
            justify-content: center;
            min-width: 18px;
            height: 18px;
            border-radius: 9px;
            font-size: 10px;
            font-weight: 700;
            padding: 0 5px;
        }
        .dg-app-delete {
            width: 20px;
            height: 20px;
            border: none;
            background: transparent;
            color: ${CFG.textMuted};
            cursor: pointer;
            border-radius: 4px;
            font-size: 12px;
            display: flex;
            align-items: center;
            justify-content: center;
            flex-shrink: 0;
            transition: all 0.15s;
        }
        .dg-app-delete:hover { color: ${CFG.red}; background: ${CFG.red}22; }
        .dg-stat-grid {
            display: grid;
            grid-template-columns: 1fr 1fr;
            gap: 6px;
            margin-bottom: 10px;
        }
        .dg-stat-box {
            background: ${CFG.bgDark};
            border: 1px solid ${CFG.border};
            border-radius: 8px;
            padding: 10px;
            text-align: center;
        }
        .dg-stat-num {
            font-size: 20px;
            font-weight: 800;
            color: ${CFG.text};
        }
        .dg-stat-label {
            font-size: 9px;
            color: ${CFG.textMuted};
            margin-top: 2px;
        }
    `;

    // ── Utility Functions ──
    function showToast(msg, duration = 3000) {
        const toast = document.createElement('div');
        toast.className = 'dg-toast';
        toast.textContent = msg;
        document.body.appendChild(toast);
        requestAnimationFrame(() => toast.classList.add('visible'));
        setTimeout(() => {
            toast.classList.remove('visible');
            setTimeout(() => toast.remove(), 300);
        }, duration);
    }

    function waitForElement(selector, timeout = 15000) {
        return new Promise((resolve, reject) => {
            const el = document.querySelector(selector);
            if (el) return resolve(el);
            const obs = new MutationObserver(() => {
                const el = document.querySelector(selector);
                if (el) { obs.disconnect(); resolve(el); }
            });
            obs.observe(document.body, { childList: true, subtree: true });
            setTimeout(() => { obs.disconnect(); reject(new Error('Timeout')); }, timeout);
        });
    }

    function createPanel(title, subtitle, bodyHTML) {
        const panel = document.createElement('div');
        panel.className = 'dg-panel';
        panel.innerHTML = TTP.createHTML(`
            <div class="dg-header">
                <div class="dg-logo">DG</div>
                <div class="dg-header-text">
                    <h3>${title}</h3>
                    <p>${subtitle}</p>
                </div>
                <button class="dg-close" title="Collapse">_</button>
            </div>
            <div class="dg-body">${bodyHTML}</div>
        `);

        // Collapse toggle
        const closeBtn = panel.querySelector('.dg-close');
        closeBtn.addEventListener('click', (e) => {
            e.stopPropagation();
            panel.classList.toggle('dg-collapsed');
        });
        panel.addEventListener('click', (e) => {
            if (panel.classList.contains('dg-collapsed')) {
                panel.classList.remove('dg-collapsed');
            }
        });

        return panel;
    }

    // ═══════════════════════════════════════════════
    // MODULE: Google Takeout Helper
    // ═══════════════════════════════════════════════
    function initTakeoutHelper() {
        const bodyHTML = `
            <div class="dg-section">
                <h4>Quick Actions</h4>
                <p>Automate the Takeout selection process. Click below to select all services for a complete backup.</p>
                <div class="dg-btn-row">
                    <button class="dg-btn dg-btn-primary" id="dg-select-all">Select All Services</button>
                    <button class="dg-btn dg-btn-secondary" id="dg-deselect-all">Deselect All</button>
                </div>
            </div>
            <div class="dg-section">
                <h4>Recommended Settings</h4>
                <ul class="dg-checklist">
                    <li><span class="dg-check" data-key="takeout-format"></span> Export as .zip (most compatible)</li>
                    <li><span class="dg-check" data-key="takeout-size"></span> Set max file size to 10GB+</li>
                    <li><span class="dg-check" data-key="takeout-delivery"></span> Send download link via email</li>
                    <li><span class="dg-check" data-key="takeout-single"></span> Export once (not scheduled)</li>
                </ul>
            </div>
            <div class="dg-section">
                <h4>Export Priority</h4>
                <p>Most critical data to export first:</p>
                <ul class="dg-checklist">
                    <li><span class="dg-badge dg-badge-green">High</span> Gmail (emails, attachments)</li>
                    <li><span class="dg-badge dg-badge-green">High</span> Google Drive (all files)</li>
                    <li><span class="dg-badge dg-badge-green">High</span> Google Photos</li>
                    <li><span class="dg-badge dg-badge-green">High</span> Contacts</li>
                    <li><span class="dg-badge dg-badge-orange">Med</span> Calendar</li>
                    <li><span class="dg-badge dg-badge-orange">Med</span> Chrome (bookmarks, passwords)</li>
                    <li><span class="dg-badge dg-badge-blue">Low</span> YouTube (subscriptions, history)</li>
                    <li><span class="dg-badge dg-badge-blue">Low</span> Keep (notes)</li>
                    <li><span class="dg-badge dg-badge-blue">Low</span> Maps (saved places, timeline)</li>
                </ul>
            </div>
            <div class="dg-section">
                <h4>After Export</h4>
                <p>Once your Takeout is ready, use the <strong>DeGoogler Toolkit</strong> (PowerShell) to extract, organize, and convert your data for import into your new services.</p>
            </div>
        `;

        const panel = createPanel('Takeout Helper', 'DeGoogler Browser Assistant', bodyHTML);
        document.body.appendChild(panel);

        // Select All Services
        document.getElementById('dg-select-all').addEventListener('click', async () => {
            showToast('Selecting all services...');
            // Google Takeout uses toggle switches - find and enable them
            const toggles = document.querySelectorAll('[role="checkbox"][aria-checked="false"], input[type="checkbox"]:not(:checked)');
            let count = 0;
            for (const toggle of toggles) {
                toggle.click();
                count++;
                await new Promise(r => setTimeout(r, 80));
            }
            // Also try material design switches
            const mdSwitches = document.querySelectorAll('.mdc-switch:not(.mdc-switch--checked), [data-is-checked="false"]');
            for (const sw of mdSwitches) {
                sw.click();
                count++;
                await new Promise(r => setTimeout(r, 80));
            }
            showToast(count > 0 ? `Enabled ${count} services` : 'All services already selected (or page structure changed)');
        });

        // Deselect All
        document.getElementById('dg-deselect-all').addEventListener('click', async () => {
            showToast('Deselecting all services...');
            const toggles = document.querySelectorAll('[role="checkbox"][aria-checked="true"], input[type="checkbox"]:checked');
            let count = 0;
            for (const toggle of toggles) {
                toggle.click();
                count++;
                await new Promise(r => setTimeout(r, 80));
            }
            const mdSwitches = document.querySelectorAll('.mdc-switch--checked, [data-is-checked="true"]');
            for (const sw of mdSwitches) {
                sw.click();
                count++;
                await new Promise(r => setTimeout(r, 80));
            }
            showToast(`Deselected ${count} services`);
        });

        // Persist checklist state
        panel.querySelectorAll('.dg-check[data-key]').forEach(check => {
            const key = check.dataset.key;
            if (GM_getValue(key, false)) {
                check.classList.add('checked');
                check.textContent = '\u2713';
            }
            check.addEventListener('click', () => {
                check.classList.toggle('checked');
                const isChecked = check.classList.contains('checked');
                check.textContent = isChecked ? '\u2713' : '';
                GM_setValue(key, isChecked);
            });
        });
    }

    // ═══════════════════════════════════════════════
    // MODULE: YouTube Subscription Exporter
    // ═══════════════════════════════════════════════
    function initYouTubeExporter() {
        const bodyHTML = `
            <div class="dg-section">
                <h4>YouTube Data Export</h4>
                <p>Export your subscriptions as OPML for import into NewPipe, FreeTube, or Invidious.</p>
                <div class="dg-btn-row">
                    <button class="dg-btn dg-btn-primary" id="dg-yt-export-subs">Export Subscriptions (OPML)</button>
                </div>
                <div id="dg-yt-status" style="margin-top:8px;font-size:11px;color:${CFG.textMuted}"></div>
                <div class="dg-progress" id="dg-yt-progress" style="display:none">
                    <div class="dg-progress-fill" id="dg-yt-progress-fill" style="width:0%"></div>
                </div>
            </div>
            <div class="dg-section">
                <h4>Import Targets</h4>
                <ul class="dg-checklist">
                    <li><span class="dg-badge dg-badge-green">OPML</span> NewPipe: Settings > Content > Import from file</li>
                    <li><span class="dg-badge dg-badge-green">OPML</span> FreeTube: Settings > Data Settings > Import Subscriptions</li>
                    <li><span class="dg-badge dg-badge-orange">OPML</span> Invidious: Import/Export Data > Import OPML</li>
                </ul>
            </div>
        `;

        const panel = createPanel('YouTube Exporter', 'DeGoogler Browser Assistant', bodyHTML);
        document.body.appendChild(panel);
        panel.classList.add('dg-collapsed');

        document.getElementById('dg-yt-export-subs').addEventListener('click', async () => {
            const statusEl = document.getElementById('dg-yt-status');
            const progressBar = document.getElementById('dg-yt-progress');
            const progressFill = document.getElementById('dg-yt-progress-fill');
            progressBar.style.display = 'block';

            statusEl.textContent = 'Fetching subscriptions...';
            statusEl.style.color = CFG.orange;

            try {
                // Method 1: Try YouTube's subscription manager page data
                const response = await fetch('https://www.youtube.com/feed/channels', { credentials: 'include' });
                const html = await response.text();

                // Extract ytInitialData from page source
                const match = html.match(/var\s+ytInitialData\s*=\s*({.+?});\s*<\/script>/);
                let channels = [];

                if (match) {
                    try {
                        const data = JSON.parse(match[1]);
                        // Navigate the YouTube data structure to find channel info
                        const items = findNestedChannels(data);
                        channels = items;
                    } catch (e) {
                        statusEl.textContent = 'Parsing page data... trying alternate method';
                    }
                }

                // Method 2: Try scraping subscription links from page
                if (channels.length === 0) {
                    statusEl.textContent = 'Using alternate extraction method...';
                    const guideResponse = await fetch('https://www.youtube.com/feed/subscriptions', { credentials: 'include' });
                    const guideHtml = await guideResponse.text();
                    const guideMatch = guideHtml.match(/var\s+ytInitialData\s*=\s*({.+?});\s*<\/script>/);
                    if (guideMatch) {
                        try {
                            const guideData = JSON.parse(guideMatch[1]);
                            channels = findNestedChannels(guideData);
                        } catch (e) {}
                    }
                }

                // Method 3: Scrape from guide sidebar
                if (channels.length === 0) {
                    statusEl.textContent = 'Scraping sidebar subscriptions...';
                    const sidebarLinks = document.querySelectorAll('a[href*="/channel/"], a[href*="/@"]');
                    const seen = new Set();
                    sidebarLinks.forEach(link => {
                        const href = link.href;
                        const title = link.textContent.trim() || link.title || '';
                        if (title && !seen.has(href) && (href.includes('/channel/') || href.includes('/@'))) {
                            seen.add(href);
                            const channelId = href.match(/\/channel\/(UC[\w-]+)/)?.[1] || '';
                            channels.push({ title: title, channelId: channelId, url: href });
                        }
                    });
                }

                progressFill.style.width = '80%';

                if (channels.length === 0) {
                    statusEl.textContent = 'No subscriptions found. Try Google Takeout instead (YouTube data > subscriptions.csv).';
                    statusEl.style.color = CFG.red;
                    progressBar.style.display = 'none';
                    return;
                }

                // Generate OPML
                let opml = '<?xml version="1.0" encoding="UTF-8"?>\n';
                opml += '<opml version="1.1">\n';
                opml += '  <head>\n';
                opml += '    <title>YouTube Subscriptions - DeGoogler Export</title>\n';
                opml += `    <dateCreated>${new Date().toISOString()}</dateCreated>\n`;
                opml += '  </head>\n';
                opml += '  <body>\n';
                opml += '    <outline text="YouTube Subscriptions" title="YouTube Subscriptions">\n';

                channels.forEach(ch => {
                    const safeName = ch.title.replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&apos;'}[c]));
                    const feedUrl = ch.channelId
                        ? `https://www.youtube.com/feeds/videos.xml?channel_id=${ch.channelId}`
                        : ch.url;
                    const htmlUrl = ch.channelId
                        ? `https://www.youtube.com/channel/${ch.channelId}`
                        : ch.url;
                    opml += `      <outline text="${safeName}" title="${safeName}" type="rss" xmlUrl="${feedUrl}" htmlUrl="${htmlUrl}"/>\n`;
                });

                opml += '    </outline>\n';
                opml += '  </body>\n';
                opml += '</opml>';

                // Download
                const blob = new Blob([opml], { type: 'text/xml' });
                const url = URL.createObjectURL(blob);
                const a = document.createElement('a');
                a.href = url;
                a.download = `youtube-subscriptions-${new Date().toISOString().split('T')[0]}.opml`;
                a.click();
                URL.revokeObjectURL(url);

                progressFill.style.width = '100%';
                statusEl.textContent = `Exported ${channels.length} subscriptions as OPML`;
                statusEl.style.color = CFG.green;
                showToast(`Exported ${channels.length} YouTube subscriptions`);

            } catch (err) {
                statusEl.textContent = 'Export failed. Use Google Takeout for YouTube data instead.';
                statusEl.style.color = CFG.red;
                progressBar.style.display = 'none';
                console.error('[DeGoogler] YouTube export error:', err);
            }
        });

        function findNestedChannels(obj, results = []) {
            if (!obj || typeof obj !== 'object') return results;
            if (obj.subscriberCountText && obj.title && obj.channelId) {
                results.push({ title: obj.title.simpleText || obj.title, channelId: obj.channelId });
            }
            if (obj.channelRenderer) {
                const cr = obj.channelRenderer;
                results.push({
                    title: cr.title?.simpleText || cr.title?.runs?.[0]?.text || '',
                    channelId: cr.channelId || ''
                });
            }
            if (obj.gridChannelRenderer) {
                const gcr = obj.gridChannelRenderer;
                results.push({
                    title: gcr.title?.simpleText || gcr.title?.runs?.[0]?.text || '',
                    channelId: gcr.channelId || ''
                });
            }
            if (obj.guideEntryRenderer) {
                const ger = obj.guideEntryRenderer;
                const navUrl = ger.navigationEndpoint?.browseEndpoint?.browseId || '';
                if (navUrl.startsWith('UC')) {
                    results.push({
                        title: ger.formattedTitle?.simpleText || '',
                        channelId: navUrl
                    });
                }
            }
            for (const key of Object.keys(obj)) {
                if (Array.isArray(obj[key])) {
                    obj[key].forEach(item => findNestedChannels(item, results));
                } else if (typeof obj[key] === 'object') {
                    findNestedChannels(obj[key], results);
                }
            }
            return results;
        }
    }

    // ═══════════════════════════════════════════════
    // MODULE: Google Account Audit
    // ═══════════════════════════════════════════════
    function initAccountAudit() {
        const bodyHTML = `
            <div class="dg-section">
                <h4>Account Audit Checklist</h4>
                <p>Review and clean up your Google account before migrating. Check off each item as you complete it.</p>
                <ul class="dg-checklist">
                    <li><span class="dg-check" data-key="audit-permissions"></span> <div>Review third-party app access<br><a href="https://myaccount.google.com/permissions" style="color:${CFG.accentColor};font-size:10px" target="_blank">Open App Permissions</a></div></li>
                    <li><span class="dg-check" data-key="audit-security"></span> <div>Check security events<br><a href="https://myaccount.google.com/security" style="color:${CFG.accentColor};font-size:10px" target="_blank">Open Security Settings</a></div></li>
                    <li><span class="dg-check" data-key="audit-devices"></span> <div>Review signed-in devices<br><a href="https://myaccount.google.com/device-activity" style="color:${CFG.accentColor};font-size:10px" target="_blank">Open Device Activity</a></div></li>
                    <li><span class="dg-check" data-key="audit-activity"></span> <div>Download & delete activity data<br><a href="https://myactivity.google.com" style="color:${CFG.accentColor};font-size:10px" target="_blank">Open My Activity</a></div></li>
                    <li><span class="dg-check" data-key="audit-ads"></span> <div>Review ad personalization settings<br><a href="https://adssettings.google.com" style="color:${CFG.accentColor};font-size:10px" target="_blank">Open Ad Settings</a></div></li>
                    <li><span class="dg-check" data-key="audit-privacy"></span> <div>Run Google Privacy Checkup<br><a href="https://myaccount.google.com/privacycheckup" style="color:${CFG.accentColor};font-size:10px" target="_blank">Open Privacy Checkup</a></div></li>
                    <li><span class="dg-check" data-key="audit-takeout"></span> <div>Export all data via Google Takeout<br><a href="https://takeout.google.com" style="color:${CFG.accentColor};font-size:10px" target="_blank">Open Google Takeout</a></div></li>
                    <li><span class="dg-check" data-key="audit-forwarding"></span> <div>Set up Gmail forwarding<br><a href="https://mail.google.com/mail/u/0/#settings/fwdandpop" style="color:${CFG.accentColor};font-size:10px" target="_blank">Open Gmail Settings</a></div></li>
                </ul>
                <div class="dg-progress" style="margin-top:12px">
                    <div class="dg-progress-fill" id="dg-audit-progress" style="width:0%"></div>
                </div>
                <div id="dg-audit-status" style="margin-top:6px;font-size:11px;color:${CFG.textMuted}">0 of 8 complete</div>
            </div>
            <div class="dg-section">
                <h4>Quick Links</h4>
                <div class="dg-btn-row" style="flex-direction:column;gap:4px">
                    <a href="https://myaccount.google.com/deleteservices" target="_blank" class="dg-btn dg-btn-secondary" style="text-decoration:none;justify-content:center;color:${CFG.orange}">Delete Individual Google Services</a>
                    <a href="https://myaccount.google.com/deleteaccount" target="_blank" class="dg-btn dg-btn-secondary" style="text-decoration:none;justify-content:center;color:${CFG.red}">Delete Entire Google Account</a>
                </div>
                <p style="margin-top:8px;font-size:10px;color:${CFG.red}">Only delete your account after confirming ALL data has been migrated successfully.</p>
            </div>
        `;

        const panel = createPanel('Account Audit', 'DeGoogler Browser Assistant', bodyHTML);
        document.body.appendChild(panel);

        function updateAuditProgress() {
            const checks = panel.querySelectorAll('.dg-check[data-key^="audit-"]');
            let done = 0;
            checks.forEach(c => { if (c.classList.contains('checked')) done++; });
            const pct = Math.round((done / checks.length) * 100);
            const progressFill = document.getElementById('dg-audit-progress');
            const statusEl = document.getElementById('dg-audit-status');
            if (progressFill) progressFill.style.width = pct + '%';
            if (statusEl) statusEl.textContent = `${done} of ${checks.length} complete`;
        }

        // Persist checklist state
        panel.querySelectorAll('.dg-check[data-key]').forEach(check => {
            const key = check.dataset.key;
            if (GM_getValue(key, false)) {
                check.classList.add('checked');
                check.textContent = '\u2713';
            }
            check.addEventListener('click', () => {
                check.classList.toggle('checked');
                const isChecked = check.classList.contains('checked');
                check.textContent = isChecked ? '\u2713' : '';
                GM_setValue(key, isChecked);
                updateAuditProgress();
            });
        });
        updateAuditProgress();
    }

    // ═══════════════════════════════════════════════
    // MODULE: Gmail Migration Helper
    // ═══════════════════════════════════════════════
    function initGmailHelper() {
        const bodyHTML = `
            <div class="dg-section">
                <h4>Gmail Migration Steps</h4>
                <ul class="dg-checklist">
                    <li><span class="dg-check" data-key="gmail-forward"></span> <div>Set up forwarding to new email<br><span style="font-size:10px;color:${CFG.textMuted}">Settings > Forwarding and POP/IMAP</span></div></li>
                    <li><span class="dg-check" data-key="gmail-autorespond"></span> <div>Create auto-reply with new address<br><span style="font-size:10px;color:${CFG.textMuted}">Settings > Vacation responder</span></div></li>
                    <li><span class="dg-check" data-key="gmail-filters"></span> <div>Export filter list for reference<br><span style="font-size:10px;color:${CFG.textMuted}">Settings > Filters > Export</span></div></li>
                    <li><span class="dg-check" data-key="gmail-contacts"></span> <div>Export contacts from Google Contacts<br><a href="https://contacts.google.com" style="color:${CFG.accentColor};font-size:10px" target="_blank">Open Contacts</a></div></li>
                    <li><span class="dg-check" data-key="gmail-labels"></span> <div>Note your label/folder structure<br><span style="font-size:10px;color:${CFG.textMuted}">Replicate in your new email service</span></div></li>
                    <li><span class="dg-check" data-key="gmail-update-critical"></span> <div>Update email on critical accounts<br><span style="font-size:10px;color:${CFG.textMuted}">Banking, insurance, government, medical</span></div></li>
                    <li><span class="dg-check" data-key="gmail-update-social"></span> <div>Update email on social accounts<br><span style="font-size:10px;color:${CFG.textMuted}">Social media, subscriptions, newsletters</span></div></li>
                    <li><span class="dg-check" data-key="gmail-notify"></span> <div>Email contacts your new address<br><span style="font-size:10px;color:${CFG.textMuted}">Send a brief "I've moved" email</span></div></li>
                </ul>
            </div>
            <div class="dg-section">
                <h4>Forwarding Quick Setup</h4>
                <p>Click below to jump directly to Gmail's forwarding settings:</p>
                <div class="dg-btn-row">
                    <a href="https://mail.google.com/mail/u/0/#settings/fwdandpop" class="dg-btn dg-btn-primary" style="text-decoration:none">Open Forwarding Settings</a>
                    <a href="https://mail.google.com/mail/u/0/#settings/general" class="dg-btn dg-btn-secondary" style="text-decoration:none">Vacation Responder</a>
                </div>
            </div>
        `;

        const panel = createPanel('Gmail Migration', 'DeGoogler Browser Assistant', bodyHTML);
        document.body.appendChild(panel);
        panel.classList.add('dg-collapsed');

        // Persist checklist
        panel.querySelectorAll('.dg-check[data-key]').forEach(check => {
            const key = check.dataset.key;
            if (GM_getValue(key, false)) {
                check.classList.add('checked');
                check.textContent = '\u2713';
            }
            check.addEventListener('click', () => {
                check.classList.toggle('checked');
                const isChecked = check.classList.contains('checked');
                check.textContent = isChecked ? '\u2713' : '';
                GM_setValue(key, isChecked);
            });
        });
    }

    // ═══════════════════════════════════════════════
    // MODULE: Connected Services Auditor
    // ═══════════════════════════════════════════════
    function initConnectedServicesAuditor() {
        // ── Persistent service store ──
        const STORE_KEY = 'dg-connected-services';
        function loadServices() {
            try { return JSON.parse(GM_getValue(STORE_KEY, '[]')); }
            catch { return []; }
        }
        function saveServices(svcs) { GM_setValue(STORE_KEY, JSON.stringify(svcs)); }
        function genId() { return Date.now().toString(36) + Math.random().toString(36).slice(2,6); }

        // ── Known service domain map ──
        const DOMAIN_MAP = {
            'amazon': 'amazon.com', 'apple': 'appleid.apple.com', 'adobe': 'account.adobe.com',
            'airbnb': 'airbnb.com', 'asana': 'asana.com', 'atlassian': 'id.atlassian.com',
            'bitbucket': 'bitbucket.org', 'canva': 'canva.com', 'capcut': 'capcut.com',
            'cesium ion': 'ion.cesium.com', 'chatgpt': 'chatgpt.com', 'claude': 'claude.ai',
            'cloudflare': 'dash.cloudflare.com', 'coinbase': 'coinbase.com',
            'cursor': 'cursor.com', 'deepseek': 'chat.deepseek.com',
            'deviantart': 'deviantart.com', 'digg': 'digg.com', 'discogs': 'discogs.com',
            'discord': 'discord.com', 'distrokid': 'distrokid.com', 'dropbox': 'dropbox.com',
            'ebay': 'ebay.com', 'elevenlabs': 'elevenlabs.io', 'em client': 'emclient.com',
            'epic games': 'epicgames.com', 'etsy': 'etsy.com', 'evernote': 'evernote.com',
            'facebook': 'facebook.com', 'figma': 'figma.com', 'fiverr': 'fiverr.com',
            'github': 'github.com', 'gitlab': 'gitlab.com', 'grammarly': 'grammarly.com',
            'heygen': 'heygen.com', 'hulu': 'hulu.com', 'ideogram': 'ideogram.ai',
            'imdb': 'imdb.com', 'indeed': 'indeed.com', 'instagram': 'instagram.com',
            'jira': 'atlassian.net', 'klingai': 'klingai.com', 'linkedin': 'linkedin.com',
            'maptiler': 'maptiler.com', 'marketplace': 'facebook.com/marketplace',
            'medium': 'medium.com', 'messenger': 'messenger.com', 'microsoft': 'account.microsoft.com',
            'microsoft copilot': 'copilot.microsoft.com', 'musixmatch': 'musixmatch.com',
            'netflix': 'netflix.com', 'notion': 'notion.so', 'nocodexport': 'nocodexport.com',
            'openai': 'openai.com', 'openrouter': 'openrouter.ai', 'paypal': 'paypal.com',
            'perplexity': 'perplexity.ai', 'perplexity ask': 'perplexity.ai',
            'pexels': 'pexels.com', 'pinterest': 'pinterest.com', 'pixabay': 'pixabay.com',
            'rclone': 'rclone.org', 'recall': 'recall.ai', 'reddit': 'reddit.com',
            'reddit enhancement suite': 'reddit.com', 'robinhood': 'robinhood.com',
            'runway': 'runway.com', 'shopify': 'shopify.com', 'slack': 'slack.com',
            'snapchat': 'snapchat.com', 'snippets ai': 'snippets.ai',
            'sorrywatermark': 'sorrywatermark.com', 'spotify': 'spotify.com',
            'steam': 'store.steampowered.com', 'stripe': 'stripe.com', 'stylebot': 'stylebot.dev',
            'stylus extension': 'add0n.com/stylus.html', 'suno': 'suno.com',
            'swift backup': 'swiftbackup.com', 'tampermonkey': 'tampermonkey.net',
            'ticktick': 'ticktick.com', 'tiktok': 'tiktok.com', 'tinyurl': 'tinyurl.com',
            'trello': 'trello.com', 'tumblr': 'tumblr.com', 'twitch': 'twitch.tv',
            'twitter': 'twitter.com', 'uber': 'uber.com', 'venmo': 'venmo.com',
            'violentmonkey': 'violentmonkey.github.io', 'vmake': 'vmake.ai',
            'x': 'x.com', 'yahoo': 'login.yahoo.com', 'yelp': 'yelp.com', 'zoom': 'zoom.us',
        };

        // Common password reset URL patterns
        const RESET_PATTERNS = [
            '/forgot-password', '/account/forgot', '/reset-password',
            '/password/reset', '/auth/forgot', '/forgot',
        ];

        function getDomain(name) {
            const lower = name.toLowerCase().trim();
            // Direct match
            if (DOMAIN_MAP[lower]) return DOMAIN_MAP[lower];
            // Partial match
            for (const [key, domain] of Object.entries(DOMAIN_MAP)) {
                if (lower.includes(key) || key.includes(lower)) return domain;
            }
            // Domain-looking names (e.g. "chat.deepseek.com")
            if (/^[\w-]+\.[\w-]+\.\w+$/.test(lower)) return lower;
            // Fallback: construct from name
            const slug = lower.replace(/[^a-z0-9]/g, '');
            return slug ? slug + '.com' : null;
        }

        function getResetUrl(domain) {
            if (!domain) return null;
            const base = domain.startsWith('http') ? domain : 'https://' + domain;
            return base + '/forgot-password';
        }

        function getLoginUrl(domain) {
            if (!domain) return null;
            return domain.startsWith('http') ? domain : 'https://' + domain;
        }

        // Migration steps per auth type
        const STEPS_OAUTH = [
            { key: 'password', label: 'Set Password' },
            { key: 'email', label: 'Update Email' },
            { key: 'disconnect', label: 'Revoke Google' },
            { key: 'verified', label: 'Verified' }
        ];
        const STEPS_EMAIL = [
            { key: 'email', label: 'Update Email' },
            { key: 'verified', label: 'Verified' }
        ];
        const STEPS_ACCESS = [
            { key: 'review', label: 'Review Access' },
            { key: 'disconnect', label: 'Revoke' },
            { key: 'verified', label: 'Verified' }
        ];

        function getSteps(type) {
            return type === 'oauth' ? STEPS_OAUTH : type === 'access' ? STEPS_ACCESS : STEPS_EMAIL;
        }

        // Priority auto-classification
        const CRITICAL_KW = ['bank','chase','wells fargo','capital one','citi','fidelity','schwab','vanguard','paypal','venmo','zelle','irs','ssa','gov','healthcare','insurance','geico','state farm','medicare','medicaid','anthem','kaiser','tax','turbotax','intuit','credit','loan','mortgage','coinbase','robinhood'];
        const IMPORTANT_KW = ['amazon','microsoft','apple','github','gitlab','slack','zoom','dropbox','linkedin','indeed','notion','figma','adobe','canva','trello','asana','jira','heroku','aws','azure','netlify','vercel','cloudflare','domain','godaddy','namecheap','shopify','stripe','square','spotify','netflix','hulu','disney','openai','chatgpt','claude','cursor','elevenlabs'];

        function autoClassify(name) {
            const l = name.toLowerCase();
            if (CRITICAL_KW.some(k => l.includes(k))) return 'critical';
            if (IMPORTANT_KW.some(k => l.includes(k))) return 'important';
            return 'optional';
        }

        const bodyHTML = `
            <div class="dg-stat-grid" id="dg-svc-stats">
                <div class="dg-stat-box"><div class="dg-stat-num" id="dg-stat-total">0</div><div class="dg-stat-label">Total Services</div></div>
                <div class="dg-stat-box"><div class="dg-stat-num" id="dg-stat-migrated" style="color:${CFG.green}">0</div><div class="dg-stat-label">Fully Migrated</div></div>
                <div class="dg-stat-box"><div class="dg-stat-num" id="dg-stat-inprogress" style="color:${CFG.orange}">0</div><div class="dg-stat-label">In Progress</div></div>
                <div class="dg-stat-box"><div class="dg-stat-num" id="dg-stat-pending" style="color:${CFG.red}">0</div><div class="dg-stat-label">Not Started</div></div>
            </div>
            <div class="dg-progress" style="margin-bottom:12px">
                <div class="dg-progress-fill" id="dg-svc-progress" style="width:0%"></div>
            </div>
            <div class="dg-section">
                <h4>Scan Google Connections</h4>
                <p>Reads "Sign in with Google" and "Account access" lists from this page. Click a tab below then Scan to capture that category.</p>
                <div class="dg-btn-row">
                    <button class="dg-btn dg-btn-primary" id="dg-svc-scan-signin">Scan Sign-In Apps</button>
                    <button class="dg-btn dg-btn-secondary" id="dg-svc-scan-access">Scan Access Apps</button>
                    <button class="dg-btn dg-btn-secondary" id="dg-svc-scan-all">Scan All (Both)</button>
                </div>
                <div id="dg-svc-scan-status" style="margin-top:8px;font-size:11px;color:${CFG.textMuted}"></div>
            </div>
            <div class="dg-section">
                <h4>Add Service Manually</h4>
                <p>For accounts not connected via Google OAuth (email-only registrations).</p>
                <div class="dg-input-row">
                    <input class="dg-input" id="dg-svc-name" placeholder="Service name (e.g. Amazon, Chase)"/>
                    <select class="dg-select" id="dg-svc-type">
                        <option value="oauth">OAuth</option>
                        <option value="email" selected>Email Only</option>
                        <option value="access">Data Access</option>
                    </select>
                </div>
                <div class="dg-input-row">
                    <select class="dg-select" id="dg-svc-priority" style="flex:1">
                        <option value="critical">Critical (banking, gov, medical)</option>
                        <option value="important">Important (work, subscriptions)</option>
                        <option value="optional" selected>Optional (social, forums)</option>
                    </select>
                    <button class="dg-btn dg-btn-primary" id="dg-svc-add" style="padding:7px 14px">Add</button>
                </div>
            </div>
            <div class="dg-section" style="padding-bottom:6px">
                <div style="display:flex;align-items:center;justify-content:space-between;margin-bottom:8px">
                    <h4 style="margin:0">Connected Services</h4>
                    <button class="dg-btn dg-btn-secondary" id="dg-svc-export" style="padding:4px 10px;font-size:10px">Export CSV</button>
                </div>
                <div class="dg-tabs" id="dg-svc-tabs">
                    <button class="dg-tab active" data-filter="all">All</button>
                    <button class="dg-tab" data-filter="critical">Critical</button>
                    <button class="dg-tab" data-filter="important">Important</button>
                    <button class="dg-tab" data-filter="optional">Optional</button>
                    <button class="dg-tab" data-filter="done">Done</button>
                </div>
                <div id="dg-svc-list"></div>
                <div id="dg-svc-empty" style="text-align:center;padding:20px 0;font-size:11px;color:${CFG.textMuted}">
                    No services tracked yet. Click a Scan button above to auto-detect connected apps.
                </div>
            </div>
            <div class="dg-section">
                <h4>Common Forgotten Services</h4>
                <p>Click to add any you use:</p>
                <div class="dg-btn-row" style="flex-wrap:wrap" id="dg-svc-quickadd"></div>
            </div>
        `;

        const panel = createPanel('Connected Services', 'DeGoogler Browser Assistant', bodyHTML);
        document.body.appendChild(panel);

        const listEl = document.getElementById('dg-svc-list');
        const emptyEl = document.getElementById('dg-svc-empty');
        const statusEl = document.getElementById('dg-svc-scan-status');
        let activeFilter = 'all';

        // ── DOM Scraper ──
        // Scrapes Google's connections page using the actual DOM selectors from MHTML analysis
        async function scrapeApps(type) {
            const services = loadServices();
            let found = 0;
            const authType = type === 'signin' ? 'oauth' : 'access';

            // If we need to switch tabs, click the appropriate chip
            if (type === 'signin') {
                // Click "Sign in with Google" tab chip
                const signinChip = document.querySelector('[data-input-chip-label*="Sign in with Google"]');
                const signinChipAlt = document.querySelector('[data-relationship-type="4"]');
                const chip = signinChip || signinChipAlt;
                if (chip) {
                    chip.click();
                    await new Promise(r => setTimeout(r, 800));
                }
            } else if (type === 'access') {
                // Click "Access to" tab chip
                const accessChip = document.querySelector('[data-input-chip-label*="Access to"]');
                const accessChipAlt = document.querySelector('[data-relationship-type="3"]');
                const chip = accessChip || accessChipAlt;
                if (chip) {
                    chip.click();
                    await new Promise(r => setTimeout(r, 800));
                }
            }

            // Wait for apps to render
            await new Promise(r => setTimeout(r, 500));

            // Primary selector: a[data-provider-index] with .mMsbvc name
            const appLinks = document.querySelectorAll('a[data-provider-index]');

            appLinks.forEach(link => {
                const nameEl = link.querySelector('.mMsbvc');
                if (!nameEl) return;
                const name = nameEl.textContent.trim();
                if (!name || name.length < 2) return;

                // Skip if already tracked
                if (services.some(s => s.name.toLowerCase() === name.toLowerCase())) return;

                const detailUrl = link.href || '';
                const iconEl = link.querySelector('img.bLJ69, img[role="presentation"]');
                const iconUrl = iconEl ? iconEl.src : '';
                const domain = getDomain(name);

                services.push({
                    id: genId(),
                    name: name,
                    type: authType,
                    priority: autoClassify(name),
                    steps: {},
                    domain: domain,
                    detailUrl: detailUrl,
                    iconUrl: iconUrl,
                    addedAt: Date.now(),
                    source: 'scan'
                });
                found++;
            });

            // Fallback: if primary selector found nothing, try broader selectors
            if (found === 0) {
                // Try c-wiz based card structures
                const cards = document.querySelectorAll('[data-provider-index]');
                cards.forEach(card => {
                    const parent = card.closest('a') || card;
                    const nameEl = parent.querySelector('.mMsbvc') || parent.querySelector('div[class*="mMsbvc"]');
                    if (!nameEl) return;
                    const name = nameEl.textContent.trim();
                    if (!name || name.length < 2 || services.some(s => s.name.toLowerCase() === name.toLowerCase())) return;

                    const domain = getDomain(name);
                    services.push({
                        id: genId(),
                        name: name,
                        type: authType,
                        priority: autoClassify(name),
                        steps: {},
                        domain: domain,
                        detailUrl: parent.href || '',
                        iconUrl: '',
                        addedAt: Date.now(),
                        source: 'scan-fallback'
                    });
                    found++;
                });
            }

            saveServices(services);
            return found;
        }

        // ── Scan buttons ──
        document.getElementById('dg-svc-scan-signin').addEventListener('click', async () => {
            statusEl.textContent = 'Clicking "Sign in with Google" tab...';
            statusEl.style.color = CFG.orange;
            const found = await scrapeApps('signin');
            statusEl.textContent = found > 0
                ? `Found ${found} new Sign-in apps`
                : 'No new Sign-in apps found. Make sure the "Sign in with Google" tab is active.';
            statusEl.style.color = found > 0 ? CFG.green : CFG.textMuted;
            renderList();
        });

        document.getElementById('dg-svc-scan-access').addEventListener('click', async () => {
            statusEl.textContent = 'Clicking "Access to" tab...';
            statusEl.style.color = CFG.orange;
            const found = await scrapeApps('access');
            statusEl.textContent = found > 0
                ? `Found ${found} new Account Access apps`
                : 'No new Access apps found. Make sure the "Access to" tab is active.';
            statusEl.style.color = found > 0 ? CFG.green : CFG.textMuted;
            renderList();
        });

        document.getElementById('dg-svc-scan-all').addEventListener('click', async () => {
            statusEl.textContent = 'Scanning Sign-in apps...';
            statusEl.style.color = CFG.orange;
            const found1 = await scrapeApps('signin');
            statusEl.textContent = `Found ${found1} Sign-in apps. Now scanning Access apps...`;
            await new Promise(r => setTimeout(r, 500));
            const found2 = await scrapeApps('access');
            const total = found1 + found2;
            statusEl.textContent = total > 0
                ? `Scan complete: ${found1} Sign-in + ${found2} Access = ${total} new apps`
                : 'No new apps found. They may already be in your list.';
            statusEl.style.color = total > 0 ? CFG.green : CFG.textMuted;
            renderList();
        });

        // ── Quick-add common services ──
        const commonServices = [
            { name: 'Amazon', type: 'email', pri: 'important' },
            { name: 'PayPal', type: 'email', pri: 'critical' },
            { name: 'Netflix', type: 'email', pri: 'important' },
            { name: 'Spotify', type: 'email', pri: 'important' },
            { name: 'Apple ID', type: 'email', pri: 'critical' },
            { name: 'Microsoft', type: 'email', pri: 'important' },
            { name: 'GitHub', type: 'oauth', pri: 'important' },
            { name: 'LinkedIn', type: 'email', pri: 'important' },
            { name: 'Facebook', type: 'email', pri: 'optional' },
            { name: 'Reddit', type: 'email', pri: 'optional' },
            { name: 'Discord', type: 'email', pri: 'optional' },
            { name: 'Twitch', type: 'oauth', pri: 'optional' },
            { name: 'Bank (Primary)', type: 'email', pri: 'critical' },
            { name: 'Credit Card', type: 'email', pri: 'critical' },
            { name: 'Health Insurance', type: 'email', pri: 'critical' },
            { name: 'IRS / Tax Service', type: 'email', pri: 'critical' },
            { name: 'Employer/HR Portal', type: 'email', pri: 'critical' },
            { name: 'Domain Registrar', type: 'email', pri: 'important' },
            { name: 'Cloud Hosting', type: 'email', pri: 'important' },
            { name: 'Adobe', type: 'email', pri: 'important' },
            { name: 'Steam', type: 'email', pri: 'optional' },
            { name: 'Uber/Lyft', type: 'email', pri: 'optional' },
            { name: 'DoorDash/UberEats', type: 'email', pri: 'optional' },
            { name: 'Airbnb', type: 'email', pri: 'optional' },
        ];

        const quickAddEl = document.getElementById('dg-svc-quickadd');
        function refreshQuickAdd() {
            const existing = loadServices();
            quickAddEl.querySelectorAll('button').forEach(btn => {
                const tracked = existing.some(s => s.name.toLowerCase() === btn.textContent.toLowerCase());
                btn.style.opacity = tracked ? '0.3' : '1';
                btn.style.pointerEvents = tracked ? 'none' : 'auto';
            });
        }

        commonServices.forEach(svc => {
            const btn = document.createElement('button');
            btn.className = 'dg-btn dg-btn-secondary';
            btn.style.cssText = 'padding:4px 10px;font-size:10px;margin:0';
            btn.textContent = svc.name;
            btn.addEventListener('click', () => {
                const services = loadServices();
                if (services.some(s => s.name.toLowerCase() === svc.name.toLowerCase())) {
                    showToast(svc.name + ' already tracked'); return;
                }
                const domain = getDomain(svc.name);
                services.push({
                    id: genId(), name: svc.name, type: svc.type, priority: svc.pri,
                    steps: {}, domain: domain, detailUrl: '', iconUrl: '',
                    addedAt: Date.now(), source: 'manual'
                });
                saveServices(services);
                renderList();
                refreshQuickAdd();
                showToast('Added ' + svc.name);
            });
            quickAddEl.appendChild(btn);
        });

        // ── Render service list ──
        function renderList() {
            const services = loadServices();
            listEl.innerHTML = TTP.createHTML('');

            let filtered = services;
            if (activeFilter === 'done') {
                filtered = services.filter(s => getSteps(s.type).every(st => s.steps[st.key]));
            } else if (activeFilter !== 'all') {
                filtered = services.filter(s => s.priority === activeFilter);
            }

            const priOrder = { critical: 0, important: 1, optional: 2 };
            filtered.sort((a, b) => {
                const aDone = getSteps(a.type).every(st => a.steps[st.key]);
                const bDone = getSteps(b.type).every(st => b.steps[st.key]);
                if (aDone !== bDone) return aDone ? 1 : -1;
                return (priOrder[a.priority] || 2) - (priOrder[b.priority] || 2);
            });

            emptyEl.style.display = filtered.length === 0 ? 'block' : 'none';

            filtered.forEach(svc => {
                const steps = getSteps(svc.type);
                const allDone = steps.every(st => svc.steps[st.key]);
                const domain = svc.domain || getDomain(svc.name);
                const loginUrl = getLoginUrl(domain);

                const card = document.createElement('div');
                card.className = 'dg-app-card';
                if (allDone) card.style.opacity = '0.5';

                const typeClass = svc.type === 'oauth' ? 'dg-type-oauth' : svc.type === 'access' ? 'dg-type-billing' : 'dg-type-email';
                const typeLabel = svc.type === 'oauth' ? 'Sign-In' : svc.type === 'access' ? 'Access' : 'Email';
                const priClass = svc.priority === 'critical' ? 'dg-pri-critical' : svc.priority === 'important' ? 'dg-pri-important' : 'dg-pri-optional';
                const priLabel = svc.priority.charAt(0).toUpperCase() + svc.priority.slice(1);

                let cardHTML = '<div class="dg-app-row">';
                cardHTML += '<span class="dg-priority-label ' + priClass + '">' + priLabel + '</span>';
                cardHTML += '<span class="dg-app-name">' + svc.name + '</span>';
                cardHTML += '<span class="dg-app-type ' + typeClass + '">' + typeLabel + '</span>';
                cardHTML += '<button class="dg-app-delete" data-id="' + svc.id + '" title="Remove">x</button>';
                cardHTML += '</div>';

                // Domain + action links row
                if (domain || svc.detailUrl) {
                    cardHTML += '<div style="display:flex;gap:6px;margin-top:6px;flex-wrap:wrap">';
                    if (domain) {
                        cardHTML += '<a href="' + (loginUrl || '#') + '" target="_blank" rel="noopener" style="font-size:9px;color:' + CFG.accentColor + ';text-decoration:none;padding:2px 6px;border:1px solid ' + CFG.border + ';border-radius:3px">' + domain + '</a>';
                    }
                    if (loginUrl && svc.type === 'oauth') {
                        cardHTML += '<a href="' + loginUrl + '" target="_blank" rel="noopener" style="font-size:9px;color:' + CFG.orange + ';text-decoration:none;padding:2px 6px;border:1px solid ' + CFG.border + ';border-radius:3px">Login</a>';
                    }
                    if (svc.detailUrl) {
                        cardHTML += '<a href="' + svc.detailUrl + '" target="_blank" rel="noopener" style="font-size:9px;color:' + CFG.textMuted + ';text-decoration:none;padding:2px 6px;border:1px solid ' + CFG.border + ';border-radius:3px">Google Details</a>';
                    }
                    cardHTML += '</div>';
                }

                // Migration step pills
                cardHTML += '<div class="dg-app-steps">';
                steps.forEach((st, idx) => {
                    const done = svc.steps[st.key];
                    const isNext = !done && (idx === 0 || svc.steps[steps[idx-1].key]);
                    const cls = done ? 'done' : isNext ? 'active' : '';
                    cardHTML += '<button class="dg-step-pill ' + cls + '" data-id="' + svc.id + '" data-step="' + st.key + '">' + (done ? '\u2713 ' : '') + st.label + '</button>';
                });
                cardHTML += '</div>';

                card.innerHTML = TTP.createHTML(cardHTML);
                listEl.appendChild(card);
            });

            // Wire step clicks
            listEl.querySelectorAll('.dg-step-pill').forEach(pill => {
                pill.addEventListener('click', () => {
                    const svcs = loadServices();
                    const svc = svcs.find(s => s.id === pill.dataset.id);
                    if (!svc) return;
                    svc.steps[pill.dataset.step] = !svc.steps[pill.dataset.step];
                    saveServices(svcs);
                    renderList();
                });
            });

            // Wire delete clicks
            listEl.querySelectorAll('.dg-app-delete').forEach(btn => {
                btn.addEventListener('click', () => {
                    let svcs = loadServices();
                    svcs = svcs.filter(s => s.id !== btn.dataset.id);
                    saveServices(svcs);
                    renderList();
                    refreshQuickAdd();
                });
            });

            updateStats();
            refreshQuickAdd();
        }

        function updateStats() {
            const services = loadServices();
            let total = services.length, migrated = 0, inProgress = 0, pending = 0;
            services.forEach(svc => {
                const steps = getSteps(svc.type);
                const done = steps.filter(st => svc.steps[st.key]).length;
                if (done === steps.length) migrated++;
                else if (done > 0) inProgress++;
                else pending++;
            });
            const el = (id) => document.getElementById(id);
            el('dg-stat-total').textContent = total;
            el('dg-stat-migrated').textContent = migrated;
            el('dg-stat-inprogress').textContent = inProgress;
            el('dg-stat-pending').textContent = pending;
            el('dg-svc-progress').style.width = (total > 0 ? Math.round((migrated / total) * 100) : 0) + '%';
        }

        // ── Tab filtering ──
        document.getElementById('dg-svc-tabs').addEventListener('click', e => {
            if (!e.target.classList.contains('dg-tab')) return;
            document.querySelectorAll('#dg-svc-tabs .dg-tab').forEach(t => t.classList.remove('active'));
            e.target.classList.add('active');
            activeFilter = e.target.dataset.filter;
            renderList();
        });

        // ── Manual add ──
        document.getElementById('dg-svc-add').addEventListener('click', () => {
            const nameInput = document.getElementById('dg-svc-name');
            const name = nameInput.value.trim();
            if (!name) return;
            const type = document.getElementById('dg-svc-type').value;
            const priority = document.getElementById('dg-svc-priority').value;
            const services = loadServices();
            if (services.some(s => s.name.toLowerCase() === name.toLowerCase())) {
                showToast(name + ' already tracked'); return;
            }
            const domain = getDomain(name);
            services.push({
                id: genId(), name: name, type: type, priority: priority,
                steps: {}, domain: domain, detailUrl: '', iconUrl: '',
                addedAt: Date.now(), source: 'manual'
            });
            saveServices(services);
            nameInput.value = '';
            renderList();
            showToast('Added ' + name);
        });

        document.getElementById('dg-svc-name').addEventListener('keydown', e => {
            if (e.key === 'Enter') document.getElementById('dg-svc-add').click();
        });

        document.getElementById('dg-svc-name').addEventListener('input', e => {
            const name = e.target.value.trim();
            if (name.length > 2) {
                document.getElementById('dg-svc-priority').value = autoClassify(name);
            }
        });

        // ── Export CSV ──
        document.getElementById('dg-svc-export').addEventListener('click', () => {
            const services = loadServices();
            if (services.length === 0) { showToast('No services to export'); return; }

            let csv = 'Service Name,Auth Type,Priority,Status,Domain,Login URL,Google Detail URL,Set Password,Update Email,Review Access,Revoke Google,Verified\n';
            services.forEach(svc => {
                const steps = getSteps(svc.type);
                const done = steps.filter(st => svc.steps[st.key]).length;
                const status = done === steps.length ? 'Complete' : done > 0 ? 'In Progress' : 'Not Started';
                const safeName = svc.name.replace(/"/g, '""');
                const domain = svc.domain || getDomain(svc.name) || '';
                const loginUrl = svc.type === 'oauth' ? (getLoginUrl(domain) || '') : '';
                csv += '"' + safeName + '",' + svc.type + ',' + svc.priority + ',' + status + ',';
                csv += '"' + domain + '","' + loginUrl + '","' + (svc.detailUrl || '') + '",';
                csv += (svc.steps.password ? 'Yes' : '-') + ',';
                csv += (svc.steps.email ? 'Yes' : 'No') + ',';
                csv += (svc.steps.review ? 'Yes' : '-') + ',';
                csv += (svc.steps.disconnect ? 'Yes' : '-') + ',';
                csv += (svc.steps.verified ? 'Yes' : 'No') + '\n';
            });

            const blob = new Blob([csv], { type: 'text/csv' });
            const url = URL.createObjectURL(blob);
            const a = document.createElement('a');
            a.href = url;
            a.download = 'connected-services-audit-' + new Date().toISOString().split('T')[0] + '.csv';
            a.click();
            URL.revokeObjectURL(url);
            showToast('Exported ' + services.length + ' services to CSV');
        });

        // Initial render
        renderList();
    }

    // ═══════════════════════════════════════════════
    // MODULE: GitHub Pages Sync Bridge
    // ═══════════════════════════════════════════════
    function initPageSync() {
        // Send tracked services to the landing page via postMessage
        const STORE_KEY = 'dg-connected-services';
        let data = [];
        try { data = JSON.parse(GM_getValue(STORE_KEY, '[]')); }
        catch { data = []; }

        if (data.length > 0) {
            // postMessage to the page
            window.postMessage({ type: 'degoogler-sync', services: data }, '*');

            // Also inject as hidden element for fallback
            const el = document.createElement('div');
            el.id = 'degoogler-userscript-data';
            el.style.display = 'none';
            el.textContent = JSON.stringify(data);
            document.body.appendChild(el);
        }

        // Listen for requests from the page
        window.addEventListener('message', (event) => {
            if (event.data && event.data.type === 'degoogler-request-sync') {
                window.postMessage({ type: 'degoogler-sync', services: data }, '*');
            }
        });
    }

    // ── Route to correct module ──
    function init() {
        GM_addStyle(STYLES);

        // Remove anti-FOUC
        const af = document.getElementById('degoogler-antifouc');
        if (af) af.remove();

        const host = location.hostname;
        const path = location.pathname;

        if (host === 'takeout.google.com') {
            initTakeoutHelper();
        } else if (host === 'myaccount.google.com') {
            if (path.includes('/permissions') || path.includes('/connections')) {
                initConnectedServicesAuditor();
            } else {
                initAccountAudit();
                if (path.includes('/security')) {
                    initConnectedServicesAuditor();
                }
            }
        } else if (host === 'mail.google.com') {
            initGmailHelper();
        } else if (host === 'www.youtube.com') {
            initYouTubeExporter();
        } else if (host === 'sysadmindoc.github.io') {
            initPageSync();
        }
    }

    // ── Start ──
    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', init);
    } else {
        init();
    }
})();
