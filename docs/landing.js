// Point at a line of Markdown and its counterpart lights up — and the other
// way. Progressive enhancement: without this file the page is complete.
(() => {
  const pairs = new Map();
  for (const el of document.querySelectorAll('[data-pair]')) {
    const key = el.dataset.pair;
    if (!pairs.has(key)) pairs.set(key, []);
    pairs.get(key).push(el);
  }
  if (!pairs.size) return;

  const light = (key, on) => {
    for (const el of pairs.get(key) || []) el.classList.toggle('is-lit', on);
  };

  let pinned = null;

  for (const [key, els] of pairs) {
    for (const el of els) {
      el.addEventListener('pointerenter', () => light(key, true));
      el.addEventListener('pointerleave', () => light(key, false));
      // Touch has no hover: a tap pins the pair, and tapping it again releases.
      el.addEventListener('click', () => {
        const on = pinned !== key;
        if (pinned) light(pinned, false);
        pinned = on ? key : null;
        light(key, on);
      });
    }
  }
})();
