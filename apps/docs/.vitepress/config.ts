import { defineConfig } from 'vitepress'

export default defineConfig({
  title: 'macwlt',
  description: 'macwlt',
  lang: 'en-US',
  outDir: 'dist',
  srcExclude: ['AGENTS.md'],
  cleanUrls: true,
  head: [
    [
      'link',
      { rel: 'icon', type: 'image/svg+xml', href: '/macwlt-logo.svg' },
    ],
  ],
  vite: {
    publicDir: '../landing/public',
  },
  themeConfig: {
    logo: {
      src: '/macwlt-logo.svg',
      alt: 'macwlt',
    },
  },
})
