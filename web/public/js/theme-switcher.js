(() => {
  const root = document.documentElement;
  const darkScheme = window.matchMedia('(prefers-color-scheme: dark)');
  const themeColors = { light: '#ffffff', dark: '#0b0c10' };

  function readTheme() {
    try {
      const saved = localStorage.getItem('cocxy-theme');
      return saved === 'light' || saved === 'dark' ? saved : null;
    } catch (_) {
      return null;
    }
  }

  function activeTheme() {
    return root.dataset.theme || (darkScheme.matches ? 'dark' : 'light');
  }

  function syncThemeColor() {
    const chosen = root.dataset.theme;
    if (!chosen) return;
    document.querySelectorAll('meta[name="theme-color"]').forEach((meta) => {
      meta.setAttribute('content', themeColors[chosen]);
    });
  }

  const saved = readTheme();
  if (saved) root.dataset.theme = saved;

  document.addEventListener('DOMContentLoaded', () => {
    syncThemeColor();
    const toggle = document.querySelector('.theme-toggle');
    if (!toggle) return;

    toggle.addEventListener('click', () => {
      const next = activeTheme() === 'light' ? 'dark' : 'light';
      root.dataset.theme = next;
      syncThemeColor();
      try {
        localStorage.setItem('cocxy-theme', next);
      } catch (_) {}
    });
  });
})();
