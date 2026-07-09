// Vercel serverless function: POST /api/delete-user
// Removes a login (Supabase Auth user; the profiles row cascades automatically).
// Same admin-only guard pattern as create-user.js.

const { createClient } = require('@supabase/supabase-js');

if(!process.env.SUPABASE_URL || !process.env.SUPABASE_SERVICE_ROLE_KEY){
  console.error('Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY environment variables.');
}

const supabaseAdmin = createClient(
  process.env.SUPABASE_URL,
  process.env.SUPABASE_SERVICE_ROLE_KEY
);

module.exports = async (req, res) => {
  if (req.method !== 'POST') {
    return res.status(405).json({ error: 'Method not allowed' });
  }

  if(!process.env.SUPABASE_URL || !process.env.SUPABASE_SERVICE_ROLE_KEY){
    return res.status(500).json({ error: 'Server is missing SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY environment variables. Set them in Vercel → Settings → Environment Variables, then redeploy.' });
  }

  try {
    const { accessToken, targetUserId } = req.body || {};

    if (!accessToken) {
      return res.status(401).json({ error: 'Missing access token' });
    }
    if (!targetUserId) {
      return res.status(400).json({ error: 'Missing targetUserId' });
    }

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
      return res.status(403).json({ error: 'Only admin accounts can remove accounts' });
    }

    if (targetUserId === callerData.user.id) {
      return res.status(400).json({ error: 'You cannot remove your own account while signed in' });
    }

    const { error: deleteErr } = await supabaseAdmin.auth.admin.deleteUser(targetUserId);
    if (deleteErr) {
      return res.status(400).json({ error: deleteErr.message });
    }

    return res.status(200).json({ success: true });
  } catch (err) {
    return res.status(500).json({ error: err.message || 'Unexpected server error' });
  }
};
