import { useEffect, useState } from 'react'

const API = '/api'
const TOKEN_KEY = 'adminToken'

// The JWT lives in sessionStorage: survives page reloads in this tab,
// disappears when the tab closes — a good default for an admin session.
export default function Admin() {
  const [token, setToken] = useState(() => sessionStorage.getItem(TOKEN_KEY))
  const [user, setUser] = useState(null)
  const [form, setForm] = useState({ username: '', password: '' })
  const [error, setError] = useState(null)
  const [messages, setMessages] = useState(null)
  const [loading, setLoading] = useState(false)

  async function verifyToken(t) {
    const res = await fetch(`${API}/auth/me`, {
      headers: { Authorization: `Bearer ${t}` },
    })
    if (!res.ok) { logout(); return }
    const body = await res.json()
    setUser(body.user)
  }

  useEffect(() => {
    if (token) verifyToken(token)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  async function load(t) {
    setLoading(true)
    const res = await fetch(`${API}/contact`, {
      headers: { Authorization: `Bearer ${t}` },
    })
    setLoading(false)
    if (res.status === 401) { logout(); return }
    if (!res.ok) { setError(`Failed to load messages (HTTP ${res.status})`); return }
    setMessages(await res.json())
  }

  useEffect(() => {
    if (token && user) load(token)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [token, user])

  function logout() {
    sessionStorage.removeItem(TOKEN_KEY)
    setToken(null)
    setUser(null)
    setMessages(null)
    setForm({ username: '', password: '' })
  }

  async function login(e) {
    e.preventDefault()
    setError(null)
    const res = await fetch(`${API}/auth/login`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(form),
    })
    if (!res.ok) {
      setError('Wrong username or password.')
      return
    }
    const body = await res.json()
    sessionStorage.setItem(TOKEN_KEY, body.token)
    setToken(body.token)
  }

  return (
    <main className="admin">
      <header className="hero">
        <p className="hello"><a href="#/">← back to portfolio</a></p>
        <h1>Admin</h1>
        <p className="title">
          {user ? `Signed in as ${user}` : 'Sign in to read contact messages'}
        </p>
      </header>

      {!token && (
        <form onSubmit={login} className="contact-form">
          <input
            placeholder="Username"
            value={form.username}
            required
            onChange={(e) => setForm({ ...form, username: e.target.value })}
          />
          <input
            type="password"
            placeholder="Password"
            value={form.password}
            required
            onChange={(e) => setForm({ ...form, password: e.target.value })}
          />
          <button type="submit">Sign in</button>
          {error && <p className="form-error">{error}</p>}
        </form>
      )}

      {token && (
        <section>
          <div className="admin-bar">
            <button onClick={() => token && load(token)}>
              {loading ? 'Refreshing…' : 'Refresh'}
            </button>
            <button className="secondary" onClick={logout}>Sign out</button>
          </div>

          {messages && messages.length === 0 && <p>No messages yet.</p>}
          {messages && messages.map((m) => (
            <div className="project" key={m.id}>
              <div className="job-head">
                <h3>#{m.id} — {m.name} <span className="company">&lt;{m.email}&gt;</span></h3>
                <span className="period">{new Date(m.createdAtUtc).toLocaleString()}</span>
              </div>
              <p>{m.message}</p>
            </div>
          ))}
        </section>
      )}
    </main>
  )
}
