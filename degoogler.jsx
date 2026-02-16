import { useState, useEffect, useCallback, useRef } from "react";

/* ═══════════════════════════════════════════════════════════════
   DeGoogler v0.0.1 — Interactive Google Services Migration Wizard
   ═══════════════════════════════════════════════════════════════ */

// ── Color Palette ──
const C = {
  bg: "#0a0a0f",
  bgCard: "#12121a",
  bgCardHover: "#1a1a26",
  bgElevated: "#16161f",
  bgInput: "#0e0e16",
  border: "#1e1e2e",
  borderActive: "#3b82f6",
  text: "#e2e2ef",
  textMuted: "#6b6b80",
  textDim: "#44445a",
  accent: "#3b82f6",
  accentGlow: "rgba(59,130,246,0.15)",
  accentSoft: "rgba(59,130,246,0.08)",
  green: "#22c55e",
  greenGlow: "rgba(34,197,94,0.15)",
  greenSoft: "rgba(34,197,94,0.08)",
  orange: "#f59e0b",
  orangeGlow: "rgba(245,158,11,0.15)",
  red: "#ef4444",
  redGlow: "rgba(239,68,68,0.12)",
  purple: "#a855f7",
  purpleGlow: "rgba(168,85,247,0.12)",
  cyan: "#06b6d4",
};

// ── Google Services Database ──
const GOOGLE_SERVICES = [
  {
    id: "gmail",
    name: "Gmail",
    icon: "✉",
    category: "Communication",
    difficulty: "Medium",
    desc: "Email service",
    takeoutKey: "Mail",
    alternatives: [
      { id: "protonmail", name: "Proton Mail", icon: "🟣", privacy: 5, cost: "Free / $4+/mo", ease: 4, platforms: "Web, iOS, Android, Desktop (Bridge)", desc: "Swiss-based, end-to-end encrypted email. Gold standard for privacy.", importGuide: "Settings → Import/Export → Import emails from MBOX file", signupUrl: "https://account.proton.me/signup" },
      { id: "tuta", name: "Tuta Mail", icon: "🟢", privacy: 5, cost: "Free / $3+/mo", ease: 4, platforms: "Web, iOS, Android, Desktop", desc: "German E2E encrypted email with built-in calendar. Fully open source.", importGuide: "Currently supports manual migration. Use desktop client for bulk import.", signupUrl: "https://app.tuta.com/signup" },
      { id: "fastmail", name: "Fastmail", icon: "🔵", privacy: 4, cost: "$3+/mo", ease: 5, platforms: "Web, iOS, Android", desc: "Australian privacy-focused email. Excellent UI, great import tools, custom domains.", importGuide: "Settings → Migration → Add Gmail account for automatic import", signupUrl: "https://www.fastmail.com/signup/" },
      { id: "mailbox", name: "Mailbox.org", icon: "🟤", privacy: 5, cost: "€1+/mo", ease: 3, platforms: "Web, IMAP/SMTP", desc: "German privacy email with office suite, calendar, cloud storage. GDPR-first.", importGuide: "Use IMAP migration wizard in admin panel", signupUrl: "https://mailbox.org/en/" },
    ],
  },
  {
    id: "gdrive",
    name: "Google Drive",
    icon: "📁",
    category: "Storage",
    difficulty: "Medium",
    desc: "Cloud storage & file sync",
    takeoutKey: "Drive",
    alternatives: [
      { id: "protondrive", name: "Proton Drive", icon: "🟣", privacy: 5, cost: "Free 1GB / $4+/mo", ease: 4, platforms: "Web, iOS, Android, Desktop", desc: "E2E encrypted cloud storage from Proton. Integrates with Proton ecosystem.", importGuide: "Upload files directly through web or desktop client", signupUrl: "https://account.proton.me/signup" },
      { id: "nextcloud", name: "Nextcloud", icon: "🔵", privacy: 5, cost: "Free (self-hosted) / Hosted plans vary", ease: 2, platforms: "Web, iOS, Android, Desktop", desc: "Self-hosted cloud platform. Full Google Workspace replacement. Maximum control.", importGuide: "Upload via desktop sync client or web interface. Supports WebDAV.", signupUrl: "https://nextcloud.com/signup/" },
      { id: "tresorit", name: "Tresorit", icon: "🟢", privacy: 5, cost: "$11+/mo", ease: 5, platforms: "Web, iOS, Android, Desktop", desc: "Swiss E2E encrypted cloud storage. Business-grade with zero-knowledge encryption.", importGuide: "Install desktop app → drag and drop files from Takeout export", signupUrl: "https://tresorit.com/pricing" },
      { id: "filen", name: "Filen", icon: "⚪", privacy: 5, cost: "Free 10GB / $2+/mo", ease: 4, platforms: "Web, iOS, Android, Desktop", desc: "German zero-knowledge encrypted cloud. Fast uploads, generous free tier.", importGuide: "Upload via web or desktop client from Takeout export folder", signupUrl: "https://filen.io/r" },
    ],
  },
  {
    id: "gsearch",
    name: "Google Search",
    icon: "🔍",
    category: "Web",
    difficulty: "Easy",
    desc: "Web search engine",
    takeoutKey: null,
    alternatives: [
      { id: "duckduckgo", name: "DuckDuckGo", icon: "🦆", privacy: 5, cost: "Free", ease: 5, platforms: "Web, Browser, iOS, Android", desc: "Most popular private search engine. No tracking, no search history stored.", importGuide: "Set as default search engine in your browser settings", signupUrl: "https://duckduckgo.com" },
      { id: "brave_search", name: "Brave Search", icon: "🦁", privacy: 5, cost: "Free / $3/mo premium", ease: 5, platforms: "Web, Brave Browser", desc: "Independent index (not reliant on Google/Bing). Built by Brave Software.", importGuide: "Set as default in browser or visit search.brave.com", signupUrl: "https://search.brave.com" },
      { id: "startpage", name: "Startpage", icon: "🟢", privacy: 5, cost: "Free", ease: 5, platforms: "Web", desc: "Anonymized Google results without the tracking. Best of both worlds.", importGuide: "Set as default search engine or use browser extension", signupUrl: "https://www.startpage.com" },
      { id: "kagi", name: "Kagi", icon: "🟡", privacy: 5, cost: "$5+/mo", ease: 5, platforms: "Web", desc: "Premium ad-free search. Superior results, no tracking, user-funded model.", importGuide: "Create account and set as default search engine", signupUrl: "https://kagi.com" },
    ],
  },
  {
    id: "chrome",
    name: "Chrome",
    icon: "🌐",
    category: "Web",
    difficulty: "Easy",
    desc: "Web browser",
    takeoutKey: null,
    alternatives: [
      { id: "firefox", name: "Firefox", icon: "🦊", privacy: 4, cost: "Free", ease: 5, platforms: "Windows, Mac, Linux, iOS, Android", desc: "Open-source browser by Mozilla. Huge extension library. Community voted #1 for privacy.", importGuide: "Import bookmarks, passwords, and history during first-run setup wizard", signupUrl: "https://www.mozilla.org/firefox/new/" },
      { id: "brave", name: "Brave", icon: "🦁", privacy: 5, cost: "Free", ease: 5, platforms: "Windows, Mac, Linux, iOS, Android", desc: "Chromium-based with built-in ad/tracker blocking, VPN, and privacy features.", importGuide: "Import Chrome data during setup. Extensions are compatible.", signupUrl: "https://brave.com/download/" },
      { id: "librewolf", name: "LibreWolf", icon: "🐺", privacy: 5, cost: "Free", ease: 3, platforms: "Windows, Mac, Linux", desc: "Hardened Firefox fork. Maximum privacy out of the box. No telemetry.", importGuide: "Import Firefox/Chrome bookmarks via Library → Import and Backup", signupUrl: "https://librewolf.net" },
      { id: "vivaldi", name: "Vivaldi", icon: "🎵", privacy: 4, cost: "Free", ease: 5, platforms: "Windows, Mac, Linux, iOS, Android", desc: "Feature-rich Chromium browser. Built-in mail, calendar, notes. No tracking.", importGuide: "Import Chrome data during setup. Chromium extension compatible.", signupUrl: "https://vivaldi.com/download/" },
    ],
  },
  {
    id: "gcalendar",
    name: "Google Calendar",
    icon: "📅",
    category: "Productivity",
    difficulty: "Easy",
    desc: "Calendar & scheduling",
    takeoutKey: "Calendar",
    alternatives: [
      { id: "protoncalendar", name: "Proton Calendar", icon: "🟣", privacy: 5, cost: "Free with Proton", ease: 4, platforms: "Web, iOS, Android", desc: "E2E encrypted calendar. Seamlessly integrates with Proton Mail.", importGuide: "Settings → Import → Upload .ics file from Google Takeout", signupUrl: "https://account.proton.me/signup" },
      { id: "tutacalendar", name: "Tuta Calendar", icon: "🟢", privacy: 5, cost: "Free with Tuta", ease: 4, platforms: "Web, iOS, Android, Desktop", desc: "Encrypted calendar built into Tuta. Zero-knowledge encryption.", importGuide: "Import .ics calendar file through calendar settings", signupUrl: "https://app.tuta.com/signup" },
      { id: "etesync", name: "EteSync", icon: "🔵", privacy: 5, cost: "$2/mo", ease: 3, platforms: "Web, iOS, Android, Desktop (DAV)", desc: "Secure, E2E encrypted calendar/contacts sync. Works with standard CalDAV apps.", importGuide: "Import .ics files via web client or CalDAV-compatible app", signupUrl: "https://www.etesync.com" },
    ],
  },
  {
    id: "gphotos",
    name: "Google Photos",
    icon: "📷",
    category: "Storage",
    difficulty: "Hard",
    desc: "Photo storage & management",
    takeoutKey: "Google Photos",
    alternatives: [
      { id: "immich", name: "Immich", icon: "📸", privacy: 5, cost: "Free (self-hosted)", ease: 2, platforms: "Web, iOS, Android", desc: "Self-hosted Google Photos replacement. AI-powered face/object recognition runs locally.", importGuide: "Use CLI upload tool to bulk import from Takeout. Supports metadata preservation.", signupUrl: "https://immich.app" },
      { id: "ente", name: "Ente Photos", icon: "🟢", privacy: 5, cost: "Free 5GB / $3+/mo", ease: 5, platforms: "Web, iOS, Android, Desktop", desc: "E2E encrypted photo storage. Open source. AI features run on-device.", importGuide: "Desktop app → Import → Select Google Takeout photos folder", signupUrl: "https://ente.io" },
      { id: "photoprism", name: "PhotoPrism", icon: "🌈", privacy: 5, cost: "Free (self-hosted) / $7+/mo hosted", ease: 3, platforms: "Web, iOS (PWA), Android (PWA)", desc: "AI-powered self-hosted photo app. Browse by location, faces, subjects.", importGuide: "Copy photos to import directory, then run indexer via web UI", signupUrl: "https://www.photoprism.app" },
    ],
  },
  {
    id: "gmaps",
    name: "Google Maps",
    icon: "🗺",
    category: "Navigation",
    difficulty: "Easy",
    desc: "Maps & navigation",
    takeoutKey: null,
    alternatives: [
      { id: "osmand", name: "OsmAnd", icon: "🗺", privacy: 5, cost: "Free / $10 one-time", ease: 4, platforms: "iOS, Android", desc: "Offline maps based on OpenStreetMap. No tracking, fully offline capable.", importGuide: "Download maps for your region. Import saved places as GPX.", signupUrl: "https://osmand.net" },
      { id: "organicmaps", name: "Organic Maps", icon: "🌿", privacy: 5, cost: "Free", ease: 5, platforms: "iOS, Android", desc: "Privacy-focused offline maps. Fork of Maps.me without tracking. Very fast.", importGuide: "Install and download offline maps. No account needed.", signupUrl: "https://organicmaps.app" },
      { id: "magicearth", name: "Magic Earth", icon: "🌍", privacy: 4, cost: "Free", ease: 5, platforms: "iOS, Android", desc: "Free navigation with real-time traffic. No tracking, no ads. OpenStreetMap data.", importGuide: "Install app. Supports offline maps and turn-by-turn navigation.", signupUrl: "https://www.magicearth.com" },
    ],
  },
  {
    id: "youtube",
    name: "YouTube",
    icon: "▶",
    category: "Media",
    difficulty: "Hard",
    desc: "Video streaming",
    takeoutKey: "YouTube and YouTube Music",
    alternatives: [
      { id: "newpipe", name: "NewPipe", icon: "📺", privacy: 5, cost: "Free", ease: 4, platforms: "Android (F-Droid)", desc: "Lightweight YouTube frontend. No Google account needed. Background play, downloads.", importGuide: "Export YouTube subscriptions via Takeout → Import OPML into NewPipe", signupUrl: "https://newpipe.net" },
      { id: "freetube", name: "FreeTube", icon: "📺", privacy: 5, cost: "Free", ease: 4, platforms: "Windows, Mac, Linux", desc: "Desktop YouTube client. No tracking, no ads. Import subscriptions.", importGuide: "Settings → Data Settings → Import Subscriptions from YouTube/OPML", signupUrl: "https://freetubeapp.io" },
      { id: "invidious", name: "Invidious", icon: "🔵", privacy: 5, cost: "Free", ease: 3, platforms: "Web (self-hosted / public instances)", desc: "Alternative YouTube frontend. No JavaScript required, no tracking. API available.", importGuide: "Import subscriptions via OPML file from YouTube Takeout data", signupUrl: "https://invidious.io" },
      { id: "odysee", name: "Odysee / LBRY", icon: "🟣", privacy: 4, cost: "Free", ease: 4, platforms: "Web, iOS, Android, Desktop", desc: "Decentralized video platform. Blockchain-backed. Growing creator base.", importGuide: "YouTube Sync feature can auto-mirror your channel to Odysee", signupUrl: "https://odysee.com" },
    ],
  },
  {
    id: "gdocs",
    name: "Google Docs/Sheets/Slides",
    icon: "📝",
    category: "Productivity",
    difficulty: "Medium",
    desc: "Office productivity suite",
    takeoutKey: "Drive",
    alternatives: [
      { id: "libreoffice", name: "LibreOffice", icon: "📄", privacy: 5, cost: "Free", ease: 5, platforms: "Windows, Mac, Linux", desc: "Full open-source office suite. Excellent compatibility with MS Office formats.", importGuide: "Google Takeout exports Docs as .docx, Sheets as .xlsx — open directly", signupUrl: "https://www.libreoffice.org/download/" },
      { id: "cryptpad", name: "CryptPad", icon: "🔐", privacy: 5, cost: "Free / €5+/mo", ease: 4, platforms: "Web", desc: "Zero-knowledge encrypted collaborative suite. Docs, sheets, presentations, forms.", importGuide: "Upload exported files to CryptPad Drive. Import supported for most formats.", signupUrl: "https://cryptpad.fr" },
      { id: "onlyoffice", name: "ONLYOFFICE", icon: "🟦", privacy: 4, cost: "Free (self-hosted) / Cloud plans", ease: 4, platforms: "Web, Windows, Mac, Linux", desc: "Full office suite compatible with MS formats. Self-hostable. Real-time collab.", importGuide: "Upload .docx/.xlsx/.pptx files from Takeout export directly", signupUrl: "https://www.onlyoffice.com" },
    ],
  },
  {
    id: "gmeet",
    name: "Google Meet",
    icon: "📹",
    category: "Communication",
    difficulty: "Easy",
    desc: "Video conferencing",
    takeoutKey: null,
    alternatives: [
      { id: "jitsi", name: "Jitsi Meet", icon: "📹", privacy: 5, cost: "Free", ease: 5, platforms: "Web, iOS, Android, Desktop", desc: "Open-source video conferencing. No account required. E2E encryption available.", importGuide: "No migration needed — just start using meet.jit.si or self-host", signupUrl: "https://meet.jit.si" },
      { id: "signal_video", name: "Signal (Video)", icon: "💬", privacy: 5, cost: "Free", ease: 5, platforms: "iOS, Android, Desktop", desc: "E2E encrypted video calls for up to 50 people. Gold standard for secure comms.", importGuide: "Install Signal, verify phone number. Group video calls available.", signupUrl: "https://signal.org/download/" },
      { id: "element", name: "Element (Matrix)", icon: "🟢", privacy: 5, cost: "Free / Hosted plans", ease: 3, platforms: "Web, iOS, Android, Desktop", desc: "Decentralized Matrix-based video conferencing. Self-hostable, federated.", importGuide: "Create account on matrix.org or self-hosted server", signupUrl: "https://element.io" },
    ],
  },
  {
    id: "gkeep",
    name: "Google Keep",
    icon: "📌",
    category: "Productivity",
    difficulty: "Easy",
    desc: "Notes & lists",
    takeoutKey: "Keep",
    alternatives: [
      { id: "standardnotes", name: "Standard Notes", icon: "🔒", privacy: 5, cost: "Free / $5+/mo", ease: 5, platforms: "Web, iOS, Android, Windows, Mac, Linux", desc: "E2E encrypted notes. 100% open source. Longevity focused (100-year company).", importGuide: "Import from Google Keep JSON export via Standard Notes importer", signupUrl: "https://standardnotes.com" },
      { id: "joplin", name: "Joplin", icon: "📓", privacy: 5, cost: "Free / €3+/mo sync", ease: 4, platforms: "Windows, Mac, Linux, iOS, Android", desc: "Open-source Markdown note-taking. E2E encrypted sync. Evernote import.", importGuide: "File → Import → Select Google Keep export files", signupUrl: "https://joplinapp.org" },
      { id: "obsidian", name: "Obsidian", icon: "💎", privacy: 4, cost: "Free / $5+/mo sync", ease: 4, platforms: "Windows, Mac, Linux, iOS, Android", desc: "Powerful knowledge base. Local-first Markdown files. Plugin ecosystem.", importGuide: "Convert Keep notes to Markdown, place in Obsidian vault folder", signupUrl: "https://obsidian.md" },
    ],
  },
  {
    id: "gauth",
    name: "Google Authenticator",
    icon: "🔑",
    category: "Security",
    difficulty: "Medium",
    desc: "2FA authentication",
    takeoutKey: null,
    alternatives: [
      { id: "aegis", name: "Aegis", icon: "🛡", privacy: 5, cost: "Free", ease: 5, platforms: "Android", desc: "Open-source 2FA app. Encrypted vault, biometric unlock, backup/restore.", importGuide: "Export from Google Authenticator → Import into Aegis (supports multiple formats)", signupUrl: "https://getaegis.app" },
      { id: "enteauth", name: "Ente Auth", icon: "🟢", privacy: 5, cost: "Free", ease: 5, platforms: "iOS, Android, Web, Desktop", desc: "E2E encrypted 2FA with cloud backup. Cross-platform. Open source.", importGuide: "Scan QR codes or import from Google Authenticator export", signupUrl: "https://ente.io/auth/" },
      { id: "bitwarden_auth", name: "Bitwarden (TOTP)", icon: "🔵", privacy: 5, cost: "$10/yr (premium)", ease: 5, platforms: "All platforms", desc: "Built-in TOTP authenticator in Bitwarden password manager. Everything in one place.", importGuide: "Add TOTP secret keys to existing Bitwarden vault entries", signupUrl: "https://bitwarden.com" },
    ],
  },
  {
    id: "gpassword",
    name: "Google Password Manager",
    icon: "🔐",
    category: "Security",
    difficulty: "Medium",
    desc: "Password management",
    takeoutKey: null,
    alternatives: [
      { id: "bitwarden", name: "Bitwarden", icon: "🔵", privacy: 5, cost: "Free / $10/yr", ease: 5, platforms: "All platforms + browser extensions", desc: "Open-source password manager. Cloud sync, self-hostable. Community voted #1.", importGuide: "Export Chrome passwords as CSV → Bitwarden → Tools → Import Data", signupUrl: "https://vault.bitwarden.com/#/register" },
      { id: "keepassxc", name: "KeePassXC", icon: "🟢", privacy: 5, cost: "Free", ease: 3, platforms: "Windows, Mac, Linux", desc: "Offline-first open-source password manager. Local encrypted database.", importGuide: "Export Chrome passwords as CSV → KeePassXC → Import from CSV", signupUrl: "https://keepassxc.org/download/" },
      { id: "protonpass", name: "Proton Pass", icon: "🟣", privacy: 5, cost: "Free / $2+/mo", ease: 5, platforms: "All platforms + browser extensions", desc: "E2E encrypted password manager from Proton. Integrates with Proton ecosystem.", importGuide: "Export Chrome passwords as CSV → Proton Pass → Import", signupUrl: "https://proton.me/pass" },
    ],
  },
  {
    id: "gtranslate",
    name: "Google Translate",
    icon: "🌐",
    category: "Utilities",
    difficulty: "Easy",
    desc: "Translation service",
    takeoutKey: null,
    alternatives: [
      { id: "deepl", name: "DeepL", icon: "🔵", privacy: 4, cost: "Free / $9+/mo", ease: 5, platforms: "Web, Windows, Mac, iOS, Android", desc: "Superior translation quality. European privacy standards. Pro plan deletes data.", importGuide: "No migration needed — bookmark deepl.com or install desktop app", signupUrl: "https://www.deepl.com" },
      { id: "libretranslate", name: "LibreTranslate", icon: "🟢", privacy: 5, cost: "Free (self-hosted) / API plans", ease: 3, platforms: "Web, API", desc: "Open-source machine translation. Self-hostable. No tracking.", importGuide: "Use web interface or self-host your own instance", signupUrl: "https://libretranslate.com" },
    ],
  },
  {
    id: "gplaystore",
    name: "Google Play Store",
    icon: "🏪",
    category: "Android",
    difficulty: "Medium",
    desc: "Android app store",
    takeoutKey: null,
    alternatives: [
      { id: "fdroid", name: "F-Droid", icon: "🤖", privacy: 5, cost: "Free", ease: 4, platforms: "Android", desc: "FOSS app repository. All apps are free and open source. No tracking.", importGuide: "Download F-Droid APK from f-droid.org → Install → Browse apps", signupUrl: "https://f-droid.org" },
      { id: "aurora", name: "Aurora Store", icon: "🌌", privacy: 4, cost: "Free", ease: 4, platforms: "Android", desc: "Access Play Store apps without a Google account. Anonymous downloads.", importGuide: "Install from F-Droid → Use anonymous login → Download your apps", signupUrl: "https://auroraoss.com" },
    ],
  },
  {
    id: "gandroid",
    name: "Android OS (Stock)",
    icon: "📱",
    category: "Android",
    difficulty: "Hard",
    desc: "Mobile operating system",
    takeoutKey: null,
    alternatives: [
      { id: "grapheneos", name: "GrapheneOS", icon: "🔒", privacy: 5, cost: "Free", ease: 2, platforms: "Google Pixel phones only", desc: "Hardened Android. Maximum security & privacy. Sandboxed Google Play available.", importGuide: "Web installer at grapheneos.org. Requires unlocked Pixel device.", signupUrl: "https://grapheneos.org/install/web" },
      { id: "lineageos", name: "LineageOS", icon: "🟢", privacy: 4, cost: "Free", ease: 2, platforms: "Many Android devices", desc: "Open-source Android ROM. Wide device support. No Google services by default.", importGuide: "Check device support → Unlock bootloader → Flash via recovery", signupUrl: "https://lineageos.org" },
      { id: "calyxos", name: "CalyxOS", icon: "🌿", privacy: 5, cost: "Free", ease: 3, platforms: "Google Pixel, Fairphone, others", desc: "Privacy-focused Android with microG. Good balance of privacy and usability.", importGuide: "Flash via CalyxOS installer tool for supported devices", signupUrl: "https://calyxos.org" },
    ],
  },
];

const CATEGORIES = [...new Set(GOOGLE_SERVICES.map((s) => s.category))];

const MIGRATION_PHASES = [
  { id: "backup", name: "Backup & Export", icon: "💾", desc: "Export all your Google data via Takeout" },
  { id: "accounts", name: "Create Accounts", icon: "🔑", desc: "Sign up for your chosen alternatives" },
  { id: "migrate", name: "Migrate Data", icon: "📦", desc: "Import your data into new services" },
  { id: "connected", name: "Connected Services", icon: "🔗", desc: "Migrate every account tied to your Google login" },
  { id: "transition", name: "Transition Period", icon: "🔄", desc: "Run old & new services in parallel" },
  { id: "cutover", name: "Final Cutover", icon: "✅", desc: "Update logins, notify contacts, disable Google" },
];

// ── Styles ──
const styles = {
  app: {
    minHeight: "100vh",
    background: `linear-gradient(180deg, ${C.bg} 0%, #08080d 100%)`,
    color: C.text,
    fontFamily: "'JetBrains Mono', 'SF Mono', 'Cascadia Code', 'Fira Code', monospace",
    position: "relative",
    overflow: "hidden",
  },
  noise: {
    position: "fixed",
    top: 0,
    left: 0,
    right: 0,
    bottom: 0,
    opacity: 0.03,
    backgroundImage: `url("data:image/svg+xml,%3Csvg viewBox='0 0 256 256' xmlns='http://www.w3.org/2000/svg'%3E%3Cfilter id='n'%3E%3CfeTurbulence type='fractalNoise' baseFrequency='0.9' numOctaves='4' stitchTiles='stitch'/%3E%3C/filter%3E%3Crect width='100%25' height='100%25' filter='url(%23n)'/%3E%3C/svg%3E")`,
    pointerEvents: "none",
    zIndex: 0,
  },
  container: {
    maxWidth: 1100,
    margin: "0 auto",
    padding: "0 24px",
    position: "relative",
    zIndex: 1,
  },
  header: {
    padding: "32px 0 16px",
    display: "flex",
    alignItems: "center",
    justifyContent: "space-between",
    borderBottom: `1px solid ${C.border}`,
    marginBottom: 32,
  },
  logo: {
    display: "flex",
    alignItems: "center",
    gap: 14,
  },
  logoIcon: {
    width: 44,
    height: 44,
    borderRadius: 12,
    background: `linear-gradient(135deg, ${C.accent}, ${C.purple})`,
    display: "flex",
    alignItems: "center",
    justifyContent: "center",
    fontSize: 22,
    fontWeight: 800,
    letterSpacing: -1,
    color: "#fff",
    boxShadow: `0 0 24px ${C.accentGlow}`,
  },
  logoText: {
    fontSize: 22,
    fontWeight: 700,
    letterSpacing: -0.5,
    background: `linear-gradient(135deg, ${C.text}, ${C.textMuted})`,
    WebkitBackgroundClip: "text",
    WebkitTextFillColor: "transparent",
  },
  version: {
    fontSize: 11,
    color: C.textDim,
    fontWeight: 500,
    marginLeft: 8,
    background: C.bgElevated,
    padding: "3px 8px",
    borderRadius: 6,
    border: `1px solid ${C.border}`,
  },
  stepIndicator: {
    display: "flex",
    gap: 6,
    alignItems: "center",
  },
  stepDot: (active, done) => ({
    width: done ? 28 : active ? 28 : 8,
    height: 8,
    borderRadius: 4,
    background: done ? C.green : active ? C.accent : C.border,
    transition: "all 0.4s cubic-bezier(0.34,1.56,0.64,1)",
    boxShadow: active ? `0 0 12px ${C.accentGlow}` : done ? `0 0 12px ${C.greenGlow}` : "none",
  }),
  card: {
    background: C.bgCard,
    border: `1px solid ${C.border}`,
    borderRadius: 14,
    padding: 24,
    marginBottom: 16,
    transition: "all 0.25s ease",
  },
  btn: (variant = "primary") => ({
    padding: "12px 28px",
    borderRadius: 10,
    border: variant === "primary" ? "none" : `1px solid ${C.border}`,
    background: variant === "primary" ? `linear-gradient(135deg, ${C.accent}, #2563eb)` : variant === "ghost" ? "transparent" : C.bgElevated,
    color: variant === "primary" ? "#fff" : C.text,
    fontSize: 14,
    fontWeight: 600,
    cursor: "pointer",
    fontFamily: "inherit",
    transition: "all 0.2s ease",
    display: "inline-flex",
    alignItems: "center",
    gap: 8,
    boxShadow: variant === "primary" ? `0 4px 16px ${C.accentGlow}` : "none",
  }),
  sectionTitle: {
    fontSize: 28,
    fontWeight: 800,
    letterSpacing: -1,
    marginBottom: 8,
    lineHeight: 1.2,
  },
  sectionDesc: {
    fontSize: 14,
    color: C.textMuted,
    lineHeight: 1.6,
    marginBottom: 28,
    maxWidth: 640,
  },
  badge: (color) => ({
    display: "inline-flex",
    alignItems: "center",
    gap: 4,
    padding: "3px 10px",
    borderRadius: 6,
    fontSize: 11,
    fontWeight: 600,
    background: color === "green" ? C.greenSoft : color === "orange" ? C.orangeGlow : color === "red" ? C.redGlow : color === "blue" ? C.accentSoft : color === "purple" ? C.purpleGlow : C.bgElevated,
    color: color === "green" ? C.green : color === "orange" ? C.orange : color === "red" ? C.red : color === "blue" ? C.accent : color === "purple" ? C.purple : C.textMuted,
    border: `1px solid ${color === "green" ? "rgba(34,197,94,0.2)" : color === "orange" ? "rgba(245,158,11,0.2)" : color === "red" ? "rgba(239,68,68,0.2)" : color === "blue" ? "rgba(59,130,246,0.2)" : color === "purple" ? "rgba(168,85,247,0.2)" : C.border}`,
    fontFamily: "inherit",
  }),
  privacyDots: (level) => ({
    display: "inline-flex",
    gap: 3,
  }),
  checkbox: (checked) => ({
    width: 22,
    height: 22,
    borderRadius: 6,
    border: `2px solid ${checked ? C.accent : C.border}`,
    background: checked ? C.accent : "transparent",
    display: "flex",
    alignItems: "center",
    justifyContent: "center",
    cursor: "pointer",
    transition: "all 0.2s ease",
    flexShrink: 0,
    fontSize: 13,
    color: "#fff",
    fontWeight: 700,
  }),
  progressBar: (pct) => ({
    height: 6,
    borderRadius: 3,
    background: C.bgElevated,
    overflow: "hidden",
    position: "relative",
  }),
  progressFill: (pct) => ({
    height: "100%",
    width: `${pct}%`,
    borderRadius: 3,
    background: `linear-gradient(90deg, ${C.accent}, ${C.green})`,
    transition: "width 0.6s cubic-bezier(0.34,1.56,0.64,1)",
    boxShadow: pct > 0 ? `0 0 12px ${C.accentGlow}` : "none",
  }),
};

// ── Components ──

const PrivacyDots = ({ level }) => (
  <span style={styles.privacyDots(level)}>
    {[1, 2, 3, 4, 5].map((i) => (
      <span key={i} style={{ width: 7, height: 7, borderRadius: "50%", background: i <= level ? C.green : C.border, transition: "background 0.2s" }} />
    ))}
  </span>
);

const DifficultyBadge = ({ d }) => {
  const color = d === "Easy" ? "green" : d === "Medium" ? "orange" : "red";
  return <span style={styles.badge(color)}>{d}</span>;
};

const ProgressBar = ({ pct }) => (
  <div style={styles.progressBar(pct)}>
    <div style={styles.progressFill(pct)} />
  </div>
);

// ── Welcome Screen ──
const WelcomeStep = ({ onNext }) => (
  <div style={{ textAlign: "center", padding: "40px 0 20px", animation: "fadeIn 0.6s ease" }}>
    <div style={{ fontSize: 64, marginBottom: 20, filter: "drop-shadow(0 0 30px rgba(59,130,246,0.3))" }}>🛡</div>
    <h1 style={{ fontSize: 42, fontWeight: 900, letterSpacing: -2, lineHeight: 1.1, marginBottom: 12, background: `linear-gradient(135deg, ${C.text} 30%, ${C.accent} 70%, ${C.purple})`, WebkitBackgroundClip: "text", WebkitTextFillColor: "transparent" }}>
      DeGoogler
    </h1>
    <p style={{ fontSize: 16, color: C.textMuted, lineHeight: 1.7, maxWidth: 540, margin: "0 auto 32px" }}>
      Your personal migration wizard for leaving Google services behind. Select which services you use, choose privacy-respecting alternatives, and follow a step-by-step plan to take back control of your data.
    </p>
    <div style={{ display: "flex", gap: 12, justifyContent: "center", flexWrap: "wrap", marginBottom: 40 }}>
      {[
        { icon: "📋", label: "Audit Services" },
        { icon: "🔄", label: "Choose Alternatives" },
        { icon: "💾", label: "Backup Data" },
        { icon: "🔗", label: "Untangle Logins" },
        { icon: "📦", label: "Migrate" },
        { icon: "✅", label: "Go Google-Free" },
      ].map((s, i) => (
        <div key={i} style={{ ...styles.card, padding: "14px 18px", display: "flex", alignItems: "center", gap: 10, marginBottom: 0, minWidth: 140, background: i === 5 ? C.accentSoft : C.bgCard, border: `1px solid ${i === 5 ? "rgba(59,130,246,0.2)" : C.border}` }}>
          <span style={{ fontSize: 20 }}>{s.icon}</span>
          <span style={{ fontSize: 13, fontWeight: 600 }}>{s.label}</span>
          {i < 5 && <span style={{ color: C.textDim, marginLeft: "auto", fontSize: 16 }}>→</span>}
        </div>
      ))}
    </div>
    <button style={styles.btn("primary")} onClick={onNext} onMouseOver={(e) => (e.target.style.transform = "translateY(-2px)")} onMouseOut={(e) => (e.target.style.transform = "none")}>
      Begin Migration Assessment →
    </button>
    <p style={{ fontSize: 11, color: C.textDim, marginTop: 16 }}>No data leaves your browser. Everything runs locally.</p>
  </div>
);

// ── Service Selection ──
const ServiceSelection = ({ selected, onToggle, onNext, onBack }) => {
  const [filter, setFilter] = useState("All");
  const filtered = filter === "All" ? GOOGLE_SERVICES : GOOGLE_SERVICES.filter((s) => s.category === filter);
  const count = selected.length;

  return (
    <div style={{ animation: "fadeIn 0.4s ease" }}>
      <h2 style={styles.sectionTitle}>Which Google services do you use?</h2>
      <p style={styles.sectionDesc}>Select every Google product you currently rely on. We'll help you find alternatives and build a migration plan for each one.</p>

      <div style={{ display: "flex", gap: 8, marginBottom: 20, flexWrap: "wrap", alignItems: "center" }}>
        {["All", ...CATEGORIES].map((cat) => (
          <button
            key={cat}
            onClick={() => setFilter(cat)}
            style={{
              padding: "6px 14px",
              borderRadius: 8,
              border: `1px solid ${filter === cat ? C.accent : C.border}`,
              background: filter === cat ? C.accentSoft : "transparent",
              color: filter === cat ? C.accent : C.textMuted,
              fontSize: 12,
              fontWeight: 600,
              cursor: "pointer",
              fontFamily: "inherit",
              transition: "all 0.2s",
            }}
          >
            {cat}
          </button>
        ))}
        <button
          onClick={() => {
            const allIds = GOOGLE_SERVICES.map((s) => s.id);
            const allSelected = allIds.every((id) => selected.includes(id));
            allIds.forEach((id) => {
              if (allSelected && selected.includes(id)) onToggle(id);
              if (!allSelected && !selected.includes(id)) onToggle(id);
            });
          }}
          style={{ ...styles.btn("ghost"), padding: "6px 14px", fontSize: 12, marginLeft: "auto" }}
        >
          {GOOGLE_SERVICES.every((s) => selected.includes(s.id)) ? "Deselect All" : "Select All"}
        </button>
      </div>

      <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fill, minmax(280px, 1fr))", gap: 12, marginBottom: 28 }}>
        {filtered.map((svc) => {
          const sel = selected.includes(svc.id);
          return (
            <div
              key={svc.id}
              onClick={() => onToggle(svc.id)}
              style={{
                ...styles.card,
                marginBottom: 0,
                padding: "16px 18px",
                cursor: "pointer",
                display: "flex",
                alignItems: "center",
                gap: 14,
                borderColor: sel ? C.accent : C.border,
                background: sel ? C.accentSoft : C.bgCard,
                boxShadow: sel ? `0 0 20px ${C.accentGlow}` : "none",
              }}
              onMouseOver={(e) => { if (!sel) e.currentTarget.style.background = C.bgCardHover; }}
              onMouseOut={(e) => { if (!sel) e.currentTarget.style.background = C.bgCard; }}
            >
              <span style={{ fontSize: 26 }}>{svc.icon}</span>
              <div style={{ flex: 1, minWidth: 0 }}>
                <div style={{ fontSize: 14, fontWeight: 700 }}>{svc.name}</div>
                <div style={{ fontSize: 11, color: C.textMuted }}>{svc.desc}</div>
              </div>
              <div style={{ display: "flex", flexDirection: "column", alignItems: "flex-end", gap: 6 }}>
                <DifficultyBadge d={svc.difficulty} />
                <div style={styles.checkbox(sel)}>{sel ? "✓" : ""}</div>
              </div>
            </div>
          );
        })}
      </div>

      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
        <button style={styles.btn("secondary")} onClick={onBack}>← Back</button>
        <span style={{ fontSize: 13, color: C.textMuted }}>{count} service{count !== 1 ? "s" : ""} selected</span>
        <button style={{ ...styles.btn("primary"), opacity: count === 0 ? 0.4 : 1, pointerEvents: count === 0 ? "none" : "auto" }} onClick={onNext}>
          Choose Alternatives →
        </button>
      </div>
    </div>
  );
};

// ── Alternative Selection ──
const AlternativeSelection = ({ selectedServices, choices, onChoose, onNext, onBack }) => {
  const [expandedSvc, setExpandedSvc] = useState(selectedServices[0] || null);
  const services = GOOGLE_SERVICES.filter((s) => selectedServices.includes(s.id));
  const allChosen = services.every((s) => choices[s.id]);
  const chosenCount = Object.keys(choices).filter((k) => selectedServices.includes(k)).length;

  return (
    <div style={{ animation: "fadeIn 0.4s ease" }}>
      <h2 style={styles.sectionTitle}>Choose your alternatives</h2>
      <p style={styles.sectionDesc}>
        For each Google service, pick the alternative you want to migrate to. We've ranked them by privacy, cost, and ease of migration.
      </p>

      <div style={{ display: "flex", gap: 8, marginBottom: 20, flexWrap: "wrap" }}>
        {services.map((svc) => (
          <button
            key={svc.id}
            onClick={() => setExpandedSvc(svc.id)}
            style={{
              padding: "8px 14px",
              borderRadius: 8,
              border: `1px solid ${expandedSvc === svc.id ? C.accent : choices[svc.id] ? C.green : C.border}`,
              background: expandedSvc === svc.id ? C.accentSoft : choices[svc.id] ? C.greenSoft : "transparent",
              color: expandedSvc === svc.id ? C.accent : choices[svc.id] ? C.green : C.textMuted,
              fontSize: 12,
              fontWeight: 600,
              cursor: "pointer",
              fontFamily: "inherit",
              transition: "all 0.2s",
              display: "flex",
              alignItems: "center",
              gap: 6,
            }}
          >
            <span>{svc.icon}</span> {svc.name} {choices[svc.id] ? "✓" : ""}
          </button>
        ))}
      </div>

      {expandedSvc && (() => {
        const svc = GOOGLE_SERVICES.find((s) => s.id === expandedSvc);
        if (!svc) return null;
        return (
          <div style={{ marginBottom: 24 }}>
            <div style={{ display: "flex", alignItems: "center", gap: 12, marginBottom: 16 }}>
              <span style={{ fontSize: 28 }}>{svc.icon}</span>
              <div>
                <h3 style={{ fontSize: 18, fontWeight: 700, margin: 0 }}>Replace {svc.name}</h3>
                <span style={{ fontSize: 12, color: C.textMuted }}>{svc.alternatives.length} alternatives available</span>
              </div>
            </div>
            <div style={{ display: "grid", gap: 12 }}>
              {svc.alternatives.map((alt) => {
                const chosen = choices[svc.id] === alt.id;
                return (
                  <div
                    key={alt.id}
                    onClick={() => onChoose(svc.id, alt.id)}
                    style={{
                      ...styles.card,
                      marginBottom: 0,
                      padding: "18px 20px",
                      cursor: "pointer",
                      borderColor: chosen ? C.green : C.border,
                      background: chosen ? C.greenSoft : C.bgCard,
                      boxShadow: chosen ? `0 0 20px ${C.greenGlow}` : "none",
                      display: "grid",
                      gridTemplateColumns: "1fr auto",
                      gap: 16,
                    }}
                    onMouseOver={(e) => { if (!chosen) e.currentTarget.style.background = C.bgCardHover; }}
                    onMouseOut={(e) => { if (!chosen) e.currentTarget.style.background = C.bgCard; }}
                  >
                    <div>
                      <div style={{ display: "flex", alignItems: "center", gap: 10, marginBottom: 8 }}>
                        <span style={{ fontSize: 20 }}>{alt.icon}</span>
                        <span style={{ fontSize: 16, fontWeight: 700 }}>{alt.name}</span>
                        {chosen && <span style={styles.badge("green")}>Selected</span>}
                      </div>
                      <p style={{ fontSize: 13, color: C.textMuted, lineHeight: 1.5, margin: "0 0 12px" }}>{alt.desc}</p>
                      <div style={{ display: "flex", gap: 16, flexWrap: "wrap", fontSize: 12 }}>
                        <span style={{ display: "flex", alignItems: "center", gap: 6 }}>
                          <span style={{ color: C.textDim }}>Privacy</span> <PrivacyDots level={alt.privacy} />
                        </span>
                        <span><span style={{ color: C.textDim }}>Cost:</span> <span style={{ color: C.text, fontWeight: 600 }}>{alt.cost}</span></span>
                        <span><span style={{ color: C.textDim }}>Ease:</span> <span style={{ color: alt.ease >= 4 ? C.green : alt.ease >= 3 ? C.orange : C.red, fontWeight: 600 }}>{"★".repeat(alt.ease)}{"☆".repeat(5 - alt.ease)}</span></span>
                      </div>
                      <div style={{ fontSize: 11, color: C.textDim, marginTop: 8 }}>Platforms: {alt.platforms}</div>
                    </div>
                    <div style={{ display: "flex", alignItems: "center" }}>
                      <div style={styles.checkbox(chosen)}>{chosen ? "✓" : ""}</div>
                    </div>
                  </div>
                );
              })}
            </div>
          </div>
        );
      })()}

      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginTop: 20 }}>
        <button style={styles.btn("secondary")} onClick={onBack}>← Back</button>
        <span style={{ fontSize: 13, color: C.textMuted }}>{chosenCount}/{services.length} alternatives chosen</span>
        <button style={{ ...styles.btn("primary"), opacity: !allChosen ? 0.4 : 1, pointerEvents: !allChosen ? "none" : "auto" }} onClick={onNext}>
          Generate Migration Plan →
        </button>
      </div>
    </div>
  );
};

// ── Migration Plan ──
const MigrationPlan = ({ selectedServices, choices, checklist, onCheck, onBack, onExport }) => {
  const services = GOOGLE_SERVICES.filter((s) => selectedServices.includes(s.id));
  const [activePhase, setActivePhase] = useState("backup");

  const getAlternative = (svcId) => {
    const svc = GOOGLE_SERVICES.find((s) => s.id === svcId);
    return svc?.alternatives.find((a) => a.id === choices[svcId]);
  };

  // Build checklist items per phase
  const phaseItems = {
    backup: [
      { id: "takeout_start", label: "Go to Google Takeout and start a full export", link: "https://takeout.google.com", critical: true },
      { id: "takeout_download", label: "Download all Takeout archive files when ready", critical: true },
      { id: "takeout_extract", label: "Extract archives and organize by service", critical: false },
      { id: "passwords_export", label: "Export Chrome passwords (chrome://settings/passwords → Export)", critical: true },
      { id: "bookmarks_export", label: "Export Chrome bookmarks (Bookmarks Manager → ⋮ → Export)", critical: false },
      ...services.filter((s) => s.takeoutKey).map((s) => ({
        id: `verify_${s.id}`,
        label: `Verify ${s.name} data exported correctly (${s.takeoutKey})`,
        critical: false,
      })),
    ],
    accounts: services.map((svc) => {
      const alt = getAlternative(svc.id);
      return {
        id: `signup_${svc.id}`,
        label: `Create ${alt?.name} account`,
        link: alt?.signupUrl,
        critical: true,
        sub: `Replaces ${svc.name}`,
      };
    }),
    migrate: services.map((svc) => {
      const alt = getAlternative(svc.id);
      return {
        id: `import_${svc.id}`,
        label: `Import ${svc.name} data into ${alt?.name}`,
        critical: true,
        sub: alt?.importGuide,
      };
    }),
    connected: [
      { id: "conn_audit_oauth", label: "Audit all OAuth-connected apps (\"Sign in with Google\")", link: "https://myaccount.google.com/permissions", critical: true, sub: "Review every app that uses your Google account as its login method." },
      { id: "conn_audit_email", label: "List all services registered with your Gmail address", critical: true, sub: "Think through: banking, insurance, government (IRS, SSA), medical portals, work HR, shopping, subscriptions, social media, hosting/domains, utilities." },
      { id: "conn_critical_banking", label: "Update email on banking and financial services", critical: true, sub: "Bank accounts, credit cards, investment accounts, PayPal, Venmo, crypto exchanges." },
      { id: "conn_critical_gov", label: "Update email on government and tax services", critical: true, sub: "IRS, SSA, state DMV, voter registration, tax filing services (TurboTax, etc)." },
      { id: "conn_critical_medical", label: "Update email on healthcare and insurance portals", critical: true, sub: "Health insurance, patient portals, pharmacy accounts, dental, vision." },
      { id: "conn_critical_work", label: "Update email on employer and HR systems", critical: true, sub: "Payroll, benefits, 401k/retirement, expense reports, corporate accounts." },
      { id: "conn_oauth_passwords", label: "Set passwords on all OAuth-only services", critical: true, sub: "For each service where Google is your ONLY login: go to their settings and create a standalone password before disconnecting." },
      { id: "conn_important_shopping", label: "Update email on shopping and subscription services", critical: false, sub: "Amazon, eBay, streaming services, app subscriptions, meal delivery, etc." },
      { id: "conn_important_social", label: "Update email on social media accounts", critical: false, sub: "LinkedIn, Facebook, Reddit, Discord, Twitter/X, Instagram, etc." },
      { id: "conn_important_dev", label: "Update email on developer and hosting accounts", critical: false, sub: "GitHub, cloud providers (AWS/Azure/GCP), domain registrars, CI/CD, monitoring." },
      { id: "conn_important_utilities", label: "Update email on utility and service providers", critical: false, sub: "Electric, gas, water, internet, phone, rideshare (Uber/Lyft), travel (Airbnb)." },
      { id: "conn_play_store", label: "Audit Google Play Store purchases and subscriptions", link: "https://play.google.com/store/account/subscriptions", critical: false, sub: "List apps with active subscriptions billed through Google Play. Re-subscribe directly with each provider." },
      { id: "conn_google_pay", label: "Migrate Google Pay/Wallet payment methods", link: "https://pay.google.com", critical: false, sub: "Update stored payment methods on services that used Google Pay." },
      { id: "conn_smart_home", label: "Reconfigure smart home devices (if using Google Home)", critical: false, sub: "Smart speakers, Chromecast, Nest devices, smart lights/plugs linked to Google Home." },
      { id: "conn_revoke_all", label: "Revoke all remaining OAuth connections", link: "https://myaccount.google.com/permissions", critical: true, sub: "After setting passwords and updating emails, disconnect every third-party app." },
      { id: "conn_verify_access", label: "Verify you can log into every migrated service without Google", critical: true, sub: "Test each service with your new credentials. This is the last gate before account deletion." },
    ],
    transition: [
      { id: "email_forward", label: "Set up Gmail forwarding to new email address", link: "https://mail.google.com/mail/u/0/#settings/fwdandpop", critical: true },
      { id: "update_logins", label: "Update email on critical accounts (banking, work, government)", critical: true },
      { id: "notify_contacts", label: "Send contacts your new email address", critical: false },
      { id: "test_services", label: "Test all new services for 1-2 weeks in parallel", critical: true },
      { id: "update_2fa", label: "Re-enroll 2FA tokens in new authenticator app", critical: true },
      { id: "update_subscriptions", label: "Update email on newsletters, subscriptions, and mailing lists", critical: false },
    ],
    cutover: [
      { id: "verify_all", label: "Confirm all data migrated successfully", critical: true },
      { id: "disable_sync", label: "Disable Google sync on all devices", critical: false },
      { id: "revoke_access", label: "Revoke third-party app access (myaccount.google.com/permissions)", link: "https://myaccount.google.com/permissions", critical: true },
      { id: "delete_data", label: "Delete data from Google services (optional)", critical: false },
      { id: "close_account", label: "Delete Google account (optional — only when fully confident)", link: "https://myaccount.google.com/deleteaccount", critical: false },
    ],
  };

  const allItems = Object.values(phaseItems).flat();
  const totalChecked = allItems.filter((item) => checklist[item.id]).length;
  const totalItems = allItems.length;
  const overallPct = totalItems > 0 ? Math.round((totalChecked / totalItems) * 100) : 0;

  const phaseProgress = (phaseId) => {
    const items = phaseItems[phaseId] || [];
    const checked = items.filter((item) => checklist[item.id]).length;
    return items.length > 0 ? Math.round((checked / items.length) * 100) : 0;
  };

  return (
    <div style={{ animation: "fadeIn 0.4s ease" }}>
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "flex-start", marginBottom: 20, flexWrap: "wrap", gap: 16 }}>
        <div>
          <h2 style={styles.sectionTitle}>Your Migration Plan</h2>
          <p style={{ ...styles.sectionDesc, marginBottom: 12 }}>
            {services.length} service{services.length > 1 ? "s" : ""} to migrate across 6 phases. Check off each step as you complete it.
          </p>
        </div>
        <div style={{ textAlign: "right" }}>
          <div style={{ fontSize: 36, fontWeight: 900, color: overallPct === 100 ? C.green : C.accent, letterSpacing: -2 }}>{overallPct}%</div>
          <div style={{ fontSize: 11, color: C.textMuted }}>{totalChecked}/{totalItems} steps complete</div>
        </div>
      </div>

      <div style={{ marginBottom: 20 }}>
        <ProgressBar pct={overallPct} />
      </div>

      {/* Phase tabs */}
      <div style={{ display: "flex", gap: 6, marginBottom: 20, flexWrap: "wrap" }}>
        {MIGRATION_PHASES.map((phase) => {
          const pct = phaseProgress(phase.id);
          const active = activePhase === phase.id;
          return (
            <button
              key={phase.id}
              onClick={() => setActivePhase(phase.id)}
              style={{
                padding: "10px 16px",
                borderRadius: 10,
                border: `1px solid ${active ? C.accent : pct === 100 ? C.green : C.border}`,
                background: active ? C.accentSoft : pct === 100 ? C.greenSoft : "transparent",
                color: active ? C.accent : pct === 100 ? C.green : C.textMuted,
                fontSize: 12,
                fontWeight: 600,
                cursor: "pointer",
                fontFamily: "inherit",
                transition: "all 0.2s",
                display: "flex",
                alignItems: "center",
                gap: 8,
                flex: "1 1 auto",
                justifyContent: "center",
                minWidth: 140,
              }}
            >
              <span>{phase.icon}</span>
              <span>{phase.name}</span>
              {pct === 100 && <span style={{ fontSize: 14 }}>✓</span>}
              {pct > 0 && pct < 100 && <span style={{ fontSize: 10, opacity: 0.7 }}>{pct}%</span>}
            </button>
          );
        })}
      </div>

      {/* Active phase content */}
      {(() => {
        const phase = MIGRATION_PHASES.find((p) => p.id === activePhase);
        const items = phaseItems[activePhase] || [];
        return (
          <div style={{ ...styles.card, padding: 0, overflow: "hidden" }}>
            <div style={{ padding: "18px 22px", borderBottom: `1px solid ${C.border}`, display: "flex", justifyContent: "space-between", alignItems: "center" }}>
              <div>
                <h3 style={{ fontSize: 16, fontWeight: 700, margin: 0, display: "flex", alignItems: "center", gap: 8 }}>
                  <span>{phase.icon}</span> {phase.name}
                </h3>
                <p style={{ fontSize: 12, color: C.textMuted, margin: "4px 0 0" }}>{phase.desc}</p>
              </div>
              <span style={{ fontSize: 13, fontWeight: 700, color: phaseProgress(activePhase) === 100 ? C.green : C.accent }}>
                {phaseProgress(activePhase)}%
              </span>
            </div>
            <div>
              {items.map((item, i) => {
                const checked = !!checklist[item.id];
                return (
                  <div
                    key={item.id}
                    style={{
                      padding: "14px 22px",
                      borderBottom: i < items.length - 1 ? `1px solid ${C.border}` : "none",
                      display: "flex",
                      alignItems: "flex-start",
                      gap: 14,
                      background: checked ? "rgba(34,197,94,0.03)" : "transparent",
                      transition: "background 0.2s",
                      cursor: "pointer",
                    }}
                    onClick={() => onCheck(item.id)}
                    onMouseOver={(e) => { if (!checked) e.currentTarget.style.background = C.bgCardHover; }}
                    onMouseOut={(e) => { e.currentTarget.style.background = checked ? "rgba(34,197,94,0.03)" : "transparent"; }}
                  >
                    <div style={{ ...styles.checkbox(checked), marginTop: 2 }}>{checked ? "✓" : ""}</div>
                    <div style={{ flex: 1, minWidth: 0 }}>
                      <div style={{ fontSize: 13, fontWeight: 600, textDecoration: checked ? "line-through" : "none", opacity: checked ? 0.5 : 1, color: C.text }}>
                        {item.label}
                        {item.critical && <span style={{ ...styles.badge("red"), marginLeft: 8, fontSize: 9 }}>Required</span>}
                      </div>
                      {item.sub && <div style={{ fontSize: 11, color: C.textDim, marginTop: 4, lineHeight: 1.4 }}>{item.sub}</div>}
                      {item.link && (
                        <a
                          href={item.link}
                          target="_blank"
                          rel="noopener noreferrer"
                          onClick={(e) => e.stopPropagation()}
                          style={{ fontSize: 11, color: C.accent, textDecoration: "none", marginTop: 4, display: "inline-block" }}
                        >
                          Open Link →
                        </a>
                      )}
                    </div>
                  </div>
                );
              })}
            </div>
          </div>
        );
      })()}

      {/* Summary card */}
      <div style={{ ...styles.card, marginTop: 20, padding: 20 }}>
        <h4 style={{ fontSize: 14, fontWeight: 700, margin: "0 0 14px", display: "flex", alignItems: "center", gap: 8 }}>📋 Migration Summary</h4>
        <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fill, minmax(240px, 1fr))", gap: 12 }}>
          {services.map((svc) => {
            const alt = getAlternative(svc.id);
            return (
              <div key={svc.id} style={{ display: "flex", alignItems: "center", gap: 10, padding: "10px 14px", background: C.bgElevated, borderRadius: 10, border: `1px solid ${C.border}` }}>
                <span style={{ fontSize: 18 }}>{svc.icon}</span>
                <div style={{ flex: 1, minWidth: 0 }}>
                  <div style={{ fontSize: 11, color: C.textDim, textDecoration: "line-through" }}>{svc.name}</div>
                  <div style={{ fontSize: 13, fontWeight: 700, display: "flex", alignItems: "center", gap: 6 }}>
                    {alt?.icon} {alt?.name}
                  </div>
                </div>
                <DifficultyBadge d={svc.difficulty} />
              </div>
            );
          })}
        </div>
      </div>

      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginTop: 24 }}>
        <button style={styles.btn("secondary")} onClick={onBack}>← Back</button>
        <button style={styles.btn("secondary")} onClick={onExport}>📄 Export Plan</button>
      </div>
    </div>
  );
};

// ── Main App ──
export default function DeGoogler() {
  const [step, setStep] = useState(0); // 0=welcome, 1=services, 2=alternatives, 3=plan
  const [selectedServices, setSelectedServices] = useState([]);
  const [choices, setChoices] = useState({});
  const [checklist, setChecklist] = useState({});

  // Load state from storage on mount
  useEffect(() => {
    (async () => {
      try {
        const res = await window.storage.get("degoogler-state");
        if (res?.value) {
          const state = JSON.parse(res.value);
          if (state.selectedServices) setSelectedServices(state.selectedServices);
          if (state.choices) setChoices(state.choices);
          if (state.checklist) setChecklist(state.checklist);
          if (state.step !== undefined) setStep(state.step);
        }
      } catch {}
    })();
  }, []);

  // Save state to storage
  useEffect(() => {
    const timer = setTimeout(async () => {
      try {
        await window.storage.set("degoogler-state", JSON.stringify({ step, selectedServices, choices, checklist }));
      } catch {}
    }, 500);
    return () => clearTimeout(timer);
  }, [step, selectedServices, choices, checklist]);

  const toggleService = useCallback((id) => {
    setSelectedServices((prev) => prev.includes(id) ? prev.filter((s) => s !== id) : [...prev, id]);
  }, []);

  const chooseAlternative = useCallback((svcId, altId) => {
    setChoices((prev) => ({ ...prev, [svcId]: altId }));
  }, []);

  const toggleCheck = useCallback((id) => {
    setChecklist((prev) => ({ ...prev, [id]: !prev[id] }));
  }, []);

  const exportPlan = useCallback(() => {
    const services = GOOGLE_SERVICES.filter((s) => selectedServices.includes(s.id));
    let md = "# DeGoogler Migration Plan\n\nGenerated by DeGoogler v0.0.1\n\n## Migration Summary\n\n";
    md += "| Google Service | Alternative | Difficulty |\n|---|---|---|\n";
    services.forEach((svc) => {
      const alt = svc.alternatives.find((a) => a.id === choices[svc.id]);
      md += `| ${svc.name} | ${alt?.name || "TBD"} | ${svc.difficulty} |\n`;
    });
    md += "\n## Phase 1: Backup & Export\n\n";
    md += "1. Go to https://takeout.google.com and start a full export\n";
    md += "2. Download all Takeout archive files when ready\n";
    md += "3. Extract archives and organize by service\n";
    md += "4. Export Chrome passwords and bookmarks\n";
    md += "\n## Phase 2: Create Accounts\n\n";
    services.forEach((svc) => {
      const alt = svc.alternatives.find((a) => a.id === choices[svc.id]);
      if (alt) md += `- [ ] Create ${alt.name} account: ${alt.signupUrl}\n`;
    });
    md += "\n## Phase 3: Migrate Data\n\n";
    services.forEach((svc) => {
      const alt = svc.alternatives.find((a) => a.id === choices[svc.id]);
      if (alt) md += `- [ ] ${svc.name} → ${alt.name}: ${alt.importGuide}\n`;
    });
    md += "\n## Phase 4: Connected Services Migration\n\n";
    md += "**Critical (Do First)**\n";
    md += "- [ ] Audit all OAuth-connected apps: https://myaccount.google.com/permissions\n";
    md += "- [ ] List ALL services registered with your Gmail address\n";
    md += "- [ ] Set passwords on every OAuth-only service (where Google is your ONLY login)\n";
    md += "- [ ] Update email on banking and financial services\n";
    md += "- [ ] Update email on government and tax services (IRS, SSA, DMV)\n";
    md += "- [ ] Update email on healthcare and insurance portals\n";
    md += "- [ ] Update email on employer/HR systems\n\n";
    md += "**Important**\n";
    md += "- [ ] Update email on shopping and subscription services\n";
    md += "- [ ] Update email on social media accounts\n";
    md += "- [ ] Update email on developer and hosting accounts\n";
    md += "- [ ] Update email on utility and service providers\n";
    md += "- [ ] Audit Google Play Store subscriptions: https://play.google.com/store/account/subscriptions\n";
    md += "- [ ] Migrate Google Pay/Wallet payment methods\n";
    md += "- [ ] Reconfigure smart home devices (if using Google Home)\n";
    md += "- [ ] Revoke ALL remaining OAuth connections\n";
    md += "- [ ] Verify you can log into EVERY migrated service without Google\n";
    md += "\n## Phase 5: Transition Period\n\n";
    md += "- [ ] Set up Gmail forwarding\n- [ ] Update email on critical accounts\n- [ ] Notify contacts of new email\n- [ ] Test all new services for 1-2 weeks\n- [ ] Re-enroll 2FA tokens\n";
    md += "\n## Phase 6: Final Cutover\n\n";
    md += "- [ ] Confirm all data migrated\n- [ ] Disable Google sync\n- [ ] Revoke third-party app access\n- [ ] (Optional) Delete Google data\n- [ ] (Optional) Delete Google account\n";

    const blob = new Blob([md], { type: "text/markdown" });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = "degoogler-migration-plan.md";
    a.click();
    URL.revokeObjectURL(url);
  }, [selectedServices, choices]);

  const resetAll = useCallback(async () => {
    setStep(0);
    setSelectedServices([]);
    setChoices({});
    setChecklist({});
    try { await window.storage.delete("degoogler-state"); } catch {}
  }, []);

  return (
    <div style={styles.app}>
      <div style={styles.noise} />
      <style>{`
        @import url('https://fonts.googleapis.com/css2?family=JetBrains+Mono:wght@400;500;600;700;800;900&display=swap');
        * { box-sizing: border-box; margin: 0; padding: 0; }
        ::-webkit-scrollbar { width: 8px; }
        ::-webkit-scrollbar-track { background: ${C.bg}; }
        ::-webkit-scrollbar-thumb { background: ${C.border}; border-radius: 4px; }
        ::-webkit-scrollbar-thumb:hover { background: ${C.textDim}; }
        @keyframes fadeIn { from { opacity: 0; transform: translateY(12px); } to { opacity: 1; transform: none; } }
        a:hover { text-decoration: underline !important; }
      `}</style>

      <div style={styles.container}>
        {/* Header */}
        <div style={styles.header}>
          <div style={styles.logo}>
            <div style={styles.logoIcon}>DG</div>
            <span style={styles.logoText}>DeGoogler</span>
            <span style={styles.version}>v0.0.1</span>
          </div>
          <div style={{ display: "flex", alignItems: "center", gap: 16 }}>
            {step > 0 && (
              <div style={styles.stepIndicator}>
                {[1, 2, 3].map((s) => (
                  <div key={s} style={styles.stepDot(step === s, step > s)} />
                ))}
              </div>
            )}
            {step > 0 && (
              <button
                style={{ ...styles.btn("ghost"), padding: "6px 12px", fontSize: 11, color: C.textDim }}
                onClick={resetAll}
              >
                Reset
              </button>
            )}
          </div>
        </div>

        {/* Steps */}
        {step === 0 && <WelcomeStep onNext={() => setStep(1)} />}
        {step === 1 && (
          <ServiceSelection
            selected={selectedServices}
            onToggle={toggleService}
            onNext={() => setStep(2)}
            onBack={() => setStep(0)}
          />
        )}
        {step === 2 && (
          <AlternativeSelection
            selectedServices={selectedServices}
            choices={choices}
            onChoose={chooseAlternative}
            onNext={() => setStep(3)}
            onBack={() => setStep(1)}
          />
        )}
        {step === 3 && (
          <MigrationPlan
            selectedServices={selectedServices}
            choices={choices}
            checklist={checklist}
            onCheck={toggleCheck}
            onBack={() => setStep(2)}
            onExport={exportPlan}
          />
        )}

        {/* Footer */}
        <div style={{ textAlign: "center", padding: "32px 0", borderTop: `1px solid ${C.border}`, marginTop: 32 }}>
          <p style={{ fontSize: 11, color: C.textDim }}>
            DeGoogler v0.0.1 — Your data never leaves your browser. Open source. No tracking.
          </p>
        </div>
      </div>
    </div>
  );
}
