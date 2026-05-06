import type { BuildAction } from 'remix/fetch-router'

import type { routes } from '../routes.ts'
import { DocsPage } from '../ui/docs-page.tsx'
import { render } from '../utils/render.tsx'

export const docs: BuildAction<'GET', typeof routes.docs> = {
  handler({ request }) {
    return render(<DocsPage />, request)
  },
}
