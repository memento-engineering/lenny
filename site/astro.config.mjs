import { defineConfig } from 'astro/config';

export default defineConfig({
  site: 'https://memento-engineering.github.io/lenny',
  base: '/lenny',
  // Zero client-side JS: no integrations, no islands.
});
