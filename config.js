// ── Supabase configuration ────────────────────────────────────
// Replace the two placeholder values below with your project credentials.
// Find them in: Supabase Dashboard → Settings → API
const SUPABASE_URL  = 'https://hfhatujinbccqellycud.supabase.co';
const SUPABASE_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImhmaGF0dWppbmJjY3FlbGx5Y3VkIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODA3NzU2MTgsImV4cCI6MjA5NjM1MTYxOH0.4YzD5cfOAWEJs1jwxXSbWWy89hg8aKNbzKgblIMOymY';

// Global Supabase client — available on every page that loads this script
const { createClient } = window.supabase;
const db = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
