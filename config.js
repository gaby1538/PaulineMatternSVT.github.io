// ── Supabase configuration ────────────────────────────────────
// Replace the two placeholder values below with your project credentials.
// Find them in: Supabase Dashboard → Settings → API
const SUPABASE_URL  = 'https://hfhatujinbccqellycud.supabase.co';
const SUPABASE_ANON_KEY = 'sb_publishable_-dH-DDA5J956ouLFMF3N0Q_NxqF0EHU';

// Global Supabase client — available on every page that loads this script
const { createClient } = window.supabase;
const db = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
