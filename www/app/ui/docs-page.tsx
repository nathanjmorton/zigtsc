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
              'zigtsc <input.ts>                         # print C to stdout',
              'zigtsc <input.ts> <output.c>              # write C to file',
              'zigtsc <input.ts> -target js <output.js>  # transpile to JavaScript',
              'zigtsc <input.ts> -target cpp <outdir/>   # C++ multi-file output',
            ]} />
            <P>
              zigtsc reads a <Code>.ts</Code> file, parses the TypeScript subset, type-checks it,
              and emits code in one of three targets: C (default), C++, or JavaScript.
            </P>
          </Section>

          <Section title="Install">
            <H3>Homebrew (recommended)</H3>
            <CodeBlock lines={[
              'brew install nathanjmorton/zigtsc/zigtsc',
            ]} />
            <P>
              Upgrade via Homebrew: <Code>brew upgrade zigtsc</Code>.
            </P>

            <H3>Shell script</H3>
            <CodeBlock lines={[
              'curl -fsSL https://raw.githubusercontent.com/nathanjmorton/zigtsc/main/install.sh | bash',
            ]} />
            <P>
              The installer detects your platform (macOS/Linux, arm64/x86_64), downloads the correct binary
              from GitHub releases, and places it at <Code>~/.zigtsc/bin/zigtsc</Code>. It also
              adds <Code>ZIGTSC_INSTALL</Code> and updates your <Code>PATH</Code> in your shell config.
            </P>
            <P>
              To install a specific version:
            </P>
            <CodeBlock lines={[
              'curl -fsSL https://raw.githubusercontent.com/nathanjmorton/zigtsc/main/install.sh | bash -s v0.1.0',
            ]} />

            <H3>Build from source</H3>
            <CodeBlock lines={[
              'git clone https://github.com/nathanjmorton/zigtsc',
              'cd zigtsc',
              'zig build -Doptimize=ReleaseFast',
              'export PATH="$PWD/zig-out/bin:$PATH"',
            ]} />
            <P>Requires <A href="https://ziglang.org/download/">Zig 0.16.0</A>.</P>
          </Section>

          <Section title="Targets">
            <H3>C (default)</H3>
            <P>
              Single-file output. Interfaces become <Code>typedef struct</Code>, functions map
              directly, <Code>console.log</Code> becomes <Code>printf</Code>. Compile with{' '}
              <A href="https://zigc.nathanjmorton.com">zigc</A>.
            </P>
            <CodeBlock lines={[
              'zigtsc fib.ts fib.c',
              'zigc init fib-app && cp fib.c fib-app/src/main.c',
              'cd fib-app && zigc run',
            ]} />

            <H3>JavaScript (-target js)</H3>
            <P>
              Strips all type annotations and emits clean JS. Interfaces are omitted (compile-time only).
              Classes, <Code>this</Code>, and <Code>new</Code> emit directly as ES6 syntax.
              <Code>console.log</Code> stays as-is.
            </P>
            <CodeBlock lines={[
              'zigtsc counter.ts -target js counter.js',
              'node counter.js',
            ]} />

            <H3>C++ (-target cpp)</H3>
            <P>
              Multi-file output. Each class emits a <Code>.h</Code>/<Code>.cpp</Code> pair with
              <Code>#pragma once</Code>, scoped method implementations (<Code>ClassName::method()</Code>),
              and <Code>this-&gt;</Code> for field access. Free functions and top-level code go in <Code>main.cpp</Code>.
              Dependency-aware <Code>#include</Code>s are generated automatically.
              Compile with <A href="https://zigc.nathanjmorton.com">zigc</A>.
            </P>
            <CodeBlock lines={[
              'mkdir -p out && zigtsc counter.ts -target cpp out/',
              'zigc init counter-app --cpp',
              'cp out/*.h out/*.cpp counter-app/src/',
              'cd counter-app && zigc run',
            ]} />
          </Section>

          <Section title="Scaffold a project">
            <CodeBlock lines={[
              'zigtsc init myapp',
              'cd myapp',
            ]} />
            <P>
              Creates <Code>main.ts</Code> with interfaces, functions, classes, and top-level code —
              covering every feature of the language subset. Then transpile:
            </P>
            <CodeBlock lines={[
              'zigtsc main.ts -target js output.js      # JavaScript',
              'zigtsc main.ts -target cpp out/           # C++ multi-file',
              'zigtsc main.ts output.c                   # C single-file',
            ]} />
          </Section>

          <Section title="Command reference">
            {[
              ['zigtsc init [dir]', 'Scaffold a new project with a starter main.ts'],
              ['zigtsc <file.ts> [output]', 'Transpile to C (default target)'],
              ['zigtsc <file.ts> -target js [output]', 'Transpile to JavaScript'],
              ['zigtsc <file.ts> -target cpp [outdir]', 'Transpile to C++ (multi-file)'],
              ['zigtsc help', 'Print help message'],
            ].map(([cmd, desc]) => (
              <div mix={css({ display: 'flex', gap: '16px', padding: '4px 0', flexWrap: 'wrap' })}>
                <code mix={css({ fontSize: '13px', color: 'var(--text-primary)', minWidth: '280px', whiteSpace: 'nowrap' })}>{cmd}</code>
                <span mix={css({ fontSize: '13px', color: 'var(--text-secondary)' })}>{desc}</span>
              </div>
            ))}
          </Section>

          <Section title="Compiler pipeline">
            <CodeBlock lines={[
              'source.ts → Lexer → Tokens → Parser → AST → Checker →┬→ CodeGen    → output.c',
              '                                                      ├→ CodeGenJS  → output.js',
              '                                                      └→ CodeGenCpp → .h/.cpp files',
            ]} />
            <P>Each stage is a separate Zig source file. Parser and checker are shared across all targets.</P>
            {[
              ['token.zig', 'Token definitions — keywords (including class/new/this), operators, literals'],
              ['lexer.zig', 'Tokenizer with comment skipping, string/number/identifier support'],
              ['ast.zig', 'AST node definitions — class_decl, method_decl, constructor_decl, new_expr, this_expr'],
              ['parser.zig', 'Recursive descent parser with class/method/constructor/new/this support'],
              ['checker.zig', 'Type checker — scoped symbols, ClassDef, class_t type, this binding'],
              ['codegen.zig', 'C emitter — interface→struct, console.log→printf (legacy single-file)'],
              ['codegen_js.zig', 'JS emitter — strips types, classes→ES6 classes, interfaces omitted'],
              ['codegen_cpp.zig', 'C++ emitter — multi-file .h/.cpp per class, this→this->, dependency includes'],
              ['main.zig', 'CLI entry point with -target flag routing'],
            ].map(([file, desc]) => (
              <div mix={css({ display: 'flex', gap: '16px', padding: '4px 0', flexWrap: 'wrap' })}>
                <code mix={css({ fontSize: '13px', color: 'var(--accent)', whiteSpace: 'nowrap', minWidth: '140px' })}>{file}</code>
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
              ['interface Foo { ... }', 'typedef struct / C++ struct'],
              ['class Foo { ... }', 'C++ class with .h/.cpp pair'],
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
              'let x: number = 42;          → double x = 42;       (C)',
              'const msg: string = "hi";    → const msg = "hi";    (JS)',
            ]} />

            <H3>Functions</H3>
            <CodeBlock lines={[
              'function add(a: number, b: number): number {',
              '    return a + b;',
              '}',
              '',
              '→ C:   double add(double a, double b) { return (a + b); }',
              '→ JS:  function add(a, b) { return (a + b); }',
              '→ C++: double add(double a, double b) { return (a + b); }  (in main.cpp)',
            ]} />

            <H3>Interfaces</H3>
            <CodeBlock lines={[
              'interface Point { x: number; y: number; }',
              '',
              '→ C:   typedef struct { double x; double y; } Point;',
              '→ JS:  (omitted — compile-time only)',
              '→ C++: struct Point { double x; double y; };',
            ]} />

            <H3>Classes (Go-style, no inheritance)</H3>
            <CodeBlock lines={[
              'class Counter {',
              '    value: i32;',
              '    constructor(init: i32) { this.value = init; }',
              '    increment(): void { this.value = this.value + 1; }',
              '    getVal(): i32 { return this.value; }',
              '}',
              'const c = new Counter(10);',
              '',
              '→ JS:  class Counter { constructor(init) { ... } ... }',
              '→ C++: Counter.h + Counter.cpp (separate files)',
              '        Counter::Counter(int32_t init) { this->value = init; }',
            ]} />

            <H3>Control flow</H3>
            <P>
              <Code>if</Code> / <Code>else if</Code> / <Code>else</Code>, <Code>while</Code>,{' '}
              <Code>for</Code> (C-style 3-part), <Code>return</Code> — all map directly to their target equivalents.
            </P>

            <H3>Expressions</H3>
            <P>
              Arithmetic (<Code>+ - * / %</Code>), comparison (<Code>{'< > <= >= == != === !=='}</Code>),
              logical (<Code>{'&& || !'}</Code>), assignment (<Code>= += -= *= /=</Code>),
              function calls, member access (<Code>a.b</Code> / <Code>this.x</Code>),
              index access (<Code>a[i]</Code>), <Code>new ClassName(args)</Code>.
            </P>

            <H3>console.log</H3>
            <P>
              In C/C++ targets: transpiled to <Code>printf()</Code> with format strings inferred from types.
              In JS target: stays as <Code>console.log()</Code>.
            </P>
          </Section>

          <Section title="Explicitly excluded">
            <P>These TypeScript features are intentionally unsupported:</P>
            <ul mix={css({ margin: 0, paddingLeft: '20px', fontSize: '14px', lineHeight: 1.8, color: 'var(--text-secondary)' })}>
              <li>Inheritance / <Code>extends</Code></li>
              <li>Static fields/methods</li>
              <li>Closures / capturing nested functions</li>
              <li><Code>async</Code> / <Code>await</Code>, Promises</li>
              <li>Generics, union types, <Code>any</Code>, <Code>unknown</Code></li>
              <li>Decorators, destructuring, spread, optional chaining</li>
              <li>Getters/setters, access modifiers</li>
              <li><Code>eval</Code>, <Code>new Function()</Code></li>
            </ul>
          </Section>

          <Section title="Memory model">
            <P>
              Stack allocation by default for scalars and small structs. Arrays are heap-allocated
              with <Code>malloc</Code> — the caller is responsible for <Code>free</Code>. There is no
              garbage collector. The C/C++ targets are explicitly manual-memory.
              The JS target inherits the JS runtime's GC.
            </P>
          </Section>

          <Section title="Examples">
            <P>Four example programs are included in the <Code>examples/</Code> directory:</P>

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

            <H3>counter.ts (classes)</H3>
            <CodeBlock lines={[
              'class Counter {',
              '    value: i32;',
              '    step: i32;',
              '    constructor(init: i32, step: i32) {',
              '        this.value = init;',
              '        this.step = step;',
              '    }',
              '    increment(): void { this.value = this.value + this.step; }',
              '    getVal(): i32 { return this.value; }',
              '}',
              '',
              'const c = new Counter(0, 5);',
              'c.increment();',
              'c.increment();',
              'c.increment();',
              'console.log(c.getVal());',
            ]} />

            <H3>Try all three targets</H3>
            <CodeBlock lines={[
              '# JavaScript',
              'zigtsc examples/counter.ts -target js counter.js && node counter.js',
              '',
              '# C++ (multi-file)',
              'mkdir -p out && zigtsc examples/counter.ts -target cpp out/',
              'zigc init counter-app --cpp && cp out/*.h out/*.cpp counter-app/src/',
              'cd counter-app && zigc run',
              '',
              '# C (single-file)',
              'zigtsc examples/fib.ts fib.c',
              'zigc init fib-app && cp fib.c fib-app/src/main.c',
              'cd fib-app && zigc run',
            ]} />
          </Section>

          <Section title="Running tests">
            <CodeBlock lines={['zig build test --summary all']} />
            <P>
              The test suite includes 22 tests covering the lexer, parser, checker, C codegen,
              JS codegen, and C++ codegen. All tests pass with zero memory leaks.
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
