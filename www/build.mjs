import { build } from 'esbuild'
import { mkdirSync, writeFileSync } from 'node:fs'

const OUTPUT_DIR = '.vercel/output'
const FUNC_DIR = `${OUTPUT_DIR}/functions/index.func`

// 1. Bundle the API handler
await build({
  entryPoints: ['api/index.ts'],
  bundle: true,
  platform: 'node',
  target: 'node20',
  format: 'esm',
  outfile: `${FUNC_DIR}/index.mjs`,
  external: ['*.node', 'lightningcss', 'oxc-resolver', 'remix/assets', './assets.ts'],
  loader: { '.tsx': 'tsx', '.ts': 'ts' },
  define: { 'process.env.VERCEL_BUILD': '"1"' },
})

// 2. Write the function config
mkdirSync(FUNC_DIR, { recursive: true })
writeFileSync(`${FUNC_DIR}/.vc-config.json`, JSON.stringify({
  runtime: 'nodejs20.x',
  handler: 'index.mjs',
  launcherType: 'Nodejs',
}))

// 3. Write the output config with catch-all route
mkdirSync(OUTPUT_DIR, { recursive: true })
writeFileSync(`${OUTPUT_DIR}/config.json`, JSON.stringify({
  version: 3,
  routes: [
    { src: '/(.*)', dest: '/' },
  ],
}))

console.log('Build complete → .vercel/output/')
