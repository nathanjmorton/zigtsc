import { css } from 'remix/ui'

import { routes } from '../routes.ts'

const FONT_STACK =
  "'JetBrains Mono', ui-monospace, SFMono-Regular, 'SF Mono', Menlo, Consolas, monospace"

export function DocsPage() {
  return () => (
    <html lang="en">
      <head>
        <meta charSet="utf-8" />
        <meta name="viewport" content="width=device-width,initial-scale=1" />
        <meta name="color-scheme" content="light dark" />
        <title>zigtsc docs</title>
        <link rel="preconnect" href="https://fonts.googleapis.com" />
        <link rel="preconnect" href="https://fonts.gstatic.com" crossOrigin="anonymous" />
        <link
          rel="stylesheet"
          href="https://fonts.googleapis.com/css2?family=JetBrains+Mono:wght@400;700&display=swap"
        />
        <script type="module" src={routes.assets.href({ path: 'app/assets/entry.ts' })}></script>
      </head>
      <body mix={css(bodyStyles)}>
        <nav mix={css(navStyles)}>
          <a href={routes.home.href()} mix={css(navLinkStyles)}>← zigtsc</a>
          <a href="https://github.com/nathanjmorton/zigtsc" mix={css(navLinkStyles)}>GitHub</a>
        </nav>
        <main mix={css(mainStyles)}>
          <h1 mix={css({ margin: 0, fontSize: '32px', fontWeight: 700 })}>Documentation</h1>

          <Section title="Usage">
            <CodeBlock lines={[
              'zigtsc <input.ts>              # print C to stdout',
              'zigtsc <input.ts> <output.c>   # write C to file',
            ]} />
            <P>
              zigtsc reads a <Code>.ts</Code> file, parses the TypeScript subset, type-checks it,
              and emits idiomatic C. The generated C compiles with any standard C compiler.
            </P>
          </Section>

          <Section title="Build from source">
            <CodeBlock lines={[
              'git clone https://github.com/nathanjmorton/zigtsc',
              'cd zigtsc',
              'zig build -Doptimize=ReleaseFast',
              'export PATH="$PWD/zig-out/bin:$PATH"',
            ]} />
            <P>Requires <A href="https://ziglang.org/download/">Zig 0.16.0</A>.</P>
          </Section>

          <Section title="Compiler pipeline">
            <CodeBlock lines={[
              'source.ts → Lexer → Tokens → Parser → AST → Type Checker → C Codegen → output.c',
            ]} />
            <P>Each stage is a separate Zig source file with clear input/output boundaries.</P>
            {[
              ['token.zig', 'Token type definitions — keywords, operators, literals, punctuation'],
              ['lexer.zig', 'Tokenizer with comment skipping, string/number/identifier support'],
              ['ast.zig', 'AST node definitions with packed string refs and extra data array'],
              ['parser.zig', 'Recursive descent parser with precedence climbing for expressions'],
              ['checker.zig', 'Type checker with scoped symbol table, struct and function registration'],
              ['codegen.zig', 'C emitter — interface→struct, console.log→printf, type-driven output'],
              ['main.zig', 'CLI entry point'],
            ].map(([file, desc]) => (
              <div mix={css({ display: 'flex', gap: '16px', padding: '4px 0', flexWrap: 'wrap' })}>
                <code mix={css({ fontSize: '13px', color: 'var(--accent)', whiteSpace: 'nowrap', minWidth: '120px' })}>{file}</code>
                <span mix={css({ fontSize: '13px', color: 'var(--text-secondary)' })}>{desc}</span>
              </div>
            ))}
          </Section>

          <Section title="Supported types">
            {[
              ['number', 'double'],
              ['boolean', 'bool'],
              ['string', 'const char*'],
              ['void', 'void'],
              ['i32', 'int32_t'],
              ['i64', 'int64_t'],
              ['f32', 'float'],
              ['f64', 'double'],
              ['T[]', 'double* (simplified)'],
              ['interface Foo { ... }', 'typedef struct { ... } Foo;'],
            ].map(([ts, c]) => (
              <div mix={css({ display: 'flex', gap: '16px', padding: '4px 0', flexWrap: 'wrap' })}>
                <code mix={css({ fontSize: '13px', color: 'var(--text-primary)', minWidth: '220px' })}>{ts}</code>
                <span mix={css({ fontSize: '13px', color: 'var(--text-tertiary)' })}>→ {c}</span>
              </div>
            ))}
          </Section>

          <Section title="Supported syntax">
            <H3>Variables</H3>
            <CodeBlock lines={[
              'let x: number = 42;          → double x = 42;',
              'const msg: string = "hi";    → const char* msg = "hi";',
            ]} />

            <H3>Functions</H3>
            <CodeBlock lines={[
              'function add(a: number, b: number): number {',
              '    return a + b;',
              '}',
              '',
              '→ double add(double a, double b) {',
              '      return (a + b);',
              '  }',
            ]} />

            <H3>Interfaces → Structs</H3>
            <CodeBlock lines={[
              'interface Point {              → typedef struct {',
              '    x: number;                       double x;',
              '    y: number;                       double y;',
              '}                              } Point;',
            ]} />

            <H3>Control flow</H3>
            <P>
              <Code>if</Code> / <Code>else if</Code> / <Code>else</Code>, <Code>while</Code>,{' '}
              <Code>for</Code> (C-style 3-part), <Code>return</Code> — all map directly to their C equivalents.
            </P>

            <H3>Expressions</H3>
            <P>
              Arithmetic (<Code>+ - * / %</Code>), comparison (<Code>{'< > <= >= == != === !=='}</Code>),
              logical (<Code>{'&& || !'}</Code>), assignment (<Code>= += -= *= /=</Code>),
              function calls, member access (<Code>a.b</Code>), index access (<Code>a[i]</Code>).
            </P>

            <H3>console.log</H3>
            <P>
              <Code>console.log(x)</Code> is transpiled to <Code>printf()</Code> with format strings
              inferred from types: <Code>%g</Code> for numbers, <Code>%s</Code> for strings,{' '}
              <Code>%d</Code> for booleans.
            </P>
          </Section>

          <Section title="Explicitly excluded">
            <P>These TypeScript features are intentionally unsupported for clean C mapping:</P>
            <ul mix={css({ margin: 0, paddingLeft: '20px', fontSize: '14px', lineHeight: 1.8, color: 'var(--text-secondary)' })}>
              <li><Code>class</Code>, <Code>this</Code>, prototypes</li>
              <li>Closures / capturing nested functions</li>
              <li><Code>async</Code> / <Code>await</Code>, Promises</li>
              <li>Generics, union types, <Code>any</Code>, <Code>unknown</Code></li>
              <li>Decorators, destructuring, spread, optional chaining</li>
              <li><Code>eval</Code>, <Code>new Function()</Code></li>
            </ul>
          </Section>

          <Section title="Memory model">
            <P>
              Stack allocation by default for scalars and small structs. Arrays are heap-allocated
              with <Code>malloc</Code> — the caller is responsible for <Code>free</Code>. There is no
              garbage collector. The language is explicitly manual-memory, like C itself.
            </P>
          </Section>

          <Section title="Examples">
            <P>Three example programs are included in the <Code>examples/</Code> directory:</P>

            <H3>hello.ts</H3>
            <CodeBlock lines={[
              'const message: string = "hello world";',
              'console.log(message);',
            ]} />

            <H3>fib.ts</H3>
            <CodeBlock lines={[
              'function fib(n: number): number {',
              '    if (n <= 1) { return n; }',
              '    return fib(n - 1) + fib(n - 2);',
              '}',
              'const result: number = fib(10);',
              'console.log(result);',
            ]} />

            <H3>structs.ts</H3>
            <CodeBlock lines={[
              'interface Point { x: number; y: number; }',
              '',
              'function distance(a: Point, b: Point): number {',
              '    let dx: number = b.x - a.x;',
              '    let dy: number = b.y - a.y;',
              '    return dx * dx + dy * dy;',
              '}',
              '',
              'const p1: Point = { x: 0, y: 0 };',
              'const p2: Point = { x: 3, y: 4 };',
              'console.log(distance(p1, p2));',
            ]} />
          </Section>

          <Section title="Running tests">
            <CodeBlock lines={['zig build test --summary all']} />
            <P>
              The test suite includes 13 tests covering the lexer, parser, and end-to-end codegen.
              All tests pass with zero memory leaks.
            </P>
          </Section>

          <footer mix={css({ paddingTop: '24px', fontSize: '12px', color: 'var(--text-tertiary)', textAlign: 'center' })}>
            <a href={routes.home.href()} mix={css({ color: 'var(--accent)', textDecoration: 'underline', textUnderlineOffset: '2px' })}>
              ← Back to zigtsc
            </a>
          </footer>
        </main>
      </body>
    </html>
  )
}

// ── Reusable components ──────────────────────────────────────────────────────

function Section() {
  return ({ title, children }: { title: string; children?: any }) => (
    <section mix={css({ width: '100%', display: 'flex', flexDirection: 'column', gap: '12px' })}>
      <h2 mix={css({ margin: 0, fontSize: '18px', fontWeight: 700, paddingBottom: '4px', borderBottom: '1px solid var(--border)' })}>{title}</h2>
      {children}
    </section>
  )
}

function H3() {
  return ({ children }: { children?: any }) => (
    <h3 mix={css({ margin: '8px 0 0', fontSize: '14px', fontWeight: 700, color: 'var(--text-primary)' })}>{children}</h3>
  )
}

function P() {
  return ({ children }: { children?: any }) => (
    <p mix={css({ margin: 0, fontSize: '14px', lineHeight: 1.7, color: 'var(--text-secondary)' })}>{children}</p>
  )
}

function A() {
  return ({ href, children }: { href: string; children?: any }) => (
    <a href={href} mix={css({ color: 'var(--accent)', textDecoration: 'underline', textUnderlineOffset: '2px' })}>{children}</a>
  )
}

function Code() {
  return ({ children }: { children?: any }) => (
    <code mix={css({ fontSize: '13px', background: 'var(--surface-3)', padding: '1px 5px', borderRadius: '4px' })}>{children}</code>
  )
}

function CodeBlock() {
  return ({ lines }: { lines: string[] }) => (
    <pre
      mix={css({
        margin: 0,
        background: 'var(--surface-3)',
        borderRadius: '12px',
        padding: '16px 20px',
        fontSize: '13px',
        lineHeight: 1.7,
        overflowX: 'auto',
        color: 'var(--text-primary)',
        whiteSpace: 'pre-wrap',
        wordBreak: 'break-all',
      })}
    >
      {lines.join('\n')}
    </pre>
  )
}

// ── Styles ───────────────────────────────────────────────────────────────────

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
  flexDirection: 'column',
  alignItems: 'center',
} as const

const mainStyles = {
  width: '100%',
  maxWidth: '760px',
  display: 'flex',
  flexDirection: 'column',
  gap: '40px',
  paddingTop: '24px',
} as const

const navStyles = {
  width: '100%',
  maxWidth: '760px',
  display: 'flex',
  justifyContent: 'space-between',
  alignItems: 'center',
  paddingBottom: '16px',
  borderBottom: '1px solid var(--border)',
} as const

const navLinkStyles = {
  fontSize: '13px',
  color: 'var(--text-tertiary)',
  textDecoration: 'none',
  '&:hover': { color: 'var(--text-primary)' },
} as const
