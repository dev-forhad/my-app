// ── ALL YOUR PORTFOLIO CONTENT LIVES HERE ────────────────────────────────────
// Edit this file, commit, push — the pipeline deploys it. Nothing else to touch.

export const profile = {
  name: 'Forhad Hussain Khan',
  title: 'Software Engineer · Data Engineer',
  location: 'Kawasaki, Japan',
  email: 'forhad.mml@gmail.com',
  phone: '+81 70-8466-2983',
  github: 'https://github.com/dev-forhad',
  linkedin: 'https://linkedin.com/in/forhad-khan-bd',
  about:
    'Experienced Software Engineer and Data Engineer with expertise in system development, ' +
    'data integration, and offshore team coordination. I have delivered solutions across ' +
    'fintech, enterprise systems, and BI reporting — from writing the code myself to acting ' +
    'as the Bridge SE between Japanese stakeholders and offshore development teams. ' +
    'I care about code quality, reliable data, and shipping things that work in production — ' +
    'including this site, which runs on AWS behind a CI/CD pipeline I built.',
}

export const experience = [
  {
    company: 'Rakuten Group, Inc.',
    role: 'Data Engineer',
    period: '04/2026 – Present',
    location: 'Tokyo, Japan',
    points: [
      'Develop and maintain BI reports and dashboards in DOMO, turning business requirements into actionable insights for corporate users.',
      'Design and support ETL processes integrating data from Couchbase and relational databases for reporting and analytics.',
      'Analyze data discrepancies and root causes, fixing them with SQL and Python to improve data accuracy and reliability.',
      'Review and optimize SQL queries and data workflows to improve performance, data quality, and user experience.',
    ],
  },
  {
    company: 'JBBC株式会社',
    role: 'System Engineer (Bridge SE)',
    period: '10/2023 – 03/2026',
    location: 'Tokyo, Japan',
    points: [
      'Collected and analyzed requirements from Japanese clients and translated them into detailed technical specifications for offshore teams.',
      'Acted as Bridge SE between Japanese stakeholders and Bangladesh developers — clarifying requirements and keeping the project aligned end to end.',
      'Provided technical guidance to offshore developers, reviewed design documents and deliverables against quality standards.',
      'Contributed to system design, development, testing, and issue resolution through to timely delivery.',
    ],
  },
  {
    company: 'ASA — Bangladesh',
    role: 'Software Engineer',
    period: '04/2022 – 10/2023',
    location: 'Dhaka, Bangladesh',
    points: [
      'Developed and enhanced modules for the ASA Microfinance Management System, Country Management System, and Monitoring System.',
      'Optimized SQL queries and database structures to improve performance and reduce response times.',
      'Reviewed and refactored existing modules for code quality, maintainability, and stability.',
      'Conducted code reviews for junior developers and enforced coding standards.',
    ],
  },
  {
    company: 'Datasoft Systems Bangladesh Ltd',
    role: 'Software Engineer',
    period: '01/2017 – 04/2022',
    location: 'Dhaka, Bangladesh',
    points: [
      'Designed, developed, and maintained scalable software solutions with a focus on quality, reliability, and performance.',
      'Worked across the full SDLC: requirement analysis, implementation, testing, deployment, and release management.',
      'Mentored junior engineers through code reviews and knowledge sharing on architecture and design patterns.',
      'Prepared technical documentation and translated business requirements into effective solutions.',
    ],
  },
]

export const projects = [
  {
    name: 'BSS Data Integration & Reporting Platform',
    org: 'Rakuten Mobile',
    period: '04/2026 – Present',
    tech: ['DOMO', 'Python', 'SQL', 'Couchbase', 'Selenium'],
    description:
      'Data integration and reporting platform for corporate business operations: extracts data from Couchbase, ' +
      'transforms and loads it into relational databases via Python ETL, and delivers reports through DOMO dashboards. ' +
      'Selenium-based automation of report generation supports monitoring and decision-making.',
  },
  {
    name: 'Enterprise System Development & Maintenance',
    org: 'Japanese clients via JBBC',
    period: '11/2023 – 03/2026',
    tech: ['C#', 'ASP.NET 4.8', 'VB.NET', 'SQL Server', 'PostgreSQL', 'Dapper', 'Razor Pages'],
    description:
      'Developed and maintained enterprise applications: production management systems, reporting tools, batch ' +
      'processing, and desktop apps. Implemented Web Services and integration mechanisms connecting legacy and ' +
      'modern systems while automating business processes.',
  },
  {
    name: 'ASAMS — Microfinance Management System',
    org: 'ASA Bangladesh',
    period: '04/2023 – 10/2023',
    tech: ['ASP.NET MVC', 'SQL Server', 'Redis', 'SignalR', 'JWT', 'Docker', 'GitLab CI/CD'],
    description:
      'Web-based, dashboard-driven system automating microfinance operations: loans, savings, accounts, assets, ' +
      'inventory, HRM, and fund planning — enabling real-time monitoring and efficient business processes.',
  },
  {
    name: 'VerifID — eKYC & Digital Onboarding',
    org: 'Datasoft Systems',
    period: '12/2017 – 04/2022',
    tech: ['Python', 'ASP.NET Core', 'Django REST', 'OCR (Tesseract, EasyOCR)', 'Redis', 'Selenium'],
    description:
      'eKYC solution for safe, easy customer onboarding: OCR-based NID and smart-card data capture, NID server ' +
      'verification, face and fingerprint matching, and integration with banking systems (CBS, ABS, MFS).',
  },
  {
    name: 'Agent Banking Solutions',
    org: 'Datasoft Systems',
    period: '01/2017 – 04/2022',
    tech: ['ASP.NET Core', 'SQL Server', 'Oracle', 'SignalR', 'LDAP', 'JWT'],
    description:
      'Next-generation agent banking platform extending services to rural communities: secure transactions through ' +
      'agent networks with OTP/2FA, biometric verification, and real-time communication.',
  },
]

export const skillGroups = [
  {
    title: 'Languages & Frameworks',
    items: [
      'C#', 'Python', 'Java', 'VBA', 'ASP.NET', 'ASP.NET Core', 'Django REST',
      'React', 'JavaScript', 'jQuery', 'SQL Server', 'MySQL', 'PostgreSQL', 'Redis', 'Couchbase',
    ],
  },
  {
    title: 'Tools & Technology',
    items: [
      'REST API', 'Git', 'Docker', 'Microservices', 'Design Patterns', 'Dapper ORM',
      'CI/CD', 'AWS', 'Jenkins', 'GitLab CI', 'Selenium', 'OpenCV', 'JWT Authentication',
      'SignalR', 'Swagger/OpenAPI', 'Entity Framework', 'Serilog', 'RabbitMQ',
      'Razor Pages', 'LDAP', 'Windows Services', 'AI-assisted development',
    ],
  },
  {
    title: 'Engineering Practices',
    items: [
      'Bridge System Engineering (Bridge SE)',
      'Software Architecture & System Design',
      'Offshore Team Coordination & Mentoring',
      'Agile / Scrum & SDLC',
      'SOLID Principles & Code Quality',
      'Project Delivery & Multi-tasking',
    ],
  },
]

export const education = {
  degree: 'B.Sc. in Computer Science & Engineering',
  school: 'Bangladesh University',
  period: '02/2013 – 02/2017',
  location: 'Dhaka, Bangladesh',
  detail: 'CGPA 3.64 / 4.00',
}

export const languages = [
  { name: 'Japanese', note: 'NAT-Test N4 passed' },
  { name: 'English', note: 'Professional working proficiency' },
  { name: 'Bangla', note: 'Native' },
  { name: 'Hindi', note: 'Conversational' },
]
