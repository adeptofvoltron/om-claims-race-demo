// Turns a human-readable title into a URL slug.
export function slugify(title) {
  return title
    .toLowerCase()
    .trim()
    // Strip diacritics (ż → z, ó → o, …); ł has no decomposition, so map it.
    .normalize('NFD')
    .replace(/\p{M}/gu, '')
    .replace(/ł/g, 'l')
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-|-$/g, '');
}
