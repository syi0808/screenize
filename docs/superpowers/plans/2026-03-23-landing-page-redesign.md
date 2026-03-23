# Landing Page Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild the Screenize landing page as an Astro 5 + GSAP site with cinematic scroll animations, Apple/Linear-inspired design, and high-quality interactive macOS window mockups.

**Architecture:** Astro static site in `website/` directory. Each page section is an Astro component. GSAP + ScrollTrigger handles all animations via a centralized `animations.ts` module. Custom text splitting replaces paid SplitText plugin. Mockups are Astro components wrapping a shared `MacWindow.astro` shell. GitHub Actions deploys to gh-pages branch.

**Tech Stack:** Astro 5, GSAP 3 (ScrollTrigger), CSS Custom Properties, Inter + JetBrains Mono (self-hosted woff2), GitHub Actions

**Spec:** `docs/superpowers/specs/2026-03-23-landing-page-redesign-design.md`

---

## File Map

| File | Responsibility |
|------|---------------|
| `website/package.json` | Dependencies: astro, gsap |
| `website/astro.config.mjs` | Site URL, base path `/screenize/`, static output |
| `website/tsconfig.json` | TypeScript config for Astro |
| `website/src/layouts/BaseLayout.astro` | HTML shell, meta tags, JSON-LD, font loading, global CSS import |
| `website/src/pages/index.astro` | Page composition — imports and renders all section components |
| `website/src/styles/global.css` | CSS custom properties, reset, typography, utility classes |
| `website/src/components/Nav.astro` | Sticky nav, mobile hamburger, scroll-driven blur |
| `website/src/components/Hero.astro` | Fullscreen hero with headline, subtitle, CTAs, gradient orbs |
| `website/src/components/FeatureShowcase.astro` | 3 feature groups orchestrator with ScrollTrigger pin zones |
| `website/src/components/mockups/MacWindow.astro` | Reusable macOS window frame (traffic lights, shadows, toolbar) |
| `website/src/components/mockups/AutoZoomMockup.astro` | Animated zoom viewport following cursor path |
| `website/src/components/mockups/TimelineMockup.astro` | Multi-track timeline with playhead and keyframes |
| `website/src/components/mockups/ClickEffectsMockup.astro` | Expanding ripple rings from click points |
| `website/src/components/mockups/KeystrokeMockup.astro` | Floating key caps with press/release animation |
| `website/src/components/mockups/CursorMockup.astro` | Cursor style variants with transitions |
| `website/src/components/mockups/ExportMockup.astro` | Codec/resolution selectors with progress bar |
| `website/src/components/HowItWorks.astro` | 3-step Record → Edit → Export flow |
| `website/src/components/OpenSourceComparison.astro` | OSS value prop + comparison table vs Screen Studio |
| `website/src/components/DownloadCTA.astro` | Download + GitHub action buttons |
| `website/src/components/FAQ.astro` | Collapsible FAQ items |
| `website/src/components/Footer.astro` | Copyright, links, last updated |
| `website/src/scripts/animations.ts` | GSAP initialization, ScrollTrigger, hero entrance, scroll reveals |
| `website/src/scripts/text-split.ts` | Custom text splitting utility (chars/words → spans) |
| `website/src/scripts/mockup-interactions.ts` | 3D tilt, magnetic buttons, mockup scroll-driven state |
| `website/public/fonts/inter-variable.woff2` | Self-hosted Inter variable font |
| `website/public/fonts/jetbrains-mono-variable.woff2` | Self-hosted JetBrains Mono |
| `website/public/images/icon-256.png` | App icon (copied from docs/) |
| `website/public/images/og-image.png` | Open Graph image |
| `website/public/robots.txt` | Preserved verbatim from docs/robots.txt |
| `website/public/sitemap.xml` | Updated sitemap |
| `.github/workflows/deploy-website.yml` | CI: build Astro, deploy to gh-pages |

---

## Task 1: Astro Project Scaffolding

**Files:**
- Create: `website/package.json`
- Create: `website/astro.config.mjs`
- Create: `website/tsconfig.json`
- Create: `website/.gitignore`

**Context:** Initialize the Astro project manually (no `create-astro` wizard). The project deploys to `https://syi0808.github.io/screenize/` so `base: '/screenize/'` is required.

- [ ] **Step 1: Create `website/package.json`**

```json
{
  "name": "screenize-website",
  "type": "module",
  "version": "0.0.1",
  "scripts": {
    "dev": "astro dev",
    "build": "astro build",
    "preview": "astro preview"
  },
  "dependencies": {
    "astro": "^5.0.0",
    "gsap": "^3.12.0"
  }
}
```

- [ ] **Step 2: Create `website/astro.config.mjs`**

```js
import { defineConfig } from 'astro/config';

export default defineConfig({
  site: 'https://syi0808.github.io',
  base: '/screenize/',
  output: 'static',
});
```

- [ ] **Step 3: Create `website/tsconfig.json`**

```json
{
  "extends": "astro/tsconfigs/strict"
}
```

- [ ] **Step 4: Create `website/.gitignore`**

```
node_modules/
dist/
.astro/
```

- [ ] **Step 5: Install dependencies**

Run: `cd website && npm install`
Expected: `node_modules/` created, `package-lock.json` generated.

- [ ] **Step 6: Verify Astro runs**

Run: `cd website && npx astro check 2>&1 | head -5`
Expected: No fatal errors. (Will warn about missing pages, that's fine.)

- [ ] **Step 7: Commit**

```bash
git add website/package.json website/package-lock.json website/astro.config.mjs website/tsconfig.json website/.gitignore
git commit -m "feat(website): scaffold Astro 5 project with GSAP dependency"
```

---

## Task 2: Global Styles + Font Setup

**Files:**
- Create: `website/src/styles/global.css`
- Create: `website/public/fonts/` (font files)

**Context:** The design system uses deeper blacks than the current site, indigo-to-purple gradients, and Inter + JetBrains Mono fonts. Self-host fonts as woff2 for performance and GDPR compliance.

- [ ] **Step 1: Download font files**

Download font files and place in `website/public/fonts/`:

**Inter variable font** (single woff2, ~300KB, covers all weights 100-900):
- Go to https://github.com/rsms/inter/releases/latest
- Download the zip, extract `Inter-roman.woff2` (or `InterVariable.woff2` depending on version)
- Save as `website/public/fonts/inter-variable.woff2`

**JetBrains Mono variable font**:
- Go to https://github.com/JetBrains/JetBrainsMono/releases/latest
- Download the zip, extract `fonts/variable/JetBrainsMono[wght].woff2`
- Save as `website/public/fonts/jetbrains-mono-variable.woff2`

Note: Inter variable font at weight 700-800 is visually identical to Inter Display at typical heading sizes. No need for a separate Inter Display font file — just use the variable font at high weights.

- [ ] **Step 2: Create `website/src/styles/global.css`**

```css
/* === Font Faces === */
@font-face {
  font-family: 'Inter';
  src: url('/screenize/fonts/inter-variable.woff2') format('woff2');
  font-weight: 100 900;
  font-display: swap;
  font-style: normal;
}

@font-face {
  font-family: 'JetBrains Mono';
  src: url('/screenize/fonts/jetbrains-mono-variable.woff2') format('woff2');
  font-weight: 100 800;
  font-display: swap;
  font-style: normal;
}

/* === CSS Custom Properties === */
:root {
  /* Backgrounds */
  --bg-0: #030308;
  --bg-1: #08080f;
  --bg-2: #111119;
  --bg-3: #1a1a24;

  /* Accent */
  --accent-start: #6366f1;
  --accent-end: #a855f7;
  --accent-light-start: #818cf8;
  --accent-light-end: #c084fc;

  /* Text */
  --text-0: #f0f0f8;
  --text-1: #a0a0b8;
  --text-2: #606078;

  /* Borders */
  --border: rgba(255, 255, 255, 0.06);
  --border-accent: rgba(99, 102, 241, 0.25);

  /* Radius */
  --radius-sm: 6px;
  --radius-md: 12px;
  --radius-lg: 20px;

  /* Easing */
  --ease-out: cubic-bezier(0.16, 1, 0.3, 1);
  --ease-spring: cubic-bezier(0.34, 1.56, 0.64, 1);

  /* Layout */
  --container-max: 1180px;
  --container-padding: 24px;
}

/* === Reset === */
*, *::before, *::after {
  box-sizing: border-box;
  margin: 0;
  padding: 0;
}

html {
  scroll-behavior: smooth;
  -webkit-font-smoothing: antialiased;
  -moz-osx-font-smoothing: grayscale;
}

body {
  font-family: 'Inter', system-ui, -apple-system, sans-serif;
  font-size: 16px;
  line-height: 1.6;
  color: var(--text-0);
  background-color: var(--bg-0);
}

/* === Typography === */
h1, h2, h3, h4, h5, h6 {
  font-weight: 700;
  letter-spacing: -0.02em;
  line-height: 1.1;
}

h1 { font-size: clamp(2.5rem, 6vw, 4.5rem); font-weight: 800; }
h2 { font-size: clamp(2rem, 4vw, 3rem); }
h3 { font-size: clamp(1.25rem, 2.5vw, 1.75rem); }

a {
  color: inherit;
  text-decoration: none;
}

code, .mono {
  font-family: 'JetBrains Mono', monospace;
}

/* === Utility === */
.container {
  max-width: var(--container-max);
  margin: 0 auto;
  padding: 0 var(--container-padding);
}

.gradient-text {
  background: linear-gradient(135deg, var(--accent-start), var(--accent-end));
  -webkit-background-clip: text;
  -webkit-text-fill-color: transparent;
  background-clip: text;
}

.sr-only {
  position: absolute;
  width: 1px;
  height: 1px;
  padding: 0;
  margin: -1px;
  overflow: hidden;
  clip: rect(0, 0, 0, 0);
  border: 0;
}

/* === Section Spacing === */
section {
  padding: 120px 0;
}

@media (max-width: 768px) {
  section {
    padding: 80px 0;
  }
}

/* === Reduced Motion === */
@media (prefers-reduced-motion: reduce) {
  *, *::before, *::after {
    animation-duration: 0.01ms !important;
    animation-iteration-count: 1 !important;
    transition-duration: 0.01ms !important;
  }
}
```

- [ ] **Step 3: Verify CSS has no syntax errors**

Run: `cd website && npx astro build 2>&1 | tail -5`
(Will fail because no pages exist yet — that's fine. Check for CSS parse errors.)

- [ ] **Step 4: Commit**

```bash
git add website/src/styles/global.css website/public/fonts/
git commit -m "feat(website): add design system tokens and self-hosted fonts"
```

---

## Task 3: Base Layout + SEO Meta

**Files:**
- Create: `website/src/layouts/BaseLayout.astro`
- Create: `website/src/pages/index.astro` (minimal shell)
- Copy: `website/public/robots.txt` (from `docs/robots.txt`)
- Create: `website/public/sitemap.xml`
- Copy: `website/public/images/icon-256.png` (from `docs/images/icon-256.png`)

**Context:** BaseLayout contains the `<html>` shell with all meta tags, JSON-LD structured data, and global imports. Port all SEO elements from the current `docs/index.html`. The current site has 3 JSON-LD blocks: SoftwareApplication, FAQPage, HowTo.

Refer to `docs/index.html` lines 1-95 for all meta tags and JSON-LD data to carry over.

- [ ] **Step 1: Copy static assets from docs/**

```bash
cp docs/robots.txt website/public/robots.txt
cp docs/images/icon-256.png website/public/images/icon-256.png
```

**OG Image:** `docs/images/og-image.png` does not currently exist in the repo. Create a simple OG image (1200x630px) for social sharing — can be a dark background with the Screenize logo and tagline. Use the app icon + gradient background. Save to `website/public/images/og-image.png`. Alternatively, temporarily use the icon-256.png and add proper OG image creation as a follow-up task.

- [ ] **Step 2: Create `website/public/sitemap.xml`**

Port from `docs/sitemap.xml` — same content, ensure canonical URL is correct.

- [ ] **Step 3: Create `website/src/layouts/BaseLayout.astro`**

Must include:
- `<!DOCTYPE html>` with `lang="en"`
- All `<meta>` tags from current `docs/index.html` (charset, viewport, description, keywords, author, google-site-verification, Open Graph, Twitter Card)
- Canonical link to `https://syi0808.github.io/screenize/`
- Favicon referencing the icon-256.png
- JSON-LD `<script type="application/ld+json">` blocks for SoftwareApplication, FAQPage, and HowTo schemas — copy content from `docs/index.html` lines 12-90
- `<link>` to `global.css`
- `<slot />` for page content

```astro
---
interface Props {
  title: string;
  description: string;
}

const { title, description } = Astro.props;
---

<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>{title}</title>
  <meta name="description" content={description} />
  <!-- Port all remaining meta tags from docs/index.html -->
  <link rel="icon" type="image/png" href="/screenize/images/icon-256.png" />
  <link rel="canonical" href="https://syi0808.github.io/screenize/" />
  <!-- JSON-LD blocks here -->
</head>
<body>
  <slot />
</body>
</html>
```

- [ ] **Step 4: Create minimal `website/src/pages/index.astro`**

```astro
---
import BaseLayout from '../layouts/BaseLayout.astro';
---

<BaseLayout
  title="Screenize — Free Screen Studio Alternative for macOS"
  description="Record your screen, let auto-zoom do the rest. Free, open-source macOS app with smart zoom, click effects, keystroke overlays, and a timeline editor you actually control."
>
  <main>
    <p style="color: white; padding: 40px;">Landing page coming soon.</p>
  </main>
</BaseLayout>
```

- [ ] **Step 5: Verify build succeeds**

Run: `cd website && npx astro build`
Expected: Build completes, `dist/` directory created with `index.html`.

- [ ] **Step 6: Verify SEO meta tags present in output**

Run: `grep -c 'og:title\|application/ld+json\|canonical' website/dist/index.html`
Expected: At least 3 matches (og:title, JSON-LD, canonical).

- [ ] **Step 7: Commit**

```bash
git add website/src/layouts/ website/src/pages/ website/public/
git commit -m "feat(website): add base layout with SEO meta tags and JSON-LD"
```

---

## Task 4: GSAP Animation Infrastructure

**Files:**
- Create: `website/src/scripts/text-split.ts`
- Create: `website/src/scripts/animations.ts`
- Create: `website/src/scripts/mockup-interactions.ts`

**Context:** Set up the animation system before building components. GSAP is loaded via npm. Custom text splitting replaces the paid SplitText plugin. All animation initialization happens on DOMContentLoaded.

- [ ] **Step 1: Create `website/src/scripts/text-split.ts`**

```ts
/**
 * Custom text splitting utility.
 * Wraps each word and character in <span> elements for GSAP animation.
 */

interface SplitResult {
  chars: HTMLElement[];
  words: HTMLElement[];
}

export function splitText(el: HTMLElement): SplitResult {
  const text = el.textContent || '';
  el.textContent = '';
  el.setAttribute('aria-label', text);

  const words: HTMLElement[] = [];
  const chars: HTMLElement[] = [];

  text.split(/(\s+)/).forEach((segment) => {
    if (/^\s+$/.test(segment)) {
      el.appendChild(document.createTextNode(segment));
      return;
    }

    const wordSpan = document.createElement('span');
    wordSpan.style.display = 'inline-block';
    wordSpan.classList.add('split-word');
    wordSpan.setAttribute('aria-hidden', 'true');

    for (const char of segment) {
      const charSpan = document.createElement('span');
      charSpan.style.display = 'inline-block';
      charSpan.classList.add('split-char');
      charSpan.textContent = char;
      wordSpan.appendChild(charSpan);
      chars.push(charSpan);
    }

    el.appendChild(wordSpan);
    words.push(wordSpan);
  });

  return { chars, words };
}
```

- [ ] **Step 2: Create `website/src/scripts/animations.ts`**

```ts
import gsap from 'gsap';
import { ScrollTrigger } from 'gsap/ScrollTrigger';
import { splitText } from './text-split';

gsap.registerPlugin(ScrollTrigger);

// Respect reduced motion preference
const prefersReducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
const isMobile = window.innerWidth < 768;

/**
 * Hero entrance animation — character stagger reveal, subtitle blur-in, CTA scale-in
 */
function initHeroAnimation() {
  if (prefersReducedMotion) return;

  const title = document.querySelector<HTMLElement>('[data-animate="hero-title"]');
  if (title) {
    const { chars } = splitText(title);
    gsap.from(chars, {
      opacity: 0,
      y: 40,
      rotateX: -90,
      stagger: 0.02,
      duration: 0.8,
      ease: 'power4.out',
      delay: 0.2,
    });
  }

  gsap.from('[data-animate="hero-subtitle"]', {
    opacity: 0,
    y: 30,
    filter: 'blur(10px)',
    duration: 1,
    ease: 'power3.out',
    delay: 0.6,
  });

  gsap.from('[data-animate="hero-cta"]', {
    opacity: 0,
    scale: 0.8,
    y: 20,
    stagger: 0.1,
    duration: 0.6,
    ease: 'back.out(1.7)',
    delay: 0.9,
  });

  // Gradient orbs gentle floating
  gsap.to('[data-animate="orb"]', {
    x: 'random(-30, 30)',
    y: 'random(-30, 30)',
    duration: 'random(4, 8)',
    repeat: -1,
    yoyo: true,
    ease: 'sine.inOut',
    stagger: { each: 1, from: 'random' },
  });
}

/**
 * Scroll-driven section reveals — fade up + opacity
 */
function initScrollReveals() {
  if (prefersReducedMotion) return;

  const elements = document.querySelectorAll('[data-animate="reveal"]');
  elements.forEach((el) => {
    gsap.from(el, {
      scrollTrigger: {
        trigger: el,
        start: 'top 85%',
        toggleActions: 'play none none none',
      },
      opacity: 0,
      y: 60,
      duration: 0.8,
      ease: 'power3.out',
    });
  });
}

/**
 * Feature showcase — pinned scroll sections with scrub
 * Only on desktop; mobile uses simple reveals.
 */
function initFeaturePins() {
  if (prefersReducedMotion || isMobile) return;

  const featureGroups = document.querySelectorAll<HTMLElement>('[data-feature-group]');
  featureGroups.forEach((group) => {
    const content = group.querySelector('[data-feature-content]');
    const mockup = group.querySelector('[data-feature-mockup]');
    if (!content || !mockup) return;

    const tl = gsap.timeline({
      scrollTrigger: {
        trigger: group,
        start: 'top top',
        end: '+=150%',
        pin: true,
        scrub: 1,
      },
    });

    tl.from(content, { opacity: 0, x: -60, duration: 0.5 })
      .from(mockup, { opacity: 0, x: 60, scale: 0.95, duration: 0.5 }, '<0.1');
  });
}

/**
 * Nav background transition on scroll
 */
function initNavScroll() {
  const nav = document.querySelector<HTMLElement>('[data-animate="nav"]');
  if (!nav) return;

  ScrollTrigger.create({
    start: 'top -80',
    onUpdate: (self) => {
      nav.classList.toggle('scrolled', self.progress > 0);
    },
  });
}

/**
 * Text reveal on scroll — line by line
 */
function initTextReveals() {
  if (prefersReducedMotion) return;

  const elements = document.querySelectorAll<HTMLElement>('[data-animate="text-reveal"]');
  elements.forEach((el) => {
    const { words } = splitText(el);
    gsap.from(words, {
      scrollTrigger: {
        trigger: el,
        start: 'top 85%',
      },
      opacity: 0,
      y: 20,
      stagger: 0.05,
      duration: 0.6,
      ease: 'power3.out',
    });
  });
}

/**
 * Initialize all animations
 */
export function initAnimations() {
  initNavScroll();
  initHeroAnimation();
  initScrollReveals();
  initFeaturePins();
  initTextReveals();
}

// Auto-initialize on DOM ready
if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', initAnimations);
} else {
  initAnimations();
}
```

- [ ] **Step 3: Create `website/src/scripts/mockup-interactions.ts`**

```ts
import gsap from 'gsap';

const prefersReducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
const isTouch = 'ontouchstart' in window;

/**
 * 3D tilt effect on mockup windows following mouse position
 */
function initTilt() {
  if (prefersReducedMotion || isTouch) return;

  const mockups = document.querySelectorAll<HTMLElement>('[data-tilt]');
  mockups.forEach((el) => {
    el.addEventListener('mousemove', (e) => {
      const rect = el.getBoundingClientRect();
      const x = (e.clientX - rect.left) / rect.width - 0.5;
      const y = (e.clientY - rect.top) / rect.height - 0.5;

      gsap.to(el, {
        rotateY: x * 8,
        rotateX: -y * 8,
        transformPerspective: 1000,
        duration: 0.4,
        ease: 'power2.out',
      });
    });

    el.addEventListener('mouseleave', () => {
      gsap.to(el, {
        rotateY: 0,
        rotateX: 0,
        duration: 0.6,
        ease: 'power2.out',
      });
    });
  });
}

/**
 * Magnetic button effect — button follows cursor slightly on hover
 */
function initMagneticButtons() {
  if (prefersReducedMotion || isTouch) return;

  const buttons = document.querySelectorAll<HTMLElement>('[data-magnetic]');
  buttons.forEach((btn) => {
    btn.addEventListener('mousemove', (e) => {
      const rect = btn.getBoundingClientRect();
      const x = e.clientX - rect.left - rect.width / 2;
      const y = e.clientY - rect.top - rect.height / 2;

      gsap.to(btn, {
        x: x * 0.2,
        y: y * 0.2,
        duration: 0.3,
        ease: 'power2.out',
      });
    });

    btn.addEventListener('mouseleave', () => {
      gsap.to(btn, { x: 0, y: 0, duration: 0.4, ease: 'elastic.out(1, 0.3)' });
    });
  });
}

export function initInteractions() {
  initTilt();
  initMagneticButtons();
}

if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', initInteractions);
} else {
  initInteractions();
}
```

- [ ] **Step 4: Verify TypeScript compiles**

Run: `cd website && npx astro check`
Expected: No type errors in the scripts.

- [ ] **Step 5: Commit**

```bash
git add website/src/scripts/
git commit -m "feat(website): add GSAP animation system with text splitting and interactions"
```

---

## Task 5: Nav + Hero Components

**Files:**
- Create: `website/src/components/Nav.astro`
- Create: `website/src/components/Hero.astro`
- Modify: `website/src/pages/index.astro`

**Context:** Nav is a sticky header that transitions from transparent to blurred on scroll. Hero is a fullscreen intro with the main headline, subtitle, CTAs, and animated gradient orbs. Copy/adapt text content from `docs/index.html`.

- [ ] **Step 1: Create `website/src/components/Nav.astro`**

Sticky header with:
- Logo (icon-256.png + "Screenize" text)
- Links: Features, How It Works, FAQ
- GitHub SVG icon link
- Mobile hamburger menu button
- `data-animate="nav"` for scroll-triggered blur

Inline `<script>` for hamburger toggle (lightweight, no GSAP needed).

Scoped `<style>` for:
- `position: fixed; top: 0; z-index: 100; width: 100%; transition: background, backdrop-filter`
- `.scrolled` class: `background: rgba(3,3,8,0.8); backdrop-filter: blur(20px); border-bottom: 1px solid var(--border)`
- Mobile: hamburger visible at 768px, drawer slides in from right

Reference current nav structure in `docs/index.html` lines 97-125 for content.

- [ ] **Step 2: Create `website/src/components/Hero.astro`**

Fullscreen section with:
- `h1` with `data-animate="hero-title"`: headline text from current site ("Record your screen. Let auto-zoom do the rest.")
- `p` with `data-animate="hero-subtitle"`: subtitle description
- Two CTA buttons with `data-animate="hero-cta"` and `data-magnetic`: Download DMG + View on GitHub
- System requirements note
- Two gradient orb `<div>`s with `data-animate="orb"` — positioned absolutely, large blurred circles
- Background: subtle grid pattern or noise texture

Scoped `<style>` for:
- `min-height: 100vh; display: flex; align-items: center; justify-content: center; text-align: center`
- Gradient orbs: `position: absolute; width: 500-600px; aspect-ratio: 1; border-radius: 50%; filter: blur(120px); opacity: 0.3`
- CTA buttons: pill-shaped, primary (gradient fill) + secondary (border only)

Reference `docs/index.html` lines 127-162 for content.

- [ ] **Step 3: Update `website/src/pages/index.astro`**

```astro
---
import BaseLayout from '../layouts/BaseLayout.astro';
import Nav from '../components/Nav.astro';
import Hero from '../components/Hero.astro';
---

<BaseLayout
  title="Screenize — Free Screen Studio Alternative for macOS"
  description="Record your screen, let auto-zoom do the rest. Free, open-source macOS app with smart zoom, click effects, keystroke overlays, and a timeline editor you actually control."
>
  <Nav />
  <Hero />
</BaseLayout>
```

Add the GSAP script imports to `BaseLayout.astro` (before `</body>`), since animations are global:
```html
<script>
  import '../scripts/animations';
  import '../scripts/mockup-interactions';
</script>
```

- [ ] **Step 4: Build and verify**

Run: `cd website && npx astro build && npx astro preview`
Expected: Page loads with nav and hero visible. Open in browser to visually verify.

- [ ] **Step 5: Commit**

```bash
git add website/src/components/Nav.astro website/src/components/Hero.astro website/src/pages/index.astro website/src/layouts/BaseLayout.astro
git commit -m "feat(website): add nav and hero components with cinematic animations"
```

---

## Task 6: MacWindow Wrapper + Auto-Zoom Mockup

**Files:**
- Create: `website/src/components/mockups/MacWindow.astro`
- Create: `website/src/components/mockups/AutoZoomMockup.astro`

**Context:** MacWindow is a reusable wrapper for all feature mockups. It renders a realistic macOS window frame with traffic light dots, layered shadows, and frosted toolbar. The Auto-Zoom mockup is the first and most important feature demo — it shows a viewport where a zoom region follows a cursor path.

- [ ] **Step 1: Create `website/src/components/mockups/MacWindow.astro`**

Props: `title?: string`

Structure:
- Outer div with `data-tilt` attribute (for 3D tilt interaction)
- Title bar with 3 traffic light dots (red `#ff5f57`, yellow `#febc2e`, green `#28c840`)
- Optional title text in toolbar
- `<slot />` for mockup body content

Scoped style:
- `border-radius: 12px; overflow: hidden; background: var(--bg-1)`
- Multi-layer box-shadow: `0 24px 80px rgba(0,0,0,0.5), 0 4px 16px rgba(0,0,0,0.3)`
- Title bar: `height: 40px; background: var(--bg-2); display: flex; align-items: center; padding: 0 16px; gap: 8px`
- Traffic light dots: `width: 12px; height: 12px; border-radius: 50%`
- Border: `1px solid var(--border)`

- [ ] **Step 2: Create `website/src/components/mockups/AutoZoomMockup.astro`**

Wraps `MacWindow.astro`. Internal content:
- A "viewport" div representing a screen area (dark bg, relative positioned)
- A "zoom region" div (lighter bg, scaled, positioned absolutely) — this moves to simulate auto-zoom following a cursor
- A small cursor indicator (CSS triangle or SVG)
- Grid lines or UI element placeholders to make the viewport look like a real screen

Animation will be driven by CSS keyframes (looping demo) or GSAP ScrollTrigger (scroll-driven). Use CSS `@keyframes` for the standalone loop animation, with a `data-` attribute so GSAP can optionally override.

- [ ] **Step 3: Verify components render**

Temporarily add to index.astro to test:
```astro
<MacWindow title="Smart Auto-Zoom">
  <AutoZoomMockup />
</MacWindow>
```

Run: `cd website && npx astro build`
Expected: Builds without errors.

- [ ] **Step 4: Commit**

```bash
git add website/src/components/mockups/
git commit -m "feat(website): add MacWindow wrapper and Auto-Zoom mockup component"
```

---

## Task 7: Remaining Mockup Components

**Files:**
- Create: `website/src/components/mockups/TimelineMockup.astro`
- Create: `website/src/components/mockups/ClickEffectsMockup.astro`
- Create: `website/src/components/mockups/KeystrokeMockup.astro`
- Create: `website/src/components/mockups/CursorMockup.astro`
- Create: `website/src/components/mockups/ExportMockup.astro`

**Context:** Each mockup demonstrates a Screenize feature inside a MacWindow frame. All use CSS animations for their internal demos. Reference the current placeholder animations in `docs/css/style.css` for inspiration, but make them significantly higher quality.

- [ ] **Step 1: Create `TimelineMockup.astro`**

Multi-track timeline with:
- Time ruler at top with tick marks
- 4 color-coded tracks (Camera: blue, Click Effects: pink, Cursor: green, Keystrokes: orange)
- Diamond-shaped keyframe markers on each track
- Animated playhead (vertical line sweeping left to right)
- Waveform-style visualization in one track

Use CSS keyframes for playhead sweep animation (8s loop).

- [ ] **Step 2: Create `ClickEffectsMockup.astro`**

Click ripple demonstration:
- Dark viewport area
- 2-3 click points with expanding concentric rings
- Rings animate outward with opacity fade
- Color-coded by click type (left click: accent gradient, right click: different color)
- Staggered timing between click points

- [ ] **Step 3: Create `KeystrokeMockup.astro`**

Floating keyboard key caps:
- 3-4 key caps (e.g., ⌘, ⇧, Z, S) styled as physical keys with 3D bevels
- Keys animate with press/release (translateY + scale + shadow change)
- Staggered timing for a typing sequence feel
- Subtle glow under active keys

- [ ] **Step 4: Create `CursorMockup.astro`**

Cursor style variants:
- Show 3-4 different cursor styles (default arrow, crosshair, pointer, custom)
- Smooth transition between styles (opacity crossfade)
- Background gradient swatches below showing customization options
- Cursor moves along a predefined path

- [ ] **Step 5: Create `ExportMockup.astro`**

Export settings panel:
- Codec selector buttons (MP4, MOV, ProRes) — one highlighted as selected
- Resolution selector (1080p, 4K)
- Quality slider visualization
- Animated progress bar (gradient fill, 0% → 100% loop over 6s)
- File size estimate text

- [ ] **Step 6: Build and verify all mockups compile**

Run: `cd website && npx astro build`
Expected: Clean build with no errors.

- [ ] **Step 7: Commit**

```bash
git add website/src/components/mockups/
git commit -m "feat(website): add timeline, click effects, keystroke, cursor, and export mockups"
```

---

## Task 8: Feature Showcase Section

**Files:**
- Create: `website/src/components/FeatureShowcase.astro`
- Modify: `website/src/pages/index.astro`

**Context:** The feature showcase is divided into 3 groups. Each group has text content on one side and a mockup on the other. On desktop, ScrollTrigger pins each group while content animates in. The `data-feature-group`, `data-feature-content`, and `data-feature-mockup` attributes connect to the animation system in `animations.ts`.

Reference `docs/index.html` lines 189-394 for all feature text content (titles, descriptions, bullet points).

- [ ] **Step 1: Create `FeatureShowcase.astro`**

Three feature groups:

**Group 1: Smart Auto-Zoom** (standalone)
- Title: "Smart Auto-Zoom"
- Description: emphasize continuous camera + segment-based approach
- Bullet points from current site
- Mockup: `<AutoZoomMockup />` inside `<MacWindow>`

**Group 2: Editing Bundle** (Timeline + Click Effects + Keystroke)
- Show as a single pinned section with 3 sub-features
- Each sub-feature has a label + short description
- Mockup alternates or stacks: `TimelineMockup`, `ClickEffectsMockup`, `KeystrokeMockup`
- Consider a tabbed or scroll-driven transition between the 3 mockups within the pinned zone

**Group 3: Finishing Bundle** (Cursors + Backgrounds + Export)
- Same pattern as Group 2
- Mockups: `CursorMockup`, `ExportMockup`

Each group wrapper has `data-feature-group` attribute. Text container has `data-feature-content`. Mockup container has `data-feature-mockup`.

Layout: on desktop, two-column (text left, mockup right, or alternating). On mobile, single column stacked.

- [ ] **Step 2: Add to `index.astro`**

```astro
import FeatureShowcase from '../components/FeatureShowcase.astro';
// ... after Hero
<FeatureShowcase />
```

- [ ] **Step 3: Build and verify**

Run: `cd website && npx astro build`
Expected: Clean build.

- [ ] **Step 4: Commit**

```bash
git add website/src/components/FeatureShowcase.astro website/src/pages/index.astro
git commit -m "feat(website): add feature showcase with 3 grouped sections and mockups"
```

---

## Task 9: How It Works + Open Source Comparison

**Files:**
- Create: `website/src/components/HowItWorks.astro`
- Create: `website/src/components/OpenSourceComparison.astro`
- Modify: `website/src/pages/index.astro`

**Context:** How It Works is a 3-step flow (Record → Edit → Export). Open Source Comparison combines the OSS value proposition with the competitor comparison table. Port content from `docs/index.html`.

- [ ] **Step 1: Create `HowItWorks.astro`**

3-step horizontal flow:
- Step 1: Record (icon + title + short description)
- Step 2: Edit (icon + title + short description)
- Step 3: Export (icon + title + short description)
- Connector lines or arrows between steps
- Each step card has `data-animate="reveal"` for scroll entrance

Reference `docs/index.html` lines 396-437 for step content.

Scoped style: flex layout, step cards with number indicators, gradient connectors.

- [ ] **Step 2: Create `OpenSourceComparison.astro`**

Two parts:
1. **OSS value prop** header — title emphasizing free/open-source, Apache 2.0 license
2. **Comparison table** — Screenize vs Screen Studio

Port the comparison data from `docs/index.html` lines 439-510. The table has 10 rows:
- Price, Open source, Auto-zoom, Timeline editor, Click effects, Keystroke overlays, Custom cursors, Export formats, Max resolution, Camera overlay

Style the table with:
- Dark card background
- Alternating row opacity
- Screenize column highlighted with accent border
- Check/cross icons for boolean features
- `data-animate="reveal"` on the container

- [ ] **Step 3: Add to `index.astro`**

```astro
import HowItWorks from '../components/HowItWorks.astro';
import OpenSourceComparison from '../components/OpenSourceComparison.astro';
// ... after FeatureShowcase
<HowItWorks />
<OpenSourceComparison />
```

- [ ] **Step 4: Build and verify**

Run: `cd website && npx astro build`

- [ ] **Step 5: Commit**

```bash
git add website/src/components/HowItWorks.astro website/src/components/OpenSourceComparison.astro website/src/pages/index.astro
git commit -m "feat(website): add How It Works and Open Source Comparison sections"
```

---

## Task 10: Download CTA + FAQ + Footer

**Files:**
- Create: `website/src/components/DownloadCTA.astro`
- Create: `website/src/components/FAQ.astro`
- Create: `website/src/components/Footer.astro`
- Modify: `website/src/pages/index.astro`

**Context:** These are the final 3 sections. Download CTA is a prominent call-to-action above the FAQ. FAQ uses collapsible `<details>` elements. Footer has copyright and links.

- [ ] **Step 1: Create `DownloadCTA.astro`**

Large centered card with:
- Gradient border or glow effect
- Title: "Ready to record?"
- Two large CTA buttons: Download DMG (primary) + View on GitHub (secondary)
- Both buttons with `data-magnetic` attribute
- System requirements note below
- `data-animate="reveal"` on the section

- [ ] **Step 2: Create `FAQ.astro`**

Collapsible Q&A section:
- Section title: "Frequently Asked Questions"
- 6 FAQ items using `<details>` / `<summary>` (progressive enhancement)
- Animated open/close with CSS transition on max-height or grid-rows
- Plus/minus icon toggle on summary

Port FAQ content from `docs/index.html` lines 512-583.

- [ ] **Step 3: Create `Footer.astro`**

Minimal footer:
- Left: Copyright + Apache 2.0 license note
- Right: Links to GitHub, Releases, Issues
- Bottom: "Last updated" date
- App icon (small)

Port from `docs/index.html` lines 600-630.

- [ ] **Step 4: Complete `index.astro` with all sections**

```astro
---
import BaseLayout from '../layouts/BaseLayout.astro';
import Nav from '../components/Nav.astro';
import Hero from '../components/Hero.astro';
import FeatureShowcase from '../components/FeatureShowcase.astro';
import HowItWorks from '../components/HowItWorks.astro';
import OpenSourceComparison from '../components/OpenSourceComparison.astro';
import DownloadCTA from '../components/DownloadCTA.astro';
import FAQ from '../components/FAQ.astro';
import Footer from '../components/Footer.astro';
---

<BaseLayout
  title="Screenize — Free Screen Studio Alternative for macOS"
  description="Record your screen, let auto-zoom do the rest. Free, open-source macOS app with smart zoom, click effects, keystroke overlays, and a timeline editor you actually control."
>
  <Nav />
  <Hero />
  <FeatureShowcase />
  <HowItWorks />
  <OpenSourceComparison />
  <DownloadCTA />
  <FAQ />
  <Footer />
</BaseLayout>
```

- [ ] **Step 5: Full build and verify**

Run: `cd website && npx astro build`
Expected: Clean build with all sections.

- [ ] **Step 6: Commit**

```bash
git add website/src/components/DownloadCTA.astro website/src/components/FAQ.astro website/src/components/Footer.astro website/src/pages/index.astro
git commit -m "feat(website): add download CTA, FAQ, and footer sections"
```

---

## Task 11: Responsive + Mobile Adaptations

**Files:**
- Modify: `website/src/styles/global.css`
- Modify: `website/src/components/Nav.astro` (hamburger behavior)
- Modify: `website/src/scripts/animations.ts` (mobile-aware logic already present, verify)
- Modify: Various component `<style>` blocks

**Context:** Spec requires: pin disabled on mobile, 3D tilt disabled on touch, mockups scaled down, hamburger nav. The animation scripts already check `isMobile` and `isTouch` — this task focuses on CSS responsiveness.

- [ ] **Step 1: Review all component styles for mobile breakpoints**

Each component should have `@media (max-width: 768px)` rules for:
- Feature groups: single column layout
- Mockups: `max-width: 100%; height: auto` (prevent overflow)
- How It Works: vertical stack instead of horizontal
- Comparison table: horizontal scroll wrapper if needed
- Typography: `clamp()` already handles font scaling

- [ ] **Step 2: Verify Nav hamburger works on mobile**

The Nav component's hamburger toggle should:
- Show hamburger icon at `max-width: 768px`
- Slide-in drawer from right with backdrop
- Prevent body scroll when drawer open
- Close on link click

- [ ] **Step 3: Add mobile-specific mockup simplifications**

For smaller screens, simplify mockup internal animations:
- Reduce number of animated elements
- Simplify or disable complex CSS animations
- Ensure mockups are readable at narrow widths

- [ ] **Step 4: Test at multiple viewports**

Run: `cd website && npx astro preview`
Manually test at: 1440px, 1024px, 768px, 480px, 375px.
Check: no horizontal overflow, readable text, working nav, mockups visible.

- [ ] **Step 5: Commit**

```bash
git add -u website/
git commit -m "feat(website): add responsive layout and mobile adaptations"
```

---

## Task 12: GitHub Actions Workflow

**Files:**
- Create: `.github/workflows/deploy-website.yml`

**Context:** No workflows exist yet. The main branch is `master` (not `main` as in the spec). The workflow builds the Astro site and deploys to gh-pages branch using `peaceiris/actions-gh-pages`.

- [ ] **Step 1: Create `.github/workflows/deploy-website.yml`**

```yaml
name: Deploy Website

on:
  push:
    branches: [master]
    paths: ['website/**']

permissions:
  contents: write

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-node@v4
        with:
          node-version: 22
          cache: 'npm'
          cache-dependency-path: website/package-lock.json

      - run: npm ci
        working-directory: website

      - run: npm run build
        working-directory: website

      - uses: peaceiris/actions-gh-pages@v4
        with:
          github_token: ${{ secrets.GITHUB_TOKEN }}
          publish_dir: website/dist
```

Note: branch is `master` (matching this repo), not `main` as written in the spec. Also added `permissions: contents: write` and npm caching.

- [ ] **Step 2: Verify YAML syntax**

Run: `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/deploy-website.yml'))" 2>&1`
Expected: No errors.

- [ ] **Step 3: Note for manual action**

After deploying to gh-pages for the first time, go to GitHub repo Settings > Pages and change the source from "Deploy from a branch: docs" to "Deploy from a branch: gh-pages / root". This is a manual step in the GitHub UI.

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/deploy-website.yml
git commit -m "ci: add GitHub Actions workflow for website deployment"
```

---

## Task 13: Final Verification + Polish

**Files:**
- Modify: Various (bug fixes found during verification)

**Context:** Full end-to-end verification before considering the migration complete.

- [ ] **Step 1: Full clean build**

```bash
cd website && rm -rf dist .astro node_modules && npm ci && npm run build
```
Expected: Clean build with no warnings.

- [ ] **Step 2: Verify all SEO elements in output**

Check `website/dist/index.html` for:
- JSON-LD blocks (SoftwareApplication, FAQPage, HowTo)
- Open Graph meta tags
- Canonical URL
- Google site verification meta tag

```bash
grep -c 'application/ld+json' website/dist/index.html
grep 'og:title' website/dist/index.html
grep 'canonical' website/dist/index.html
```

- [ ] **Step 3: Verify robots.txt and sitemap in output**

```bash
cat website/dist/robots.txt
cat website/dist/sitemap.xml
```
Expected: `robots.txt` matches `docs/robots.txt` content exactly (including AI bot rules). Sitemap has correct URL.

- [ ] **Step 4: Preview and visual check**

Run: `cd website && npx astro preview`
Open browser and verify:
- All 8 sections render (Nav, Hero, Features, How It Works, Comparison, Download CTA, FAQ, Footer)
- Hero animation plays on load
- Scroll animations trigger correctly
- Mockups display inside MacWindow frames
- 3D tilt works on mockup hover
- Magnetic buttons respond to mouse
- Nav blur activates on scroll
- Mobile hamburger works at narrow viewport
- FAQ items expand/collapse
- All links point to correct URLs (with `/screenize/` base path)

- [ ] **Step 5: Fix any issues found**

Address visual bugs, broken animations, layout problems, or missing content.

- [ ] **Step 6: Add `.superpowers/` to `.gitignore` if not present**

```bash
echo '.superpowers/' >> .gitignore
```

- [ ] **Step 7: Final commit**

```bash
git add -A
git commit -m "feat(website): complete landing page redesign with Astro + GSAP"
```
