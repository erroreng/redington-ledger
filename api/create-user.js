// Vercel serverless function: POST /api/create-user
// Creates a new login (Supabase Auth user + profiles row).
// Uses the SERVICE ROLE key, which never reaches the browser —
// it only exists as a server-side environment variable.
// Only an already-logged-in admin can successfully call this.

const { createClient } = require('@supabase/supabase-js');

const supabaseAdmin = createClient(
  process.env.SUPABASE_URL,
  process.env.SUPABASE_SERVICE_ROLE_KEY
);

module.exports = async (req, res) => {
  if (req.method !== 'POST') {
    return res.status(405).json({ error: 'Method not allowed' });
  }

  try {
    const { accessToken, name, email, password, role, repName } = req.body || {};

    if (!accessToken) {
      return res.status(401).json({ error: 'Missing access token' });
    }
    if (!name || !email || !password || !role) {
      return res.status(400).json({ error: 'Missing required fields' });
    }
    if (!['admin', 'member'].includes(role)) {
      return res.status(400).json({ error: 'Role must be admin or member' });
    }
    if (role === 'member' && !repName) {
      return res.status(400).json({ error: 'repName is required for member accounts' });
    }
    if (password.length < 6) {
      return res.status(400).json({ error: 'Password must be at least 6 characters' });
    }

    // Verify the caller is a signed-in admin before doing anything privileged.
    const { data: callerData, error: callerErr } = await supabaseAdmin.auth.getUser(accessToken);
    if (callerErr || !callerData?.user) {
      return res.status(401).json({ error: 'Invalid or expired session' });
    }

    const { data: callerProfile, error: callerProfileErr } = await supabaseAdmin
      .from('profiles')
      .select('role')
      .eq('id', callerData.user.id)
      .single();

    if (callerProfileErr || callerProfile?.role !== 'admin') {
      return res.status(403).json({ error: 'Only admin accounts can create new accounts' });
    }

    // Create the auth user (email_confirm skips the "confirm your email" step,
    // fine here since the admin is creating this account directly).
    const { data: created, error: createErr } = await supabaseAdmin.auth.admin.createUser({
      email,
      password,
      email_confirm: true
    });
    if (createErr) {
      return res.status(400).json({ error: createErr.message });
    }

    const { error: insertErr } = await supabaseAdmin.from('profiles').insert({
      id: created.user.id,
      name,
      email,
      role,
      rep_name: role === 'member' ? repName : null
    });
    if (insertErr) {
      // Roll back the auth user if the profile insert fails, so we don't
      // end up with an orphaned login that has no role.
      await supabaseAdmin.auth.admin.deleteUser(created.user.id);
      return res.status(400).json({ error: insertErr.message });
    }

    return res.status(200).json({ success: true, userId: created.user.id });
  } catch (err) {
    return res.status(500).json({ error: err.message || 'Unexpected server error' });
  }
};
