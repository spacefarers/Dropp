'use client';

import Link from 'next/link';
import { useMemo } from 'react';

export default function Home({ navAuth, primaryCta }: { navAuth?: React.ReactNode; primaryCta?: React.ReactNode }) {
  const year = useMemo(() => new Date().getFullYear(), []);
  const navContent = navAuth ?? null;
  const primary = primaryCta ?? <a className="btn btn-primary" href="https://github.com/spacefarers/Dropp/releases" target="_blank" rel="noreferrer">Download Dropp</a>;

  return (
    <>
      <header>
        <div className="brand">
          <div className="brand-icon">DR</div>
          <span className="brand-title">Dropp</span>
        </div>
        <nav className="header-links">
          {navContent}
          <a className="header-link" href="https://github.com/spacefarers/Dropp" target="_blank" rel="noreferrer">GitHub</a>
        </nav>
      </header>

      <main>
        <section className="hero">
          <div>
            <h1>Your cross-platform dropzone HQ.</h1>
            <p>
              Dropp keeps your files and snippets within reach across macOS, Windows, and the web.
              Park anything in the cloud-backed dropzone, then drag, share, or transfer between devices without breaking flow.
            </p>
            <div className="cta-group">
              {primary}
              <a className="btn btn-secondary" href="https://github.com/spacefarers/Dropp" target="_blank" rel="noreferrer">
                View on GitHub
              </a>
            </div>
          </div>

          <aside className="feature-card" aria-label="Feature highlights">
            <div className="feature-grid">
              <article className="feature">
                <div className="feature-icon">⇅</div>
                <div>
                  <h3 className="feature-title">Drag &amp; Drop Anywhere</h3>
                  <p>Pin files, links, and text snippets in a unified dropzone synced across all your devices.</p>
                </div>
              </article>
              <article className="feature">
                <div className="feature-icon">☁</div>
                <div>
                  <h3 className="feature-title">Cloud Transfer</h3>
                  <p>Send large files effortlessly through Dropp's transfer pipeline—no USB drives, no email attachments.</p>
                </div>
              </article>
              <article className="feature">
                <div className="feature-icon">⚡</div>
                <div>
                  <h3 className="feature-title">Fast &amp; Secure</h3>
                  <p>Backed by Firebase authentication, Vercel Blob storage, and MongoDB for a responsive, reliable workflow.</p>
                </div>
              </article>
            </div>
          </aside>
        </section>
      </main>

      <footer>
        <span>© {year} Dropp. Built for makers on every platform.</span>
        <a href="https://github.com/spacefarers/Dropp" target="_blank" rel="noreferrer">github.com/spacefarers/Dropp</a>
      </footer>
    </>
  );
}
