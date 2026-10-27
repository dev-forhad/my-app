import { useEffect, useState } from 'react'
import {
  profile, experience, projects, skillGroups, education, languages,
} from './data.js'
import Admin from './Admin.jsx'

const CONTACT_API = '/api/contact'

// Minimal hash router: '#/admin' shows the admin console. Using the hash
// (not a path like /admin) means the browser never sends it to the server,
// so static hosting on S3 works without any rewrite rules.
function useHashRoute() {
  const [hash, setHash] = useState(() => window.location.hash)
  useEffect(() => {
    const onChange = () => setHash(window.location.hash)
    window.addEventListener('hashchange', onChange)
    return () => window.removeEventListener('hashchange', onChange)
  }, [])
  return hash
}

function ContactForm() {
  const [form, setForm] = useState({ name: '', email: '', message: '' })
  const [status, setStatus] = useState(null)

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
        Thanks — your message reached my database. I will get back to you soon.
      </p>
    )
  }

  return (
    <form onSubmit={submit} className="contact-form">
      <div className="form-row">
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
      </div>
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

function Hero() {
  return (
    <header className="hero">
      <p className="hello">こんにちは · Hello, I'm</p>
      <h1>{profile.name}</h1>
      <p className="title">{profile.title}</p>
      <p className="meta">{profile.location}</p>
      <p className="links">
        <a href={`mailto:${profile.email}`}>{profile.email}</a>
        <a href={`tel:${profile.phone.replace(/[^+\d]/g, '')}`}>{profile.phone}</a>
        <a href={profile.linkedin} target="_blank" rel="noreferrer">LinkedIn</a>
        <a href={profile.github} target="_blank" rel="noreferrer">GitHub</a>
      </p>
    </header>
  )
}

function Experience() {
  return (
    <section id="experience">
      <h2>Experience</h2>
      <div className="timeline">
        {experience.map((job) => (
          <div className="job" key={job.company}>
            <div className="job-head">
              <h3>{job.role} · <span className="company">{job.company}</span></h3>
              <span className="period">{job.period} | {job.location}</span>
            </div>
            <ul>
              {job.points.map((pt) => <li key={pt}>{pt}</li>)}
            </ul>
          </div>
        ))}
      </div>
    </section>
  )
}

function Projects() {
  return (
    <section id="projects">
      <h2>Projects</h2>
      {projects.map((p) => (
        <div className="project" key={p.name}>
          <div className="job-head">
            <h3>{p.name} <span className="company">· {p.org}</span></h3>
            <span className="period">{p.period}</span>
          </div>
          <p>{p.description}</p>
          <div className="skills">
            {p.tech.map((t) => <span key={t} className="chip">{t}</span>)}
          </div>
        </div>
      ))}
    </section>
  )
}

function Skills() {
  return (
    <section id="skills">
      <h2>Skills</h2>
      {skillGroups.map((g) => (
        <div className="skill-group" key={g.title}>
          <h3>{g.title}</h3>
          <div className="skills">
            {g.items.map((s) => <span key={s} className="chip">{s}</span>)}
          </div>
        </div>
      ))}
    </section>
  )
}

function EducationLanguages() {
  return (
    <section id="education">
      <h2>Education & Languages</h2>
      <div className="edu">
        <h3>{education.degree} · <span className="company">{education.school}</span></h3>
        <span className="period">{education.period} | {education.location} | {education.detail}</span>
      </div>
      <div className="skills">
        {languages.map((l) => (
          <span key={l.name} className="chip"><strong>{l.name}</strong> — {l.note}</span>
        ))}
      </div>
    </section>
  )
}

export default function App() {
  const hash = useHashRoute()
  if (hash.startsWith('#/admin')) return <Admin />

  return (
    <main>
      <Hero />

      <section id="about">
        <h2>About</h2>
        <p>{profile.about}</p>
      </section>

      <Experience />
      <Projects />
      <Skills />
      <EducationLanguages />

      <section id="contact">
        <h2>Contact</h2>
        <p className="contact-lead">
          The fastest way to reach me is email or LinkedIn — or leave a message here.
          Every submission is stored in my own PostgreSQL database on AWS.
        </p>
        <ContactForm />
      </section>

      <footer>
        <span>© {new Date().getFullYear()} {profile.name} · Kawasaki, Japan</span>
        <span> · React · .NET · PostgreSQL · AWS · deployed by GitHub Actions</span>
        <span> · <a className="admin-link" href="#/admin">Admin</a></span>
      </footer>
    </main>
  )
}
