import { useState } from 'react'

// All requests are relative: locally the Vite dev server proxies /api to the
// .NET API; in production CloudFront routes /api/* to Elastic Beanstalk.
const CONTACT_API = '/api/contact'

// ── EDIT ME: your real content lives in this one file ────────────────────────
const PROFILE = {
  name: 'Forhad Hussain Khan',
  title: 'Full-Stack Developer',
  github: 'https://github.com/dev-forhad',
  linkedin: '', // add your LinkedIn URL here when ready
  email: 'you@example.com', // EDIT ME — shown in the footer/contact section
  about:
    'I build web applications end to end — React on the front, .NET APIs behind, ' +
    'backed by PostgreSQL and shipped to AWS through automated CI/CD pipelines. ' +
    'This very site is an example: it is a React app and a .NET API deployed from ' +
    'git push to production with GitHub Actions, CloudFront and Elastic Beanstalk.',
  skills: [
    'C# / .NET', 'React', 'JavaScript', 'PostgreSQL', 'Docker',
    'AWS', 'GitHub Actions', 'Git', 'REST APIs', 'EF Core',
  ],
  projects: [
    {
      name: 'This website',
      description:
        'React + .NET 8 + PostgreSQL deployed to AWS (S3, CloudFront, Elastic ' +
        'Beanstalk) entirely through a GitHub Actions CI/CD pipeline.',
      link: 'https://github.com/dev-forhad/my-app',
    },
    {
      name: 'Project two — EDIT ME',
      description: 'Short description of another project: what it does and what you learned building it.',
      link: 'https://github.com/dev-forhad',
    },
    {
      name: 'Project three — EDIT ME',
      description: 'Another project. Two or three sentences is plenty.',
      link: 'https://github.com/dev-forhad',
    },
  ],
}

function ContactForm() {
  const [form, setForm] = useState({ name: '', email: '', message: '' })
  const [status, setStatus] = useState(null) // null | 'sending' | 'sent' | error text

  async function submit(e) {
    e.preventDefault()
    setStatus('sending')
    try {
      const res = await fetch(CONTACT_API, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(form),
      })
      if (res.ok) {
        setStatus('sent')
        setForm({ name: '', email: '', message: '' })
      } else {
        const body = await res.json().catch(() => ({}))
        setStatus(body.error || `Could not send (HTTP ${res.status})`)
      }
    } catch {
      setStatus('Network error — try again.')
    }
  }

  if (status === 'sent') {
    return (
      <p className="sent">
        Thanks — your message landed in my database. I will get back to you soon.
      </p>
    )
  }

  return (
    <form onSubmit={submit} className="contact-form">
      <input
        placeholder="Your name"
        value={form.name}
        maxLength={100}
        required
        onChange={(e) => setForm({ ...form, name: e.target.value })}
      />
      <input
        type="email"
        placeholder="Your email"
        value={form.email}
        maxLength={200}
        required
        onChange={(e) => setForm({ ...form, email: e.target.value })}
      />
      <textarea
        placeholder="Your message"
        rows={4}
        value={form.message}
        maxLength={2000}
        required
        onChange={(e) => setForm({ ...form, message: e.target.value })}
      />
      <button type="submit" disabled={status === 'sending'}>
        {status === 'sending' ? 'Sending…' : 'Send message'}
      </button>
      {status && status !== 'sending' && <p className="form-error">{status}</p>}
    </form>
  )
}

export default function App() {
  return (
    <main>
      <header className="hero">
        <h1>{PROFILE.name}</h1>
        <p className="title">{PROFILE.title}</p>
        <p className="links">
          <a href={PROFILE.github} target="_blank" rel="noreferrer">GitHub</a>
          {PROFILE.linkedin && <a href={PROFILE.linkedin} target="_blank" rel="noreferrer">LinkedIn</a>}
        </p>
      </header>

      <section>
        <h2>About</h2>
        <p>{PROFILE.about}</p>
      </section>

      <section>
        <h2>Skills</h2>
        <div className="skills">
          {PROFILE.skills.map((s) => <span key={s} className="chip">{s}</span>)}
        </div>
      </section>

      <section>
        <h2>Projects</h2>
        {PROFILE.projects.map((p) => (
          <a key={p.name} className="project" href={p.link} target="_blank" rel="noreferrer">
            <h3>{p.name}</h3>
            <p>{p.description}</p>
          </a>
        ))}
      </section>

      <section>
        <h2>Contact</h2>
        <ContactForm />
      </section>

      <footer>
        <span>© {new Date().getFullYear()} {PROFILE.name}</span>
        {PROFILE.email !== 'you@example.com' && <span> · {PROFILE.email}</span>}
        <span> · React · .NET · PostgreSQL · AWS</span>
      </footer>
    </main>
  )
}
