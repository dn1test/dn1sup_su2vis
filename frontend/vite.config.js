import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'
import { viteSingleFile } from 'vite-plugin-singlefile'

const OUT_DIR = fileURLToPath(new URL('../dn1sup_su2vis/resources', import.meta.url))

function renamePanelHtml() {
  return {
    name: 'rename-panel-html',
    closeBundle() {
      const from = path.join(OUT_DIR, 'index.html')
      const to = path.join(OUT_DIR, 'panel.html')
      if (fs.existsSync(from)) fs.renameSync(from, to)
    }
  }
}

export default defineConfig({
  base: './',
  plugins: [vue(), viteSingleFile(), renamePanelHtml()],
  build: {
    outDir: OUT_DIR,
    emptyOutDir: false,
    rollupOptions: {
      input: { panel: fileURLToPath(new URL('./index.html', import.meta.url)) }
    }
  }
})
