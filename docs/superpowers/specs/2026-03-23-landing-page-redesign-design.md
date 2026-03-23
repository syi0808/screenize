# Landing Page Redesign — Astro + GSAP Cinematic

## Summary

Redesign the Screenize landing page from vanilla HTML/CSS/JS to an Astro-based site with GSAP cinematic animations. Apple/Linear-inspired modern dark theme with high-quality interactive macOS window mockups replacing the current CSS placeholder animations.

## Decisions

- **Direction**: Full modern redesign (not incremental improvement)
- **macOS mockups**: High-quality interactive HTML/CSS mockups (not screenshots/video)
- **Animation level**: Full cinematic — ScrollTrigger pin/scrub, custom text splitting, 3D tilt, parallax, scene transitions
- **Stack**: Astro 5 + Vanilla GSAP (no React)
- **Styling**: Astro scoped CSS + CSS custom properties
- **Deploy**: GitHub Actions → gh-pages branch, source in `website/`

## Section Structure

0. **Nav** — Sticky header with logo, section links (Features, How It Works, FAQ), GitHub icon, mobile hamburger. ScrollTrigger-driven: transparent on top, blur + shadow on scroll, active section highlighting.
1. **Hero** — Fullscreen cinematic intro with SplitText character reveal, gradient orb background, CTA buttons
2. **Feature Showcase** — 3 groups with ScrollTrigger pin + scrub:
   - Smart Auto-Zoom (standalone — key differentiator)
   - Timeline + Click Effects + Keystroke Overlays (editing bundle)
   - Cursors + Backgrounds + Export (finishing bundle)
3. **How It Works** — Record → Edit → Export flow
4. **Open Source + Comparison** — Free/OSS value prop + competitor comparison table
5. **Download CTA** — Download + GitHub links
6. **FAQ** — Essential questions only
7. **Footer**

## Tech Stack

| Layer | Choice | Rationale |
|-------|--------|-----------|
| Framework | Astro 5 | Static output, zero JS by default, scoped styles |
| Animation | GSAP + ScrollTrigger | Pin, scrub, parallax, 3D transforms. Use custom text splitting (no SplitText plugin — it requires paid GSAP Club license). Split chars/words via JS, animate with gsap.to(). |
| Styling | Astro Scoped CSS | CSS custom properties for theming, no Tailwind overhead |
| Fonts | Inter Display (headings), Inter (body), JetBrains Mono (code) | Clean geometric feel, carried over monospace |
| Deploy | GitHub Actions → gh-pages | `website/` source dir, CI builds & deploys |

## Project Structure

```
website/
├── src/
│   ├── layouts/BaseLayout.astro
│   ├── pages/index.astro
│   ├── components/
│   │   ├── Nav.astro
│   │   ├── Hero.astro
│   │   ├── FeatureShowcase.astro
│   │   ├── HowItWorks.astro
│   │   ├── OpenSourceComparison.astro
│   │   ├── DownloadCTA.astro
│   │   ├── FAQ.astro
│   │   ├── Footer.astro
│   │   └── mockups/
│   │       ├── MacWindow.astro
│   │       ├── AutoZoomMockup.astro
│   │       ├── TimelineMockup.astro
│   │       ├── ClickEffectsMockup.astro
│   │       ├── KeystrokeMockup.astro
│   │       ├── CursorMockup.astro
│   │       └── ExportMockup.astro
│   ├── scripts/
│   │   ├── animations.ts
│   │   └── mockup-interactions.ts
│   └── styles/
│       └── global.css
├── public/
│   ├── images/
│   └── fonts/
├── astro.config.mjs
└── package.json
```

## Visual Design System

### Color Palette

- **Backgrounds**: `#030308`, `#08080f`, `#111119`, `#1a1a24` (deeper blacks than current)
- **Accent gradient**: `#6366f1` → `#a855f7` (indigo to purple)
- **Light accent**: `#818cf8` → `#c084fc`
- **Text primary**: `#f0f0f8`
- **Text secondary**: `#a0a0b8`
- **Text tertiary**: `#606078`
- **Borders**: `rgba(255,255,255,0.06)`

### Typography

- **Display**: Inter Display, weight 700-800, letter-spacing -0.02em
- **Body**: Inter, weight 400, line-height 1.6
- **Mono**: JetBrains Mono, weight 400-500 (technical labels, code)

## Animation System

### GSAP Loading Strategy

GSAP loaded via npm (`gsap` package). In Astro, use a `<script>` tag in BaseLayout.astro to import and register plugins globally. Each component's animation logic lives in `scripts/animations.ts` and is initialized on `DOMContentLoaded`.

```ts
// scripts/animations.ts
import gsap from 'gsap';
import { ScrollTrigger } from 'gsap/ScrollTrigger';
gsap.registerPlugin(ScrollTrigger);
```

### Text Splitting (Custom, No SplitText Plugin)

Custom utility to split text into `<span>` wrapped chars/words for animation:

```ts
function splitText(el: HTMLElement): { chars: HTMLElement[], words: HTMLElement[] } {
  // Split into words, then chars, wrap each in <span> with inline-block
}
```

### Hero Entrance
- Custom text split character-level stagger reveal
- Subtitle fade-up + blur-in
- CTA buttons scale-in with spring easing
- Background gradient orbs with smooth movement

### Scroll Animations
- ScrollTrigger pin for feature sections (viewport-locked while content animates)
- Scrub-based progression (scroll position = animation progress)
- Parallax layers (text vs mockup speed differential)
- Cross-section crossfade transitions

### Text Effects
- Scroll-driven text reveal (opacity + y-transform per line)
- Gradient text shimmer on scroll
- Counter number animations for stats
- Keyword highlight typing effect

### Interactive
- Mouse-position-based 3D tilt on mockups
- Magnetic button hover effects
- Subtle element response near cursor
- Interactive demos inside mockup windows

## macOS Window Mockups

Each feature gets a high-fidelity interactive mockup built in HTML/CSS:

- **MacWindow.astro** — Reusable wrapper: realistic title bar with traffic lights, proper border-radius, layered shadows, frosted glass toolbar effect
- **Auto-Zoom mockup** — Simulated viewport with animated zoom region following a cursor path, smooth scale transitions
- **Timeline mockup** — Multi-track timeline with colored tracks, draggable-looking keyframes, animated playhead, zoom waveform
- **Click Effects mockup** — Ripple rings expanding from click points with realistic timing
- **Keystroke mockup** — Floating key caps with press/release animation
- **Cursor mockup** — Cursor style variants with smooth transitions between styles
- **Export mockup** — Codec/resolution selectors with animated progress bar

All mockups respond to mouse hover (3D tilt) and scroll progress (internal animation state advances with scroll).

## Responsive / Mobile

- **Breakpoints**: 768px (tablet), 480px (mobile)
- **ScrollTrigger pin**: Disable on mobile (< 768px) — use simple scroll-reveal instead
- **3D tilt**: Disable on touch devices
- **Mockups**: Scale down, simplify internal animations on mobile
- **Nav**: Hamburger menu on mobile with slide-in drawer
- **`prefers-reduced-motion`**: Respect globally — disable all GSAP animations, show static layout

## SEO Preservation

Carry over from current page:
- JSON-LD structured data (SoftwareApplication, FAQPage, HowTo)
- Open Graph + Twitter Card meta tags (existing `og-image.png` transferred to `public/images/`)
- Canonical URL, sitemap.xml
- `robots.txt` — preserve verbatim (includes AI bot allow/block rules: GPTBot allowed, CCBot blocked, etc.)
- Google site verification meta tag
- Semantic HTML structure with proper heading hierarchy
- No analytics — intentionally omitted (aligns with privacy-respecting open-source positioning)

## Astro Configuration

```js
// astro.config.mjs
import { defineConfig } from 'astro/config';

export default defineConfig({
  site: 'https://syi0808.github.io',
  base: '/screenize/',
  output: 'static',
});
```

## Font Strategy

Self-host all fonts in `public/fonts/` (woff2 format):
- **Inter** (variable font) — from Google Fonts, `@font-face` with `font-display: swap`
- **JetBrains Mono** — from Google Fonts, `@font-face` with `font-display: swap`

Self-hosting avoids external requests and GDPR concerns. Variable font files keep the total small (~100KB for Inter + JetBrains Mono woff2).

## GitHub Actions Workflow

```yaml
# .github/workflows/deploy-website.yml
name: Deploy Website
on:
  push:
    branches: [master]
    paths: ['website/**']
jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: 22
      - run: npm ci
        working-directory: website
      - run: npm run build
        working-directory: website
      - uses: peaceiris/actions-gh-pages@v4
        with:
          github_token: ${{ secrets.GITHUB_TOKEN }}
          publish_dir: website/dist
```

## Migration Notes

- Current `docs/` stays as-is until new site is deployed
- New source lives in `website/`
- GitHub Actions workflow builds Astro and deploys to gh-pages branch
- Update GitHub Pages settings to serve from gh-pages branch instead of docs/
- After deployment verified, `docs/` can be removed
