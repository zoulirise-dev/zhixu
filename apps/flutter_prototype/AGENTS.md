# Flutter UI requirements

For every UI change, support both Chinese and English and both light and dark themes.
- Route user-visible labels, statuses, errors and tooltips through `tr`/`T`; add English translations, including interpolated templates.
- Keep native macOS menu labels and window chrome synchronized with the in-app language and appearance.
- Use theme-derived surface, text, border and hover colors. Check contrast in both themes.
- Preserve Chinese IME composition, accessible hit targets, mouse cursors and modal barriers.
- Verify changed screens in both languages and themes; do not assume static analysis proves visual correctness.
- Keep the native macOS app intact. This directory is the independent cross-platform app.
