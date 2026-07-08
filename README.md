# Redington Client & Quotation Ledger — Supabase backend

This version replaces the old "resets on refresh" in-browser version with a
real database (Supabase) and real accounts (Supabase Auth), so everything is
shared live across every teammate and every device.

## What changed vs the old version
- Login is now real authentication (email + password), not a hardcoded list.
- All quotations are stored permanently in a Postgres database.
- Access control is enforced by the database itself (Row Level Security),
  not just by the front-end — a sales rep genuinely cannot fetch another
  rep's rows, even by editing the page's code.
- Everyone can still see the one company-wide total value, through a safe
  database function that returns only that single number.
- Multiple people can have the dashboard open at once and see each other's
  changes appear live (Supabase Realtime).
- Uploading an Excel sheet now **adds** those rows to the ledger (it no
  longer wipes and replaces everything — too risky with real shared data).

## One-time setup

### 1. Create a Supabase project
1. Go to [supabase.com](https://supabase.com) → sign up (free tier is enough) → **New project**
2. Pick a name and a database password (save it somewhere) → wait ~2 minutes for it to provision

### 2. Run the database schema
1. In your Supabase project, open **SQL Editor** → **New query**
2. Paste the entire contents of `supabase-schema.sql` from this folder → **Run**
3. This creates the `profiles` and `quotations` tables, all the security rules, and the `total_pipeline_value()` function

### 3. Create the first admin account
1. Go to **Authentication → Users → Add user**
2. Enter an email and password, tick **Auto Confirm User** → **Create user**
3. Copy the new user's **UID** (shown in the users list)
4. Go back to **SQL Editor → New query** and run (replace the two placeholders):
   ```sql
   insert into public.profiles (id, name, role, rep_name)
   values ('PASTE-THE-UID-HERE', 'Admin', 'admin', null);
   ```
5. This is the account you'll use to sign in and manage everyone else from inside the dashboard itself — you won't need to repeat this manual step for future accounts.

### 4. Get your API keys
In Supabase: **Settings → API**, you'll need three values:
- **Project URL**
- **anon public** key
- **service_role** key (⚠️ keep this one secret — never put it in `index.html`)

### 5. Fill in the public config
Open `index.html`, find this near the top of the `<script>` block:
```js
const SUPABASE_URL = "https://YOUR-PROJECT-REF.supabase.co";
const SUPABASE_ANON_KEY = "YOUR-ANON-PUBLIC-KEY";
```
Replace both with your **Project URL** and **anon public** key from step 4. (These two are meant to be public — they're safe to ship in the browser because every request is still restricted by the database policies.)

### 6. Deploy to Vercel
1. Push this whole folder (`index.html`, `api/`, `package.json`, `supabase-schema.sql`) to a GitHub repo
2. In Vercel: **Add New → Project → Import** that repo
3. Before deploying, open **Environment Variables** and add:
   | Name | Value |
   |---|---|
   | `SUPABASE_URL` | same Project URL as step 4 |
   | `SUPABASE_SERVICE_ROLE_KEY` | the **service_role** key from step 4 (this one stays server-side only, inside `/api`, and is never sent to the browser) |
4. Click **Deploy**

### 7. Enable Realtime (optional but recommended)
In Supabase: **Database → Replication**, find the `quotations` table and toggle it on if it isn't already (the schema script tries to do this automatically, but it's worth double-checking).

## Adding team members afterwards
No more SQL needed for this part — once the admin account above can sign in:
1. Sign in → **👤 Manage team**
2. Fill in display name, **email** (needs to look like a real email address, e.g. `faisal@redington.com` — it doesn't need to receive real mail since the account is auto-confirmed), password, role, and — for a sales rep — the exact **Sales rep** name as it should appear on their quotations
3. **+ Add account** — done, they can sign in immediately with that email/password

## A note on limits
This was built and reviewed carefully, but it hasn't been tested against a
live Supabase project from this side — I don't have a way to run a real
deployment from here. Walk through the steps above, and if anything throws
an error (in the browser console, or from Supabase/Vercel), paste it back to
me and I'll fix it.
