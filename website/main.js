(() => {
  if (!window.gsap) return;
  if (window.matchMedia?.('(prefers-reduced-motion: reduce)').matches) return;

  const gsap = window.gsap;
  const hasScrollTrigger = Boolean(window.ScrollTrigger);
  if (hasScrollTrigger) gsap.registerPlugin(window.ScrollTrigger);

  function initHeroEntrance(containerSelector, itemSelector) {
    gsap.from(itemSelector || `${containerSelector} > *`, {
      y: 32,
      opacity: 0,
      filter: 'blur(6px)',
      duration: 0.9,
      ease: 'power3.out',
      stagger: 0.12,
      clearProps: 'filter'
    });
  }

  function initLineReveal(headingSelector) {
    for (const heading of document.querySelectorAll(headingSelector)) {
      const lines = heading.querySelectorAll('.line-inner');
      gsap.from(lines, {
        y: '110%',
        duration: 0.85,
        ease: 'expo.out',
        stagger: 0.08,
        scrollTrigger: hasScrollTrigger ? {
          trigger: heading,
          start: 'top 82%',
          toggleActions: 'play none none none'
        } : undefined
      });
    }
  }

  function initParallax(layers) {
    if (!hasScrollTrigger) return;
    for (const { selector, speed } of layers) {
      gsap.to(selector, {
        y: () => window.innerHeight * (speed - 1) * -0.4,
        ease: 'none',
        scrollTrigger: {
          trigger: 'body',
          start: 'top top',
          end: 'bottom bottom',
          scrub: speed
        }
      });
    }
  }

  function initMagneticPill(pillSelector, radius, strength) {
    const pill = document.querySelector(pillSelector);
    if (!pill) return;
    document.addEventListener('mousemove', (event) => {
      const rect = pill.getBoundingClientRect();
      const dx = event.clientX - (rect.left + rect.width / 2);
      const dy = event.clientY - (rect.top + rect.height / 2);
      const distance = Math.hypot(dx, dy);
      if (distance < radius) {
        const pull = 1 - distance / radius;
        gsap.to(pill, { x: dx * pull * strength, y: dy * pull * strength, duration: 0.4, ease: 'power2.out' });
      } else {
        gsap.to(pill, { x: 0, y: 0, duration: 0.8, ease: 'elastic.out(1, 0.5)' });
      }
    });
  }

  function animateCount(element, target, duration, suffix) {
    if (!element) return;
    const state = { value: 0 };
    gsap.to(state, {
      value: target,
      duration,
      ease: 'power3.out',
      onUpdate: () => {
        element.textContent = Math.round(state.value).toLocaleString() + suffix;
      }
    });
  }

  initHeroEntrance('.hero-copy', '.hero-copy > *');
  gsap.from('.hero-visual', { opacity: 0, scale: 0.96, duration: 1.1, delay: 0.25, ease: 'power3.out' });
  initLineReveal('.js-line-reveal');
  initParallax([
    { selector: '.hero-glow', speed: 0.6 },
    { selector: '.hero-shot', speed: 1.15 }
  ]);
  initMagneticPill('.pill-nav', 120, 0.28);

  if (!hasScrollTrigger) return;

  const cards = gsap.utils.toArray('.bento-card, .shortcut-card, .perm-card, .privacy-points article, .stat-row, .faq-item, .cta-actions');
  for (const card of cards) {
    gsap.from(card, {
      y: 26,
      opacity: 0,
      duration: 0.7,
      ease: 'power2.out',
      scrollTrigger: { trigger: card, start: 'top 90%', toggleActions: 'play none none none' }
    });
  }

  for (const element of gsap.utils.toArray('.stat-value')) {
    const target = Number(element.dataset.count || 0);
    const suffix = element.dataset.suffix || '';
    window.ScrollTrigger.create({
      trigger: element,
      start: 'top 86%',
      once: true,
      onEnter: () => animateCount(element, target, 1.4, suffix)
    });
  }

  document.fonts?.ready.then(() => window.ScrollTrigger.refresh());
  window.addEventListener('load', () => window.ScrollTrigger.refresh());
})();
