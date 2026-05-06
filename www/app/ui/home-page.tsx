import { css } from 'remix/ui'

import { routes } from '../routes.ts'

const FONT_STACK =
  "'JetBrains Mono', ui-monospace, SFMono-Regular, 'SF Mono', Menlo, Consolas, monospace"

export function HomePage() {
  return () => (
    <html lang="en">
      <head>
        <meta charSet="utf-8" />
        <meta name="viewport" content="width=device-width,initial-scale=1" />
        <meta name="color-scheme" content="light dark" />
        <title>zigtsc — TypeScript subset → C / C++ / JS compiler</title>
        <meta
          name="description"
          content="A compiler written in Zig that transpiles a strict subset of TypeScript to C, C++, and JavaScript. No Wasm intermediate, no runtime."
        />
        <link rel="preconnect" href="https://fonts.googleapis.com" />
        <link rel="preconnect" href="https://fonts.gstatic.com" crossOrigin="anonymous" />
        <link
          rel="stylesheet"
          href="https://fonts.googleapis.com/css2?family=JetBrains+Mono:wght@400;700&display=swap"
        />
        <script type="module" src={routes.assets.href({ path: 'app/assets/entry.ts' })}></script>
        <script>{COPY_SCRIPT}</script>
      </head>
      <body mix={css(bodyStyles)}>
        <main mix={css(mainStyles)}>
          <Hero />
          <Example />
          <Features />
          <QuickStart />
          <Footer />
        </main>
      </body>
    </html>
  )
}

// ── Hero ──────────────────────────────────────────────────────────────────────

function Hero() {
  return () => (
    <section
      aria-label="Introduction"
      mix={css({
        display: 'flex',
        flexDirection: 'column',
        alignItems: 'center',
        gap: '24px',
        textAlign: 'center',
      })}
    >
      <h1
        mix={css({
          margin: 0,
          fontSize: '48px',
          fontWeight: 700,
          letterSpacing: '-0.02em',
          lineHeight: 1.1,
          '@media (max-width: 600px)': { fontSize: '32px' },
        })}
      >
        zigtsc
      </h1>
      <p
        mix={css({
          margin: 0,
          fontSize: '18px',
          lineHeight: 1.6,
          color: 'var(--text-secondary)',
          maxWidth: '560px',
          '@media (max-width: 600px)': { fontSize: '15px' },
        })}
      >
        A compiler written in Zig that transpiles a strict subset of TypeScript to C, C++, and
        JavaScript. Classes, interfaces, type-checked. Three targets from one source.
      </p>
      <div mix={css({ display: 'flex', gap: '12px', flexWrap: 'wrap', justifyContent: 'center' })}>
        <Tag>TypeScript syntax</Tag>
        <Tag>→ C / C++ / JS</Tag>
        <Tag>Go-style classes</Tag>
        <Tag>Written in Zig</Tag>
      </div>
      <CopyBlock
        command={"git clone https://github.com/nathanjmorton/zigtsc && cd zigtsc && zig build -Doptimize=ReleaseFast"}
        display={"git clone https://github.com/nathanjmorton/zigtsc && cd zigtsc && zig build -Doptimize=ReleaseFast"}
      />
      <p mix={css({ margin: 0, fontSize: '12px', color: 'var(--text-tertiary)' })}>
        Requires{' '}
        <a href="https://ziglang.org/download/" mix={css(linkStyles)}>
          Zig 0.16.0
        </a>{' '}
        ·{' '}
        <a href="https://github.com/nathanjmorton/zigtsc" mix={css(linkStyles)}>
          GitHub
        </a>{' '}
        ·{' '}
        <a href={routes.docs.href()} mix={css(linkStyles)}>
          Docs
        </a>
      </p>
    </section>
  )
}

function Tag() {
  return ({ children }: { children?: any }) => (
    <span
      mix={css({
        fontSize: '12px',
        fontWeight: 700,
        padding: '4px 12px',
        borderRadius: '99px',
        background: 'var(--surface-3)',
        color: 'var(--accent)',
        border: '1px solid var(--border)',
      })}
    >
      {children}
    </span>
  )
}

// ── Side-by-side example ────────────────────────────────────────────────────

function Example() {
  return () => (
    <section aria-label="Example" mix={css({ width: '100%' })}>
      <h2 mix={css(sectionHeadingStyles)}>TypeScript in, C out</h2>
      <div
        mix={css({
          display: 'grid',
          gridTemplateColumns: '1fr 1fr',
          gap: '12px',
          '@media (max-width: 700px)': { gridTemplateColumns: '1fr' },
        })}
      >
        <CodePanel
          label="fib.ts"
          code={`function fib(n: number): number {
    if (n <= 1) {
        return n;
    }
    return fib(n - 1) + fib(n - 2);
}

const result: number = fib(10);
console.log(result);`}
        />
        <CodePanel
          label="fib.c (generated)"
          code={`#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <stdbool.h>
#include <string.h>

double fib(double n);

double fib(double n) {
    if ((n <= 1)) {
        return n;
    }
    return (fib((n - 1)) + fib((n - 2)));
}

int main(void) {
    const double result = fib(10);
    printf("%g\\n", result);
    return 0;
}`}
        />
      </div>
    </section>
  )
}

function CodePanel() {
  return ({ label, code }: { label: string; code: string }) => (
    <div mix={css({ display: 'flex', flexDirection: 'column', gap: '0' })}>
      <div
        mix={css({
          fontSize: '11px',
          fontWeight: 700,
          color: 'var(--accent)',
          padding: '8px 16px',
          background: 'var(--surface-3)',
          borderRadius: '12px 12px 0 0',
          borderBottom: '1px solid var(--border)',
        })}
      >
        {label}
      </div>
      <pre
        mix={css({
          margin: 0,
          background: 'var(--surface-3)',
          borderRadius: '0 0 12px 12px',
          padding: '16px',
          fontSize: '12px',
          lineHeight: 1.6,
          overflowX: 'auto',
          color: 'var(--text-primary)',
        })}
      >
        {code}
      </pre>
    </div>
  )
}

// ── Features ─────────────────────────────────────────────────────────────────

const FEATURES: Array<{ title: string; desc: string }> = [
  { title: 'Three targets', desc: 'One source file → C, C++, or JavaScript. Use -target c, -target cpp, or -target js.' },
  { title: 'Go-style classes', desc: 'Classes with constructors, methods, and this. No inheritance. C++ target emits .h/.cpp pairs per class.' },
  { title: 'Written in Zig', desc: 'Fast compiler with zero runtime dependencies. Single binary, cross-platform.' },
  { title: 'Type-driven codegen', desc: 'number → double, boolean → bool, string → const char*, interface → struct, class → C++ class.' },
  { title: 'console.log → printf', desc: 'Format strings inferred from types in C/C++. Stays as console.log in JS output.' },
  { title: 'Pairs with zigc', desc: 'Output .c/.cpp files can be built with zigc, zig cc, gcc, g++, or clang. Full toolchain compatibility.' },
]

function Features() {
  return () => (
    <section aria-label="Features" mix={css({ width: '100%' })}>
      <h2 mix={css(sectionHeadingStyles)}>Features</h2>
      <div
        mix={css({
          display: 'grid',
          gridTemplateColumns: 'repeat(auto-fit, minmax(240px, 1fr))',
          gap: '16px',
        })}
      >
        {FEATURES.map((f) => (
          <FeatureCard title={f.title} desc={f.desc} />
        ))}
      </div>
    </section>
  )
}

function FeatureCard() {
  return ({ title, desc }: { title: string; desc: string }) => (
    <div
      mix={css({
        background: 'var(--surface-3)',
        borderRadius: '16px',
        padding: '24px',
        display: 'flex',
        flexDirection: 'column',
        gap: '8px',
      })}
    >
      <h3
        mix={css({
          margin: 0,
          fontSize: '14px',
          fontWeight: 700,
          color: 'var(--accent)',
        })}
      >
        {title}
      </h3>
      <p mix={css({ margin: 0, fontSize: '13px', lineHeight: 1.6, color: 'var(--text-secondary)' })}>
        {desc}
      </p>
    </div>
  )
}

// ── Quick start ──────────────────────────────────────────────────────────────

function QuickStart() {
  return () => (
    <section aria-label="Quick start" mix={css({ width: '100%' })}>
      <h2 mix={css(sectionHeadingStyles)}>Quick start</h2>
      <div
        mix={css({
          background: 'var(--surface-3)',
          borderRadius: '16px',
          padding: '24px',
          display: 'flex',
          flexDirection: 'column',
          gap: '4px',
        })}
      >
        {[
          'git clone https://github.com/nathanjmorton/zigtsc',
          'cd zigtsc && zig build -Doptimize=ReleaseFast',
          './zig-out/bin/zigtsc examples/fib.ts fib.c',
          'cc -o fib fib.c && ./fib',
        ].map((line) => (
          <code
            mix={css({
              display: 'block',
              fontSize: '13px',
              lineHeight: 1.8,
              color: 'var(--text-primary)',
              '&::before': { content: '"$ "', color: 'var(--text-tertiary)' },
            })}
          >
            {line}
          </code>
        ))}
      </div>
      <p
        mix={css({
          marginTop: '16px',
          fontSize: '13px',
          color: 'var(--text-tertiary)',
          textAlign: 'center',
        })}
      >
        <a href={routes.docs.href()} mix={css(linkStyles)}>
          Read the full docs →
        </a>
      </p>
    </section>
  )
}

// ── Footer ───────────────────────────────────────────────────────────────────

function Footer() {
  return () => (
    <footer
      mix={css({
        display: 'flex',
        flexDirection: 'column',
        alignItems: 'center',
        gap: '12px',
        fontSize: '12px',
        color: 'var(--text-tertiary)',
        textAlign: 'center',
        '& a': { color: 'var(--text-tertiary)', textDecoration: 'underline', textUnderlineOffset: '2px' },
        '& a:hover': { color: 'var(--text-primary)' },
      })}
    >
      <div mix={css({ display: 'flex', gap: '16px' })}>
        <a href="https://github.com/nathanjmorton/zigtsc">GitHub</a>
        <a href={routes.docs.href()}>Docs</a>
      </div>
      <p mix={css({ margin: 0 })}>MIT License</p>
    </footer>
  )
}

// ── Shared styles ────────────────────────────────────────────────────────────

const bodyStyles = {
  '--surface-0': '#0c0d10',
  '--surface-3': '#1a1b1f',
  '--border': '#2a2b30',
  '--text-primary': '#e8e8ec',
  '--text-secondary': '#a0a0a8',
  '--text-tertiary': '#6b6b74',
  '--accent': '#60a0f0',
  '@media (prefers-color-scheme: light)': {
    '--surface-0': '#f5f5f7',
    '--surface-3': '#e8e8ec',
    '--border': '#d0d0d6',
    '--text-primary': '#1a1b1f',
    '--text-secondary': '#52525a',
    '--text-tertiary': '#8b8b94',
    '--accent': '#2563eb',
  },
  '& *, & *::before, & *::after': { boxSizing: 'border-box' },
  margin: 0,
  padding: '48px 24px',
  minHeight: '100vh',
  background: 'var(--surface-0)',
  color: 'var(--text-primary)',
  fontFamily: FONT_STACK,
  fontSize: '14px',
  lineHeight: 1.5,
  WebkitFontSmoothing: 'antialiased',
  MozOsxFontSmoothing: 'grayscale',
  display: 'flex',
  alignItems: 'flex-start',
  justifyContent: 'center',
} as const

const mainStyles = {
  width: '100%',
  maxWidth: '820px',
  display: 'flex',
  flexDirection: 'column',
  alignItems: 'center',
  gap: '72px',
  paddingTop: '48px',
} as const

const sectionHeadingStyles = {
  margin: '0 0 20px',
  fontSize: '14px',
  fontWeight: 700,
  textTransform: 'uppercase',
  letterSpacing: '0.1em',
  color: 'var(--text-primary)',
} as const

const linkStyles = {
  color: 'var(--accent)',
  textDecoration: 'underline',
  textUnderlineOffset: '2px',
  '&:hover': { color: 'var(--text-primary)' },
} as const

// ── Copy-to-clipboard ────────────────────────────────────────────────────────

function CopyBlock() {
  return ({ command, display }: { command: string; display: string }) => (
    <div
      data-copy={command}
      mix={css({
        width: '100%',
        maxWidth: '640px',
        margin: 0,
        background: 'var(--surface-3)',
        border: '1px solid var(--border)',
        borderRadius: '12px',
        padding: '16px 20px',
        cursor: 'pointer',
        position: 'relative',
        transition: 'border-color 150ms ease',
        '&:hover': { borderColor: 'var(--accent)' },
      })}
    >
      <pre
        mix={css({
          margin: 0,
          fontSize: '13px',
          lineHeight: 1.6,
          color: 'var(--text-primary)',
          overflowX: 'auto',
          whiteSpace: 'pre-wrap',
          wordBreak: 'break-all',
          '&::before': { content: '"$ "', color: 'var(--text-tertiary)' },
        })}
      >
        {display}
      </pre>
      <span
        className="copy-hint"
        mix={css({
          position: 'absolute',
          top: '8px',
          right: '12px',
          fontSize: '11px',
          color: 'var(--text-tertiary)',
          transition: 'opacity 150ms ease',
        })}
      >
        click to copy
      </span>
    </div>
  )
}

const COPY_SCRIPT = `
document.addEventListener('click', function(e) {
  var el = e.target.closest('[data-copy]');
  if (!el) return;
  e.preventDefault();
  var text = el.getAttribute('data-copy');
  var hint = el.querySelector('.copy-hint');
  navigator.clipboard.writeText(text).then(function() {
    if (hint) {
      hint.textContent = 'Copied!';
      hint.style.color = 'var(--accent)';
      hint.style.fontWeight = '700';
      setTimeout(function() {
        hint.textContent = 'click to copy';
        hint.style.color = 'var(--text-tertiary)';
        hint.style.fontWeight = 'normal';
      }, 2000);
    }
  }).catch(function() {
    // Fallback for non-secure contexts
    var textarea = document.createElement('textarea');
    textarea.value = text;
    textarea.style.cssText = 'position:fixed;left:-9999px';
    document.body.appendChild(textarea);
    textarea.select();
    document.execCommand('copy');
    document.body.removeChild(textarea);
    if (hint) {
      hint.textContent = 'Copied!';
      hint.style.color = 'var(--accent)';
      hint.style.fontWeight = '700';
      setTimeout(function() {
        hint.textContent = 'click to copy';
        hint.style.color = 'var(--text-tertiary)';
        hint.style.fontWeight = 'normal';
      }, 2000);
    }
  });
});
`
