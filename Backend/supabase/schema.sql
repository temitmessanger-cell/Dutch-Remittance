-- Dutch Remit — Supabase schema. Run this once against your Supabase
-- project (Supabase dashboard → SQL Editor → paste → Run). Safe to
-- re-run: every statement is idempotent (create table if not exists /
-- create or replace / drop policy if exists).
--
-- NOTE: this file was reconstructed after being accidentally
-- overwritten with unrelated text mid-session. It's rebuilt from the
-- actual column names every route in src/routes/*.js reads and
-- writes (cross-checked directly against that code, not memory), so
-- it should match reality — but if you have an actual database
-- already running against an earlier version of this file, diff
-- before re-running rather than assuming this is byte-identical to
-- what created it.

create extension if not exists pgcrypto;

-- ------------------------------------------------------------------
-- profiles — one row per real person, whether they arrived via a
-- genuine Supabase Auth session (auth_user_id set) or the legacy
-- custom-token bridge (auth_user_id null, resolved via
-- legacy_sessions below). Every route reads/writes this by id.
-- ------------------------------------------------------------------
create table if not exists public.profiles (
  id uuid primary key default gen_random_uuid(),
  auth_user_id uuid unique references auth.users (id) on delete cascade,
  dutch_remit_id text unique,
  username text unique,
  first_name text,
  last_name text,
  email text,
  phone_number text,
  address text,
  country text,
  avatar_url text,
  eversend_card_user_id text,
  created_at timestamptz not null default now()
);

-- Defensive: `create table if not exists` above is a no-op if
-- `profiles` already existed from an earlier run of this file — it
-- will NOT retroactively add columns added since then (this is
-- exactly what caused "column dutch_remit_id does not exist" when
-- re-running against a database created before that column existed).
-- Every column is re-asserted here with `add column if not exists`
-- so re-running this file is genuinely safe regardless of which
-- earlier version of this schema created the live table.
alter table public.profiles add column if not exists auth_user_id uuid unique references auth.users (id) on delete cascade;
alter table public.profiles add column if not exists dutch_remit_id text unique;
alter table public.profiles add column if not exists username text unique;
alter table public.profiles add column if not exists first_name text;
alter table public.profiles add column if not exists last_name text;
alter table public.profiles add column if not exists email text;
alter table public.profiles add column if not exists phone_number text;
alter table public.profiles add column if not exists address text;
alter table public.profiles add column if not exists country text;
alter table public.profiles add column if not exists avatar_url text;
alter table public.profiles add column if not exists eversend_card_user_id text;
alter table public.profiles add column if not exists created_at timestamptz not null default now();

create index if not exists profiles_auth_user_id_idx on public.profiles (auth_user_id);
create index if not exists profiles_dutch_remit_id_idx on public.profiles (dutch_remit_id);

-- Generates a "DR-XXXXXXXX" id (8 uppercase alphanumeric chars) —
-- every profile gets one, whether created via the auth trigger below
-- or the legacy-token path in requireAppUser.js. Retries on the
-- astronomically unlikely collision rather than trusting one draw.
create or replace function public.generate_dutch_remit_id()
returns text as $$
declare
  candidate text;
  exists_already boolean;
begin
  loop
    candidate := 'DR-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8));
    select exists(select 1 from public.profiles where dutch_remit_id = candidate) into exists_already;
    exit when not exists_already;
  end loop;
  return candidate;
end;
$$ language plpgsql;

-- Column default so ANY insert into profiles gets a dutch_remit_id
-- automatically — covers the legacy-token path in requireAppUser.js
-- (a bare `.insert({})`) as well as the auth trigger below, without
-- needing every call site to remember to set it explicitly.
alter table public.profiles alter column dutch_remit_id set default public.generate_dutch_remit_id();

-- ------------------------------------------------------------------
-- legacy_sessions — maps a SHA-256 hash of the app's pre-Supabase-Auth
-- custom token to a stable profiles.id (see
-- src/middleware/requireAppUser.js). The raw token itself is never
-- stored, only its hash.
-- ------------------------------------------------------------------
create table if not exists public.legacy_sessions (
  token_hash text primary key,
  profile_id uuid not null references public.profiles (id) on delete cascade,
  last_seen_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

-- ------------------------------------------------------------------
-- beneficiaries — the Recipient tab's saved payout destinations,
-- mirrored from Eversend on create (src/routes/beneficiaries.js) so
-- the tab loads instantly from cache.
-- ------------------------------------------------------------------
create table if not exists public.beneficiaries (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  eversend_beneficiary_id text,
  first_name text,
  last_name text,
  country text,
  phone_number text,
  is_bank boolean not null default false,
  is_momo boolean not null default false,
  bank_name text,
  bank_account_number text,
  bank_code text,
  created_at timestamptz not null default now()
);
create index if not exists beneficiaries_user_id_idx on public.beneficiaries (user_id);

-- ------------------------------------------------------------------
-- transactions — every deposit, payout, wallet transfer, card
-- action, and exchange this backend records, regardless of which
-- provider (Eversend/Klasha) actually carried it. `eversend_reference`
-- is how webhooks.js finds and updates a row's status later.
-- ------------------------------------------------------------------
create table if not exists public.transactions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  type text not null check (
    type in (
      'deposit', 'payout', 'wallet_transfer', 'card_fund', 'card_withdraw',
      'exchange', 'card_creation_fee', 'card_link_fee', 'card_transfer'
    )
  ),
  status text not null default 'pending',
  amount numeric,
  currency text,
  method text, -- 'momo' | 'bank' | 'crypto' | 'card' | 'internal' | etc.
  provider text, -- 'eversend' | 'klasha' | 'dutch_remit' — which rail actually carried this transaction
  speed text, -- 'instant' | 'standard', matches top_up_screen.dart / withdraw_screen.dart
  phone_number text,
  beneficiary_id text,
  card_id text,
  eversend_reference text unique,
  raw_response jsonb,
  created_at timestamptz not null default now()
);
create index if not exists transactions_user_id_idx on public.transactions (user_id);
create index if not exists transactions_created_at_idx on public.transactions (created_at desc);

-- ------------------------------------------------------------------
-- cards — virtual cards actually issued through Dutch Remit's own
-- flow (create_virtual_card_screen.dart → POST /api/v1/cards).
-- ------------------------------------------------------------------
create table if not exists public.cards (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  eversend_card_id text,
  title text,
  color text,
  kind text default 'issued',
  status text default 'active',
  raw_response jsonb,
  created_at timestamptz not null default now()
);
create index if not exists cards_user_id_idx on public.cards (user_id);

-- ------------------------------------------------------------------
-- card_kyc_identities — the KYC identity behind every Eversend
-- cardholder profile (POST /cards/user), one row per person.
-- `method` is 'document' when the user actually uploaded a real ID
-- (id_type/id_number are what they entered, document_path points into
-- the `kyc-documents` storage bucket below), or 'generated' when they
-- chose "proceed without KYC" instead — in that case id_type/id_number
-- are synthesized server-side (see Backend/src/routes/cards.js):
-- id_type is 'ID' for African countries and 'FOREIGN' otherwise,
-- id_number is a generated unique cardholder reference. Either way,
-- exactly what got sent to Eversend is recorded here.
-- ------------------------------------------------------------------
create table if not exists public.card_kyc_identities (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  method text not null check (method in ('document', 'generated')),
  country text,
  id_type text not null,
  id_number text not null,
  document_path text,
  eversend_card_user_id text,
  created_at timestamptz not null default now()
);
create index if not exists card_kyc_identities_user_id_idx on public.card_kyc_identities (user_id);

-- Storage bucket for uploaded ID documents (the 'document' method
-- above) — private by default; only the service_role key (this
-- backend) can read/write, never the anon/client key.
insert into storage.buckets (id, name, public)
select 'kyc-documents', 'kyc-documents', false
where not exists (select 1 from storage.buckets where id = 'kyc-documents');

-- ------------------------------------------------------------------
-- linked_cards — a user's own pre-existing bank-issued card, linked
-- to their Dutch Remit account as a funding source (the "Add a Card"
-- flow, distinct from card issuance above). Requires the user to
-- already hold at least one Dutch-Remit-issued card first, identity
-- confirmation, and a $2.10 retrieval fee (see cards.js POST /link).
--
-- SECURITY: the CVV is used only in-memory for that one request and
-- is NEVER written here or anywhere else — no column for it exists on
-- purpose. The card number itself is stored masked (last 4 digits
-- only), never in full — this table is not a substitute for a real
-- PCI-DSS-compliant card vault, and shouldn't be treated as
-- production-ready for real cardholder data at any meaningful scale.
-- ------------------------------------------------------------------
create table if not exists public.linked_cards (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  masked_card_number text not null, -- e.g. "•••• •••• •••• 1234"
  card_brand text,
  expiry_month text,
  expiry_year text,
  cardholder_name text,
  status text not null default 'active',
  created_at timestamptz not null default now()
);
create index if not exists linked_cards_user_id_idx on public.linked_cards (user_id);

-- ------------------------------------------------------------------
-- card_transfers — the ledger for card-to-card transfers, whether
-- between two of the same user's own cards, or to another Dutch
-- Remit user's card (card_to_card_transfer_screen.dart). No real
-- card-network rail moves this money (neither Eversend nor Klasha
-- expose a card-to-card transfer API) — it's an internal ledger
-- entry, the same way the "Send to another Dutch Remit user" balance
-- transfer works; each transfer also writes a matching pair of
-- 'card_transfer' rows to `transactions` (one per party) for the
-- Transactions tab. `from_card_source`/`to_card_source` distinguish
-- which table the referenced card id lives in.
-- ------------------------------------------------------------------
create table if not exists public.card_transfers (
  id uuid primary key default gen_random_uuid(),
  from_user_id uuid not null references public.profiles (id) on delete cascade,
  to_user_id uuid references public.profiles (id) on delete set null,
  from_card_id uuid not null,
  from_card_source text not null check (from_card_source in ('issued', 'linked')),
  to_card_id uuid,
  to_card_source text check (to_card_source in ('issued', 'linked')),
  amount numeric not null,
  currency text not null default 'USD',
  status text not null default 'completed',
  reference text unique,
  note text,
  created_at timestamptz not null default now()
);
create index if not exists card_transfers_from_user_id_idx on public.card_transfers (from_user_id);
create index if not exists card_transfers_to_user_id_idx on public.card_transfers (to_user_id);

-- ------------------------------------------------------------------
-- businesses — the merchant/brand directory shown alongside contacts
-- when paying someone (available_businesses_contacts_screen.dart,
-- send_money_tab_screen.dart). Seeded with a small starter set below;
-- add real merchants here as they're onboarded.
-- ------------------------------------------------------------------
create table if not exists public.businesses (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  category text,
  logo_url text,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

insert into public.businesses (name, category)
select * from (values
  ('Dutch Remit Store', 'Retail'),
  ('Jumia', 'E-commerce'),
  ('Netflix', 'Subscriptions'),
  ('Spotify', 'Subscriptions'),
  ('MTN', 'Airtime & Data'),
  ('DSTV', 'Subscriptions')
) as seed(name, category)
where not exists (select 1 from public.businesses);

-- ------------------------------------------------------------------
-- devices — install/device metadata synced from the app
-- (POST /api/v1/devices).
-- ------------------------------------------------------------------
create table if not exists public.devices (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  device_id text not null unique,
  platform text,
  app_version text,
  last_seen_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);
create index if not exists devices_user_id_idx on public.devices (user_id);

-- ------------------------------------------------------------------
-- notifications — in-app notifications (GET/PATCH /api/v1/notifications).
-- ------------------------------------------------------------------
create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  title text,
  body text,
  is_read boolean not null default false,
  created_at timestamptz not null default now()
);
create index if not exists notifications_user_id_idx on public.notifications (user_id);

-- ------------------------------------------------------------------
-- webhook_events — a raw log of every Eversend/Klasha webhook
-- delivery, regardless of whether it matched a known transaction.
-- ------------------------------------------------------------------
create table if not exists public.webhook_events (
  id uuid primary key default gen_random_uuid(),
  source text,
  event_type text,
  payload jsonb not null,
  received_at timestamptz not null default now()
);

-- ==================================================================
-- Row Level Security. The backend always talks to Supabase with the
-- service_role key, which bypasses RLS by design — these policies
-- protect the day you let the Flutter app (or any other client) read
-- Supabase directly with the anon key under a *real* Supabase Auth
-- session (auth_user_id filled in). Legacy-token users are, for now,
-- only ever read through the backend, which is the intended boundary
-- until the auth migration happens.
-- ==================================================================
alter table public.profiles enable row level security;
alter table public.beneficiaries enable row level security;
alter table public.transactions enable row level security;
alter table public.cards enable row level security;
alter table public.card_kyc_identities enable row level security;
alter table public.linked_cards enable row level security;
alter table public.card_transfers enable row level security;
alter table public.devices enable row level security;
alter table public.notifications enable row level security;
alter table public.businesses enable row level security;

drop policy if exists "businesses_select_all" on public.businesses;
create policy "businesses_select_all" on public.businesses
  for select using (is_active = true);

drop policy if exists "profiles_select_own" on public.profiles;
create policy "profiles_select_own" on public.profiles
  for select using (auth.uid() = auth_user_id);
drop policy if exists "profiles_update_own" on public.profiles;
create policy "profiles_update_own" on public.profiles
  for update using (auth.uid() = auth_user_id);

drop policy if exists "beneficiaries_select_own" on public.beneficiaries;
create policy "beneficiaries_select_own" on public.beneficiaries
  for select using (
    user_id in (select id from public.profiles where auth_user_id = auth.uid())
  );

drop policy if exists "transactions_select_own" on public.transactions;
create policy "transactions_select_own" on public.transactions
  for select using (
    user_id in (select id from public.profiles where auth_user_id = auth.uid())
  );

drop policy if exists "cards_select_own" on public.cards;
create policy "cards_select_own" on public.cards
  for select using (
    user_id in (select id from public.profiles where auth_user_id = auth.uid())
  );

drop policy if exists "card_kyc_identities_select_own" on public.card_kyc_identities;
create policy "card_kyc_identities_select_own" on public.card_kyc_identities
  for select using (
    user_id in (select id from public.profiles where auth_user_id = auth.uid())
  );

drop policy if exists "linked_cards_select_own" on public.linked_cards;
create policy "linked_cards_select_own" on public.linked_cards
  for select using (
    user_id in (select id from public.profiles where auth_user_id = auth.uid())
  );

drop policy if exists "card_transfers_select_own" on public.card_transfers;
create policy "card_transfers_select_own" on public.card_transfers
  for select using (
    from_user_id in (select id from public.profiles where auth_user_id = auth.uid())
    or to_user_id in (select id from public.profiles where auth_user_id = auth.uid())
  );

drop policy if exists "devices_select_own" on public.devices;
create policy "devices_select_own" on public.devices
  for select using (
    user_id in (select id from public.profiles where auth_user_id = auth.uid())
  );

drop policy if exists "notifications_select_own" on public.notifications;
create policy "notifications_select_own" on public.notifications
  for select using (
    user_id in (select id from public.profiles where auth_user_id = auth.uid())
  );
drop policy if exists "notifications_update_own" on public.notifications;
create policy "notifications_update_own" on public.notifications
  for update using (
    user_id in (select id from public.profiles where auth_user_id = auth.uid())
  );

-- ------------------------------------------------------------------
-- Auto-create a profile row whenever a *real* Supabase auth user
-- signs up (only relevant once the app migrates off legacy tokens).
-- ------------------------------------------------------------------
create or replace function public.handle_new_auth_user()
returns trigger as $$
begin
  insert into public.profiles (auth_user_id, email, first_name, last_name, dutch_remit_id)
  values (
    new.id,
    new.email,
    new.raw_user_meta_data ->> 'first_name',
    new.raw_user_meta_data ->> 'last_name',
    public.generate_dutch_remit_id()
  )
  on conflict (auth_user_id) do nothing;
  return new;
end;
$$ language plpgsql security definer;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_auth_user();

-- Backfill: any profile created before this migration (or via the
-- legacy-token path, which inserts without going through the trigger
-- above — see requireAppUser.js) won't have a dutch_remit_id yet.
update public.profiles set dutch_remit_id = public.generate_dutch_remit_id()
where dutch_remit_id is null;

-- ------------------------------------------------------------------
-- virtual_accounts — a user's Klasha NGN/GHS virtual account, created
-- once per currency (see "Virtual Accounts" home-screen entry and
-- POST /api/v1/klasha/virtual-account). Needed for any corridor
-- Eversend doesn't cover but Klasha does: funds move from the user's
-- Eversend wallet into this account first, then the actual payout
-- goes out from Klasha — see the comment above POST
-- /api/v1/klasha/virtual-account for the full two-hop flow.
-- ------------------------------------------------------------------
create table if not exists public.virtual_accounts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  currency text not null check (currency in ('NGN', 'GHS')),
  account_number text,
  account_name text,
  bank_name text,
  klasha_reference text,
  fee_charged numeric not null,
  status text not null default 'active',
  raw_response jsonb,
  created_at timestamptz not null default now(),
  unique (user_id, currency)
);
create index if not exists virtual_accounts_user_id_idx on public.virtual_accounts (user_id);

alter table public.virtual_accounts enable row level security;
drop policy if exists "virtual_accounts_select_own" on public.virtual_accounts;
create policy "virtual_accounts_select_own" on public.virtual_accounts
  for select using (
    user_id in (select id from public.profiles where auth_user_id = auth.uid())
  );

-- 'card_creation_fee'/'card_link_fee'/'card_transfer' were added
-- earlier this session; 'virtual_account_fee' covers the $0.50/$1.50
-- Klasha virtual-account creation fee (see klasha.js POST
-- /virtual-account) — extending the same check constraint rather than
-- opening a second one.
alter table public.transactions drop constraint if exists transactions_type_check;
alter table public.transactions add constraint transactions_type_check check (
  type in (
    'deposit', 'payout', 'wallet_transfer', 'card_fund', 'card_withdraw',
    'exchange', 'card_creation_fee', 'card_link_fee', 'card_transfer',
    'virtual_account_fee'
  )
);
