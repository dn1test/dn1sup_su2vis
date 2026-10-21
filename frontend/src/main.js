import { createApp } from 'vue'
import App from './App.vue'
import './style.css'

createApp(App).mount('#app')

// Подсветка скрытых скроллбаров только во время прокрутки.
let fadeTimer = null
document.addEventListener('scroll', (e) => {
  const el = e.target
  if (el instanceof HTMLElement && el.classList.contains('scroll-slim')) {
    el.classList.add('scrolling')
    clearTimeout(fadeTimer)
    fadeTimer = setTimeout(() => el.classList.remove('scrolling'), 900)
  }
}, { passive: true, capture: true })
