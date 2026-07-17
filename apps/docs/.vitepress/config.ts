import { defineConfig } from 'vitepress'

export default defineConfig({
  title: 'macwlt Docs',
  description: 'Documentation for macwlt.',
  lang: 'en-US',
  outDir: 'dist',
  cleanUrls: true,
  head: [
    ['link', { rel: 'icon', type: 'image/svg+xml', href: '/favicon.svg' }],
  ],
  vite: {
    publicDir: '../landing/public',
  },
  themeConfig: {
    nav: [{ text: 'Home', link: '/' }],
    socialLinks: [
      { icon: 'github', link: 'https://github.com/paoloanzn/macwlt' },
    ],
  },
})
