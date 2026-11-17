const sections = [...document.querySelectorAll('main section[id]')];
const links = [...document.querySelectorAll('.pill-link')];

function setActive(id) {
  for (const link of links) {
    const active = link.getAttribute('href') === `#${id}`;
    link.classList.toggle('is-active', active);
    if (active) link.setAttribute('aria-current', 'true');
    else link.removeAttribute('aria-current');
  }
}

if (sections.length && links.length && 'IntersectionObserver' in window) {
  const observer = new IntersectionObserver((entries) => {
    const visible = entries
      .filter((entry) => entry.isIntersecting)
      .sort((a, b) => b.intersectionRatio - a.intersectionRatio)[0];
    if (visible) setActive(visible.target.id);
  }, { rootMargin: '-45% 0px -45% 0px', threshold: [0, 0.2, 0.6] });
  for (const section of sections) observer.observe(section);
}

for (const item of document.querySelectorAll('.faq-item')) {
  const trigger = item.querySelector('.faq-trigger');
  if (!trigger) continue;
  trigger.addEventListener('click', () => {
    const open = item.dataset.open === 'true';
    for (const other of document.querySelectorAll('.faq-item[data-open="true"]')) {
      if (other !== item) {
        other.dataset.open = 'false';
        other.querySelector('.faq-trigger')?.setAttribute('aria-expanded', 'false');
      }
    }
    item.dataset.open = String(!open);
    trigger.setAttribute('aria-expanded', String(!open));
  });
}

const switcher = document.querySelector('.language-switch');
document.addEventListener('click', (event) => {
  if (switcher?.open && !switcher.contains(event.target)) switcher.open = false;
});
