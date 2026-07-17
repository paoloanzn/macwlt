# @macwlt/design-system

Shared visual foundations for the macwlt web apps. The package exposes React
components for React consumers and standalone CSS tokens for framework-neutral
consumers such as VitePress.

## React

Import the stylesheet once at the application entry point:

```tsx
import '@macwlt/design-system/styles.css'
```

Wrap the page in `AppShell`, then compose the exported components:

```tsx
import {
  AppShell,
  Button,
  Hero,
  Navbar,
} from '@macwlt/design-system'

export function Page(): React.JSX.Element {
  return (
    <AppShell>
      <Navbar />
      <Hero
        title="macwlt"
        actions={<Button href="/docs">Read the docs</Button>}
      />
    </AppShell>
  )
}
```

## CSS-only consumers

Import only the tokens when the host framework supplies its own components:

```css
@import '@macwlt/design-system/tokens.css';

:root {
  --host-accent: var(--mw-accent);
  --host-surface: var(--mw-surface);
}
```

Use `styles.css` instead when the consumer also needs the fonts, resets, and
`mw-*` component classes.

Override tokens after the package import to re-theme a consumer without
forking the component styles.
