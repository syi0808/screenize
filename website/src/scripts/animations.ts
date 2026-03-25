import gsap from 'gsap';
import { ScrollTrigger } from 'gsap/ScrollTrigger';

// Load SplitText lazily so Astro can build without bundling it eagerly.
let SplitText: any;
try {
  const module = await import('gsap/SplitText');
  SplitText = module.SplitText;
  gsap.registerPlugin(ScrollTrigger, SplitText);
} catch (e) {
  console.warn("GSAP SplitText load failed. Using standard animations.");
  gsap.registerPlugin(ScrollTrigger);
}

export function initAnimations() {
  // Make animated elements visible before their first tween is created.
  gsap.set('[data-animate]', { visibility: 'visible', opacity: 1 });

  const ctx = gsap.context(() => {
    // Hero title animation uses SplitText when it is available.
    const title = document.querySelector('[data-animate="hero-title"]');
    if (title && SplitText) {
      const split = new SplitText(title, { type: "chars, words" });
      gsap.fromTo(split.chars, 
        { opacity: 0, y: 30 }, 
        { opacity: 1, y: 0, stagger: 0.02, duration: 1, ease: "power3.out", delay: 0.2 }
      );
    } else if (title) {
      gsap.from(title, { opacity: 0, y: 20, duration: 1 });
    }

    // Animate the supporting hero copy and CTA buttons.
    gsap.from('[data-animate="hero-subtitle"]', {
      opacity: 0,
      y: 20,
      duration: 1,
      delay: 0.5,
      ease: "power2.out"
    });

    gsap.from('[data-animate="hero-cta"]', {
      opacity: 0,
      y: 15,
      stagger: 0.1,
      duration: 0.8,
      delay: 0.8,
      ease: "back.out(1.4)"
    });

    // Reveal content blocks as they enter the viewport.
    const reveals = document.querySelectorAll('[data-animate="reveal"]');
    reveals.forEach((el) => {
      gsap.from(el, {
        scrollTrigger: {
          trigger: el,
          start: "top 92%",
          toggleActions: "play none none none"
        },
        opacity: 0,
        y: 25,
        duration: 0.8,
        ease: "power2.out"
      });
    });

    // Fade the decorative background orbs into place.
    gsap.fromTo('[data-animate="orb"]', 
      { opacity: 0 }, 
      { opacity: 0.3, duration: 2, ease: "sine.inOut" }
    );
  });

  return ctx;
}

// Wait for the full page load so measurements and assets are ready.
if (document.readyState === 'complete') {
  initAnimations();
} else {
  window.addEventListener('load', initAnimations);
}
