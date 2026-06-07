// ── config.example.js ────────────────────────────────────────
// Copy this file to config.js and fill in your real credentials.
// Add config.js to .gitignore — never commit real keys.
//
// Setup steps:
//   1. Supabase: Dashboard → Settings → API
//   2. EmailJS:  Dashboard → Account → API Keys
//              + Dashboard → Email Services (get service ID)
//              + Dashboard → Email Templates (get template ID)
//              + Dashboard → Account → Security → add your domain to whitelist
//   3. Stripe:  Dashboard → Payment Links → create one per formule
//              → paste URLs in STRIPE_LINKS inside reservation.html

const SUPABASE_URL      = 'https://YOUR_PROJECT.supabase.co';
const SUPABASE_ANON_KEY = 'YOUR_SUPABASE_ANON_KEY';

const EMAILJS_PUBLIC_KEY  = 'YOUR_EMAILJS_PUBLIC_KEY';
const EMAILJS_SERVICE_ID  = 'YOUR_EMAILJS_SERVICE_ID';
const EMAILJS_TEMPLATE_ID = 'YOUR_EMAILJS_TEMPLATE_ID';

const { createClient } = window.supabase;
const db = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
