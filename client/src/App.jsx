import { useEffect, useState } from 'react'

// All requests are relative: locally the Vite dev server proxies /api to the
// .NET API; in production CloudFront serves the React build and forwards
// /api/* to Elastic Beanstalk. Same code, no per-environment URLs.
const API = '/api/items'

export default function App() {
  const [items, setItems] = useState(null)
  const [title, setTitle] = useState('')
  const [error, setError] = useState(null)

  async function load() {
    try {
      const res = await fetch(API)
      if (!res.ok) throw new Error(`API responded ${res.status}`)
      setItems(await res.json())
      setError(null)
    } catch (e) {
      setError(`Could not reach the API: ${e.message}`)
    }
  }

  useEffect(() => { load() }, [])

  async function add(e) {
    e.preventDefault()
    const res = await fetch(API, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ title }),
    })
    if (res.ok) {
      setTitle('')
      load()
    }
  }

  async function toggle(id) {
    await fetch(`${API}/${id}/toggle`, { method: 'POST' })
    load()
  }

  async function remove(id) {
    await fetch(`${API}/${id}`, { method: 'DELETE' })
    load()
  }

  return (
    <main>
      <h1>My App</h1>
      <p className="subtitle">
        React on S3 + CloudFront · .NET API on Elastic Beanstalk · PostgreSQL in Docker
      </p>

      <form onSubmit={add}>
        <input
          value={title}
          onChange={(e) => setTitle(e.target.value)}
          placeholder="New item…"
          maxLength={200}
          required
        />
        <button type="submit">Add</button>
      </form>

      {error && <p className="error">{error}</p>}
      {items === null && !error && <p className="muted">Loading…</p>}
      {items && items.length === 0 && <p className="muted">No items yet — add one above.</p>}

      <ul>
        {(items ?? []).map((t) => (
          <li key={t.id} className={t.isDone ? 'done' : ''}>
            <span className="title" onClick={() => toggle(t.id)} title="Click to toggle">
              {t.title}
            </span>
            <button className="remove" onClick={() => remove(t.id)} aria-label="Delete">
              ✕
            </button>
          </li>
        ))}
      </ul>
    </main>
  )
}
