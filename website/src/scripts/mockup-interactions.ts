import gsap from 'gsap';

const prefersReducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
const isTouch = () => 'ontouchstart' in window || navigator.maxTouchPoints > 0;

function initTilt() {
  if (prefersReducedMotion || isTouch()) return;

  const mockups = document.querySelectorAll<HTMLElement>('[data-tilt]');
  mockups.forEach((el) => {
    // Ensure relative positioning and transform-style are set for tilt
    el.style.transformStyle = 'preserve-3d';
    el.style.willChange = 'transform';

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

function initMagneticButtons() {
  if (prefersReducedMotion || isTouch()) return;

  const buttons = document.querySelectorAll<HTMLElement>('[data-magnetic]');
  buttons.forEach((btn) => {
    btn.addEventListener('mousemove', (e) => {
      const rect = btn.getBoundingClientRect();
      const x = e.clientX - rect.left - rect.width / 2;
      const y = e.clientY - rect.top - rect.height / 2;

      gsap.to(btn, {
        x: x * 0.3, // Increased magnetic effect slightly
        y: y * 0.3,
        duration: 0.3,
        ease: 'power2.out',
      });
    });

    btn.addEventListener('mouseleave', () => {
      gsap.to(btn, { 
        x: 0, 
        y: 0, 
        duration: 0.5, 
        ease: 'elastic.out(1, 0.3)' 
      });
    });
  });
}

export function initInteractions() {
  initTilt();
  initMagneticButtons();
}

// Handle initialization
if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', initInteractions);
} else {
  initInteractions();
}
