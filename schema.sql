-- ============================================================
-- SVT Site – Supabase Schema
-- Run this entire file in Supabase SQL Editor (once, on a fresh project)
-- ============================================================

-- ── EXTENSIONS ──────────────────────────────────────────────
create extension if not exists "pgcrypto";

-- ── TABLES ──────────────────────────────────────────────────

-- Students (mirror of auth.users, enriched)
create table public.students (
  id          uuid primary key references auth.users(id) on delete cascade,
  first_name  text not null,
  last_name   text not null,
  email       text not null unique,
  niveau      text not null,
  credits     integer not null default 0 check (credits >= 0),
  created_at  timestamptz not null default now()
);

-- Sessions booked by students
create table public.sessions (
  id          uuid primary key default gen_random_uuid(),
  student_id  uuid not null references public.students(id) on delete cascade,
  slot_date   date not null,
  slot_time   text not null,   -- e.g. "14:00"
  subject     text not null,
  niveau      text not null,
  status      text not null default 'confirmed'
                check (status in ('confirmed','cancelled')),
  created_at  timestamptz not null default now(),
  unique(slot_date, slot_time, status)   -- one booking per slot (confirmed only handled in book_session)
);

-- Credit transactions ledger
create table public.transactions (
  id          uuid primary key default gen_random_uuid(),
  student_id  uuid not null references public.students(id) on delete cascade,
  description text not null,
  amount      integer not null,   -- positive = credit, negative = debit
  balance     integer not null,   -- balance after this transaction
  created_at  timestamptz not null default now()
);

-- Activation codes (SVT-{n}-{XXXXXX})
create table public.activation_codes (
  id          uuid primary key default gen_random_uuid(),
  code        text not null unique,
  credits     integer not null check (credits > 0),
  used        boolean not null default false,
  used_by     uuid references public.students(id),
  used_at     timestamptz,
  created_at  timestamptz not null default now()
);

-- Admins (Pauline and anyone else)
create table public.admins (
  id    uuid primary key references auth.users(id) on delete cascade,
  email text not null unique
);

-- ── ROW LEVEL SECURITY ───────────────────────────────────────

alter table public.students         enable row level security;
alter table public.sessions         enable row level security;
alter table public.transactions     enable row level security;
alter table public.activation_codes enable row level security;
alter table public.admins           enable row level security;

-- Helper: is the calling user an admin?
create or replace function public.is_admin()
returns boolean
language sql
security definer
stable
as $$
  select exists (
    select 1 from public.admins where id = auth.uid()
  );
$$;

-- ── RLS POLICIES: students ────────────────────────────────────

create policy "students: own row read"
  on public.students for select
  using (id = auth.uid() or public.is_admin());

create policy "students: own row update"
  on public.students for update
  using (id = auth.uid() or public.is_admin());

-- Insert handled by trigger only; no direct insert for users
create policy "students: admin insert"
  on public.students for insert
  with check (public.is_admin());

-- ── RLS POLICIES: sessions ────────────────────────────────────

create policy "sessions: own rows read"
  on public.sessions for select
  using (student_id = auth.uid() or public.is_admin());

-- Inserts go through book_session() SECURITY DEFINER
create policy "sessions: admin insert"
  on public.sessions for insert
  with check (public.is_admin());

create policy "sessions: admin update"
  on public.sessions for update
  using (public.is_admin());

-- ── RLS POLICIES: transactions ────────────────────────────────

create policy "transactions: own rows read"
  on public.transactions for select
  using (student_id = auth.uid() or public.is_admin());

-- Inserts go through SECURITY DEFINER functions only
create policy "transactions: admin insert"
  on public.transactions for insert
  with check (public.is_admin());

-- ── RLS POLICIES: activation_codes ───────────────────────────

-- Students cannot list codes; only admins can
create policy "codes: admin all"
  on public.activation_codes for all
  using (public.is_admin());

-- ── RLS POLICIES: admins ─────────────────────────────────────

create policy "admins: admin read"
  on public.admins for select
  using (public.is_admin());

-- ── TRIGGER: auto-create student profile on sign-up ──────────

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.students (id, first_name, last_name, email, niveau)
  values (
    new.id,
    new.raw_user_meta_data ->> 'first_name',
    new.raw_user_meta_data ->> 'last_name',
    new.email,
    new.raw_user_meta_data ->> 'niveau'
  );
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ── BUSINESS FUNCTIONS ────────────────────────────────────────

-- Returns taken slots so reservation.html can block them (accessible to anon)
create or replace function public.get_taken_slots()
returns table (slot_date date, slot_time text)
language sql
security definer
stable
as $$
  select slot_date, slot_time
  from public.sessions
  where status = 'confirmed';
$$;

-- Activate a credit code atomically
create or replace function public.activate_code(p_code text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_student_id  uuid;
  v_code_row    public.activation_codes%rowtype;
  v_new_balance integer;
begin
  v_student_id := auth.uid();
  if v_student_id is null then
    return jsonb_build_object('ok', false, 'error', 'not_authenticated');
  end if;

  -- Lock the code row to prevent race conditions
  select * into v_code_row
  from public.activation_codes
  where code = upper(trim(p_code))
  for update;

  if not found then
    return jsonb_build_object('ok', false, 'error', 'invalid_code');
  end if;

  if v_code_row.used then
    return jsonb_build_object('ok', false, 'error', 'already_used');
  end if;

  -- Debit the code
  update public.activation_codes
  set used = true, used_by = v_student_id, used_at = now()
  where id = v_code_row.id;

  -- Credit the student
  update public.students
  set credits = credits + v_code_row.credits
  where id = v_student_id
  returning credits into v_new_balance;

  -- Log transaction
  insert into public.transactions (student_id, description, amount, balance)
  values (
    v_student_id,
    'Code d''activation ' || v_code_row.code || ' (' || v_code_row.credits || ' crédit' || case when v_code_row.credits > 1 then 's' else '' end || ')',
    v_code_row.credits,
    v_new_balance
  );

  return jsonb_build_object('ok', true, 'credits_added', v_code_row.credits, 'new_balance', v_new_balance);
end;
$$;

-- Book a session atomically (deducts 1 credit, checks slot availability)
create or replace function public.book_session(
  p_date    date,
  p_time    text,
  p_subject text,
  p_niveau  text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_student_id  uuid;
  v_credits     integer;
  v_new_balance integer;
  v_session_id  uuid;
begin
  v_student_id := auth.uid();
  if v_student_id is null then
    return jsonb_build_object('ok', false, 'error', 'not_authenticated');
  end if;

  -- Check slot is free (lock sessions table for this slot)
  perform 1 from public.sessions
  where slot_date = p_date and slot_time = p_time and status = 'confirmed'
  for update;

  if found then
    return jsonb_build_object('ok', false, 'error', 'slot_taken');
  end if;

  -- Check student has enough credits
  select credits into v_credits
  from public.students
  where id = v_student_id
  for update;

  if v_credits < 1 then
    return jsonb_build_object('ok', false, 'error', 'no_credits');
  end if;

  -- Debit 1 credit
  update public.students
  set credits = credits - 1
  where id = v_student_id
  returning credits into v_new_balance;

  -- Create the session
  insert into public.sessions (student_id, slot_date, slot_time, subject, niveau)
  values (v_student_id, p_date, p_time, p_subject, p_niveau)
  returning id into v_session_id;

  -- Log transaction
  insert into public.transactions (student_id, description, amount, balance)
  values (
    v_student_id,
    'Réservation ' || to_char(p_date, 'DD/MM/YYYY') || ' ' || p_time || ' – ' || p_subject,
    -1,
    v_new_balance
  );

  return jsonb_build_object('ok', true, 'session_id', v_session_id, 'new_balance', v_new_balance);
end;
$$;

-- Cancel own session (refunds 1 credit)
create or replace function public.cancel_session(p_session_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_student_id  uuid;
  v_session     public.sessions%rowtype;
  v_new_balance integer;
begin
  v_student_id := auth.uid();
  if v_student_id is null then
    return jsonb_build_object('ok', false, 'error', 'not_authenticated');
  end if;

  select * into v_session
  from public.sessions
  where id = p_session_id and student_id = v_student_id and status = 'confirmed'
  for update;

  if not found then
    return jsonb_build_object('ok', false, 'error', 'session_not_found');
  end if;

  -- Cancel the session
  update public.sessions
  set status = 'cancelled'
  where id = p_session_id;

  -- Refund 1 credit
  update public.students
  set credits = credits + 1
  where id = v_student_id
  returning credits into v_new_balance;

  -- Log transaction
  insert into public.transactions (student_id, description, amount, balance)
  values (
    v_student_id,
    'Annulation séance ' || to_char(v_session.slot_date, 'DD/MM/YYYY') || ' ' || v_session.slot_time || ' – remboursement',
    1,
    v_new_balance
  );

  return jsonb_build_object('ok', true, 'new_balance', v_new_balance);
end;
$$;

-- ── ADMIN FUNCTIONS ───────────────────────────────────────────

-- Admin: add credits to a student manually
create or replace function public.admin_add_credits(
  p_student_id uuid,
  p_amount     integer,
  p_reason     text default 'Ajout manuel par administrateur'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_new_balance integer;
begin
  if not public.is_admin() then
    return jsonb_build_object('ok', false, 'error', 'forbidden');
  end if;

  if p_amount = 0 then
    return jsonb_build_object('ok', false, 'error', 'amount_zero');
  end if;

  update public.students
  set credits = greatest(0, credits + p_amount)
  where id = p_student_id
  returning credits into v_new_balance;

  if not found then
    return jsonb_build_object('ok', false, 'error', 'student_not_found');
  end if;

  insert into public.transactions (student_id, description, amount, balance)
  values (p_student_id, p_reason, p_amount, v_new_balance);

  return jsonb_build_object('ok', true, 'new_balance', v_new_balance);
end;
$$;

-- Admin: cancel any session (with optional credit refund)
create or replace function public.admin_cancel_session(
  p_session_id uuid,
  p_refund     boolean default true
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_session     public.sessions%rowtype;
  v_new_balance integer;
begin
  if not public.is_admin() then
    return jsonb_build_object('ok', false, 'error', 'forbidden');
  end if;

  select * into v_session
  from public.sessions
  where id = p_session_id and status = 'confirmed'
  for update;

  if not found then
    return jsonb_build_object('ok', false, 'error', 'session_not_found');
  end if;

  update public.sessions set status = 'cancelled' where id = p_session_id;

  if p_refund then
    update public.students
    set credits = credits + 1
    where id = v_session.student_id
    returning credits into v_new_balance;

    insert into public.transactions (student_id, description, amount, balance)
    values (
      v_session.student_id,
      'Annulation admin – séance ' || to_char(v_session.slot_date, 'DD/MM/YYYY') || ' ' || v_session.slot_time,
      1,
      v_new_balance
    );
  end if;

  return jsonb_build_object('ok', true, 'refunded', p_refund);
end;
$$;

-- Admin: generate a new activation code
create or replace function public.admin_create_code(p_credits integer)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_code text;
  v_id   uuid;
begin
  if not public.is_admin() then
    return jsonb_build_object('ok', false, 'error', 'forbidden');
  end if;

  if p_credits <= 0 then
    return jsonb_build_object('ok', false, 'error', 'invalid_credits');
  end if;

  -- Format: SVT-{credits}-{6 random uppercase chars}
  v_code := 'SVT-' || p_credits || '-' || upper(substring(encode(gen_random_bytes(6), 'hex'), 1, 6));

  insert into public.activation_codes (code, credits)
  values (v_code, p_credits)
  returning id into v_id;

  return jsonb_build_object('ok', true, 'code', v_code, 'id', v_id);
end;
$$;

-- ── GRANTS ────────────────────────────────────────────────────

-- anon can call get_taken_slots (slot availability without login)
grant execute on function public.get_taken_slots() to anon;

-- authenticated users can call their own functions
grant execute on function public.activate_code(text) to authenticated;
grant execute on function public.book_session(date, text, text, text) to authenticated;
grant execute on function public.cancel_session(uuid) to authenticated;

-- admin functions: authenticated only (is_admin() check is inside each function)
grant execute on function public.admin_add_credits(uuid, integer, text) to authenticated;
grant execute on function public.admin_cancel_session(uuid, boolean) to authenticated;
grant execute on function public.admin_create_code(integer) to authenticated;
grant execute on function public.is_admin() to authenticated;

-- ── REALTIME ─────────────────────────────────────────────────
-- Enable realtime on sessions so reservation.html gets live slot updates
-- (Also enable in Supabase Dashboard → Database → Replication)
alter publication supabase_realtime add table public.sessions;
