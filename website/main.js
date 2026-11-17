(() => {
  if (!window.gsap) return;
  if (window.matchMedia?.('(prefers-reduced-motion: reduce)').matches) return;

  const gsap = window.gsap;
  const title = document.querySelector('#hero-title');

  if (title) {
    gsap.from(title.querySelectorAll('.line-inner'), {
      y: '110%',
      duration: 0.85,
      ease: 'expo.out',
      stagger: 0.08
    });
  }

  const rest = [...document.querySelectorAll('.hero-inner > *')].filter((element) => element !== title);
  if (rest.length) {
    gsap.from(rest, {
      y: 22,
      opacity: 0,
      duration: 0.8,
      ease: 'power3.out',
      stagger: 0.07,
      delay: 0.12
    });
  }
})();
