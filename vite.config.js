import { defineConfig } from 'vite'
import { resolve } from 'path'

export default defineConfig({
  base: './',
  build: {
    rollupOptions: {
      input: {
        main: resolve(__dirname, 'index.html'),
        polaris: resolve(__dirname, 'polaris.html'),
        privacy: resolve(__dirname, 'privacy.html'),
        board: resolve(__dirname, 'board.html'),
        results_guide: resolve(__dirname, 'results-guide.html'),
        job: resolve(__dirname, 'job.html'),
        jobs: resolve(__dirname, 'jobs.html'),
        report: resolve(__dirname, 'report.html')
      }
    }
  }
})
