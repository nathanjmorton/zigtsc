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
        <script>{COPY_SCRIPT}</script>
      </head>
      <body mix={css(bodyStyles)}>
        <nav mix={css(navStyles)}>
          <a href={routes.home.href()} mix={css(navLinkStyles)}>← zigtsc</a>
          <a href="https://github.com/nathanjmorton/zigtsc" mix={css(navLinkStyles)}>GitHub</a>
        </nav>
        <main mix={css(mainStyles)}>
          <h1 mix={css({ margin: 0, fontSize: '32px', fontWeight: 700 })}>Documentation</h1>

          <Section title="Install">
            <H3>Homebrew (recommended)</H3>
            <CopyBlock command="brew install nathanjmorton/zigtsc/zigtsc" />
            <P>
              Upgrade: <Code>brew upgrade zigtsc</Code>.
            </P>

            <H3>Shell script</H3>
            <CopyBlock command="curl -fsSL https://raw.githubusercontent.com/nathanjmorton/zigtsc/main/install.sh | bash" />
            <P>
              Detects your platform (macOS/Linux, arm64/x86_64), downloads the binary to <Code>~/.zigtsc/bin/zigtsc</Code>,
              and updates your <Code>PATH</Code>.
            </P>

            <H3>Build from source</H3>
            <CopyBlock command={"git clone https://github.com/nathanjmorton/zigtsc &&\ncd zigtsc &&\nzig build -Doptimize=ReleaseFast"} />
            <P>Requires <A href="https://ziglang.org/download/">Zig 0.16.0</A>.</P>
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

          <Section title="Full pipeline: TypeScript → JavaScript">
            <P>
              Scaffold a project, transpile to JS, and run it. The scaffold includes interfaces, classes,
              functions, and top-level code. Types are stripped; classes emit as ES6 classes.
            </P>
            <CopyBlock command={"zigtsc init myapp &&\ncd myapp &&\nzigtsc main.ts -target js output.js &&\nnode output.js"} />
          </Section>

          <Section title="Full pipeline: TypeScript → C++ → native binary">
            <P>
              The scaffold's <Code>main.ts</Code> has a <Code>Counter</Code> class and a <Code>Point</Code> interface.
              The C++ target emits <Code>Counter.h</Code> + <Code>Counter.cpp</Code> (class with constructor and methods),
              <Code>main.cpp</Code> (interface struct, free functions, top-level code with <Code>main()</Code>),
              and dependency-aware <Code>#include</Code>s. Then <A href="https://zigc.nathanjmorton.com">zigc</A> compiles
              and statically links everything.
            </P>
            <CopyBlock command={"zigtsc init myapp &&\ncd myapp &&\nmkdir -p out &&\nzigtsc main.ts -target cpp out/"} />
            <P>This generates:</P>
            <CodeBlock lines={[
              'out/Counter.h      ← #pragma once, class Counter { int32_t value; ... };',
              'out/Counter.cpp    ← #include "Counter.h", Counter::Counter(), Counter::increment(), ...',
              'out/main.cpp       ← #include "Counter.h", struct Point, distance(), int main() { ... }',
            ]} />
            <P>Create a zigc C++ project, copy the generated files, build and run:</P>
            <CopyBlock command={"zigc init myapp-cpp --cpp &&\ncp out/*.h out/*.cpp myapp-cpp/src/ &&\ncd myapp-cpp &&\nzigc build &&\nzigc run"} />
            <P>
              zigc's <Code>build.zig</Code> compiles all <Code>.cpp</Code> files in <Code>src/</Code>,
              resolves the <Code>#include</Code> headers, and statically links them into one binary.
            </P>
          </Section>

          <Section title="Full pipeline: TypeScript → C → native binary">
            <P>
              Single-file C output. Interfaces become <Code>typedef struct</Code>, functions map directly,
              <Code>console.log</Code> becomes <Code>printf</Code> with format strings inferred from types.
            </P>
            <CopyBlock command={"zigtsc init myapp &&\ncd myapp &&\nzigtsc main.ts output.c"} />
            <CopyBlock command={"zigc init myapp-c &&\ncp output.c myapp-c/src/main.c &&\ncd myapp-c &&\nzigc build &&\nzigc run"} />
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

          <Section title="What zigtsc init generates">
            <P>
              <Code>zigtsc init</Code> creates a <Code>main.ts</Code> that exercises every language feature.
              The scaffold includes an interface (<Code>Point</Code>), a class (<Code>Counter</Code>) with
              constructor and methods, a free function (<Code>distance</Code>), and top-level code that
              instantiates the class with <Code>new</Code>.
            </P>
            <CodeBlock lines={[
              'interface Point { x: number; y: number; }',
              '',
              'function distance(a: Point, b: Point): number {',
              '    let dx: number = b.x - a.x;',
              '    let dy: number = b.y - a.y;',
              '    return dx * dx + dy * dy;',
              '}',
              '',
              'class Counter {',
              '    value: i32;',
              '    constructor(init: i32) { this.value = init; }',
              '    increment(): void { this.value = this.value + 1; }',
              '    decrement(): void { this.value = this.value - 1; }',
              '    getVal(): i32 { return this.value; }',
              '}',
              '',
              'const p1: Point = { x: 0, y: 0 };',
              'const p2: Point = { x: 3, y: 4 };',
              'console.log(distance(p1, p2));',
              '',
              'const c = new Counter(10);',
              'c.increment();',
              'c.increment();',
              'c.decrement();',
              'console.log(c.getVal());',
            ]} />
          </Section>

          <Section title="Running tests">
            <CopyBlock command="zig build test --summary all" />
            <P>
              22 tests covering the lexer, parser, checker, C codegen,
              JS codegen, and C++ codegen. Zero memory leaks.
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

function CopyBlock() {
  return ({ command }: { command: string }) => (
    <div
      data-copy={command}
      mix={css({
        width: '100%',
        margin: 0,
        background: 'var(--surface-3)',
        border: '1px solid var(--border)',
        borderRadius: '12px',
        padding: '12px 16px',
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
        {command}
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

// ── Styles

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
