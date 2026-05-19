(() => {
  function readTheme() {
    try {
      const saved = localStorage.getItem('cocxy-theme');
      return saved === 'light' || saved === 'dark' ? saved : null;
    } catch (_) {
      return null;
    }
  }

  function applyTheme(theme) {
    if (theme) document.documentElement.dataset.theme = theme;
  }

  applyTheme(readTheme());

  document.addEventListener('DOMContentLoaded', () => {
    const toggle = document.querySelector('.theme-toggle');
    if (!toggle) return;

    toggle.addEventListener('click', () => {
      const current = document.documentElement.dataset.theme;
      const next = current === 'light' ? 'dark' : 'light';
      document.documentElement.dataset.theme = next;
      try {
        localStorage.setItem('cocxy-theme', next);
      } catch (_) {}
    });
  });
})();
