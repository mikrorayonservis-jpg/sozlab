// ══════════════════════════════════════════════════════════════════════════
// SözLab API müştərisi — supabase-js-in saytda istifadə olunan hissəsinin
// eyni formada əvəzi. Sayt kodu dəyişmir: sb.from(...).select().eq()...,
// sb.rpc(...), sb.auth.*, sb.storage.* əvvəlki kimi işləyir, amma sorğular
// artıq öz serverinizə (Node.js + MySQL) gedir.
// ══════════════════════════════════════════════════════════════════════════
const SESSION_KEY = 'sozlab-session-v1';

function readSession() {
  try { const s = JSON.parse(localStorage.getItem(SESSION_KEY) || 'null'); return s && s.access_token ? s : null; }
  catch (_) { return null; }
}
function writeSession(s) {
  try { if (s) localStorage.setItem(SESSION_KEY, JSON.stringify(s)); else localStorage.removeItem(SESSION_KEY); } catch (_) {}
}

class ApiError extends Error {
  constructor(obj, status) {
    super(obj?.message || 'Xəta');
    this.name = 'ApiError';
    this.code = obj?.code ?? null;
    this.details = obj?.details ?? null;
    this.hint = obj?.hint ?? null;
    this.status = status;
  }
}
const netError = e => ({ message: 'Failed to fetch' + (e && e.message ? ': ' + e.message : ''), code: 'network', details: null, hint: null, status: 0 });

export function createClient(baseUrl = '') {
  const base = String(baseUrl || '').replace(/\/+$/, '');
  let session = readSession();

  async function call(path, { method = 'POST', body, raw, contentType } = {}) {
    const headers = {};
    if (session?.access_token) headers.Authorization = 'Bearer ' + session.access_token;
    let payload;
    if (raw !== undefined) { payload = raw; if (contentType) headers['Content-Type'] = contentType; }
    else if (body !== undefined) { payload = JSON.stringify(body); headers['Content-Type'] = 'application/json'; }
    let resp;
    try { resp = await fetch(base + path, { method, headers, body: payload, credentials: 'same-origin', cache: 'no-store' }); }
    catch (e) { return { error: netError(e), status: 0 }; }
    let json = null;
    try { json = await resp.json(); } catch (_) {}
    if (resp.status === 401 && session) { session = null; writeSession(null); }   // sessiya bitib
    if (!resp.ok) {
      const err = json?.error || { message: resp.statusText || ('HTTP ' + resp.status) };
      return { error: { message: err.message, code: err.code ?? null, details: err.details ?? null, hint: err.hint ?? null, status: resp.status }, status: resp.status };
    }
    return { json: json || {}, status: resp.status };
  }

  // ── sorğu qurucusu: sb.from(t) ─────────────────────────────────────────
  class Query {
    constructor(table) {
      this.b = { table, op: 'select', columns: '*', filters: [], order: [] };
    }
    select(columns = '*', opts = {}) {
      if (this.b.op === 'select') {
        this.b.columns = columns;
        if (opts.count) this.b.count = opts.count;
        if (opts.head) this.b.head = true;
      } else {
        this.b.returning = true;                      // insert/update/delete(...).select()
        this.b.columns = columns;
      }
      return this;
    }
    insert(values) { this.b.op = 'insert'; this.b.values = values; return this; }
    update(values) { this.b.op = 'update'; this.b.values = values; return this; }
    delete() { this.b.op = 'delete'; return this; }
    upsert() { throw new Error('upsert dəstəklənmir'); }
    _f(col, op, val) { this.b.filters.push([col, op, val]); return this; }
    eq(c, v) { return this._f(c, 'eq', v); }
    neq(c, v) { return this._f(c, 'neq', v); }
    gt(c, v) { return this._f(c, 'gt', v); }
    gte(c, v) { return this._f(c, 'gte', v); }
    lt(c, v) { return this._f(c, 'lt', v); }
    lte(c, v) { return this._f(c, 'lte', v); }
    like(c, v) { return this._f(c, 'like', v); }
    ilike(c, v) { return this._f(c, 'ilike', v); }
    is(c, v) { return this._f(c, 'is', v); }
    in(c, arr) { return this._f(c, 'in', Array.from(arr || [])); }
    match(obj) { for (const [k, v] of Object.entries(obj || {})) this.eq(k, v); return this; }
    or(str) { this.b.or = this.b.or ? this.b.or + ',' + str : str; return this; }
    order(col, opts = {}) { this.b.order.push([col, opts.ascending !== false, opts.nullsFirst ?? null]); return this; }
    limit(n) { this.b.limit = n; return this; }
    range(from, to) { this.b.offset = from; this.b.limit = to - from + 1; return this; }
    single() { this.b.single = true; return this; }
    maybeSingle() { this.b.maybe = true; return this; }
    abortSignal() { return this; }
    throwOnError() { this._throw = true; return this; }
    async _run() {
      const r = await call('/api/query', { body: this.b });
      if (r.error) {
        if (this._throw) throw new ApiError(r.error, r.status);
        return { data: null, error: r.error, count: null, status: r.status, statusText: '' };
      }
      return { data: r.json.data ?? null, error: null, count: r.json.count ?? null, status: r.status, statusText: 'OK' };
    }
    then(res, rej) { return this._run().then(res, rej); }
    catch(rej) { return this._run().catch(rej); }
    finally(f) { return this._run().finally(f); }
  }

  // ── sb.rpc(ad, parametrlər) ────────────────────────────────────────────
  function rpc(name, args = {}) {
    const run = async () => {
      const r = await call('/api/rpc/' + encodeURIComponent(name), { body: args || {} });
      if (r.error) return { data: null, error: r.error, status: r.status };
      return { data: r.json.data ?? null, error: null, status: r.status };
    };
    let p = null;
    const once = () => (p ||= run());
    return { then: (a, b) => once().then(a, b), catch: b => once().catch(b), finally: f => once().finally(f),
             single() { return this; }, maybeSingle() { return this; } };
  }

  // ── sb.auth ────────────────────────────────────────────────────────────
  const listeners = new Set();
  const emit = (ev, s) => listeners.forEach(fn => { try { fn(ev, s); } catch (_) {} });
  const authErr = r => ({ ...r.error, name: 'AuthApiError', __isAuthError: true });
  function setSession(s, ev) { session = s || null; writeSession(session); emit(ev, session); }

  const auth = {
    async getSession() {
      // supabase-js kimi: yerli nüsxə dərhal qaytarılır (şəbəkə gözlənilmir).
      // Token serverdə etibarsızdırsa, növbəti sorğu 401 alır və sessiya silinir.
      return { data: { session: session || null }, error: null };
    },
    async getUser() {
      const r = await call('/api/auth/user', { method: 'GET' });
      if (r.error) return { data: { user: null }, error: authErr(r) };
      return { data: { user: r.json.user }, error: null };
    },
    async signUp({ email, password, options } = {}) {
      const r = await call('/api/auth/signup', { body: { email, password, data: options?.data || {} } });
      if (r.error) return { data: { user: null, session: null }, error: authErr(r) };
      if (r.json.session) setSession(r.json.session, 'SIGNED_IN');
      return { data: { user: r.json.user, session: r.json.session || null }, error: null };
    },
    async signInWithPassword({ email, password } = {}) {
      const r = await call('/api/auth/signin', { body: { email, password } });
      if (r.error) return { data: { user: null, session: null }, error: authErr(r) };
      setSession(r.json.session, 'SIGNED_IN');
      return { data: { user: r.json.user, session: r.json.session }, error: null };
    },
    async verifyOtp({ email, token, type } = {}) {
      const r = await call('/api/auth/verify', { body: { email, token, type } });
      if (r.error) return { data: { user: null, session: null }, error: authErr(r) };
      setSession(r.json.session, 'SIGNED_IN');
      return { data: { user: r.json.user, session: r.json.session }, error: null };
    },
    async resend({ email, type } = {}) {
      const r = await call('/api/auth/resend', { body: { email, type } });
      if (r.error) return { data: null, error: authErr(r) };
      return { data: {}, error: null };
    },
    async signOut() {
      if (session) await call('/api/auth/signout', { body: {} });
      setSession(null, 'SIGNED_OUT');
      return { error: null };
    },
    async resetPasswordForEmail(email) {
      const r = await call('/api/auth/recover', { body: { email } });
      if (r.error) return { data: null, error: authErr(r) };
      return { data: {}, error: null };
    },
    async updateUser(attrs = {}) {
      const r = await call('/api/auth/update', { body: attrs });
      if (r.error) return { data: { user: null }, error: authErr(r) };
      if (session) { session = { ...session, user: r.json.user }; writeSession(session); }
      return { data: { user: r.json.user }, error: null };
    },
    onAuthStateChange(fn) {
      listeners.add(fn);
      return { data: { subscription: { unsubscribe: () => listeners.delete(fn) } } };
    },
  };

  // ── sb.storage ─────────────────────────────────────────────────────────
  const storage = {
    from(bucket) {
      return {
        async upload(path, file, opts = {}) {
          const clean = String(path).split('/').map(encodeURIComponent).join('/');
          const r = await call(`/api/storage/${encodeURIComponent(bucket)}/${clean}`,
            { raw: file, contentType: opts.contentType || file?.type || 'application/octet-stream' });
          if (r.error) return { data: null, error: { ...r.error, statusCode: String(r.status) } };
          return { data: r.json.data, error: null };
        },
        getPublicUrl(path) {
          const clean = String(path).split('/').map(encodeURIComponent).join('/');
          const origin = base || (typeof location !== 'undefined' ? location.origin : '');
          return { data: { publicUrl: `${origin}/storage/${encodeURIComponent(bucket)}/${clean}` } };
        },
        async remove(paths) {
          const r = await call(`/api/storage-remove/${encodeURIComponent(bucket)}`, { body: { prefixes: paths || [] } });
          if (r.error) return { data: null, error: r.error };
          return { data: r.json.data, error: null };
        },
      };
    },
  };

  // Realtime saytda istifadə olunmur — təhlükəsiz boş əvəz
  const channel = () => { const c = { on: () => c, subscribe: cb => { try { cb && cb('CLOSED'); } catch (_) {} return c; }, unsubscribe: async () => 'ok' }; return c; };

  return { from: t => new Query(t), rpc, auth, storage, channel, removeChannel: async () => 'ok', removeAllChannels: async () => [] };
}
