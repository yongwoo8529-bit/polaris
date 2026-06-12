import { defineConfig } from 'vite'
import { resolve } from 'path'

export default defineConfig({
  base: './',
  build: {
    rollupOptions: {
      input: {
        main: resolve(__dirname, 'index.html'),
        polaris: resolve(__dirname, 'polaris.html'),
        about: resolve(__dirname, 'about.html'),
        privacy: resolve(__dirname, 'privacy.html'),
        board: resolve(__dirname, 'board.html'),
        blog: resolve(__dirname, 'blog.html'),
        results_guide: resolve(__dirname, 'results-guide.html'),
        post: resolve(__dirname, 'post.html')
      }
    }
  }
})
