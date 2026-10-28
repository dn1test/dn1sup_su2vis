<template>
  <div class="fixed inset-0 z-50 bg-black/70 flex items-center justify-center p-4" @click.self="emit('cancel')">
    <div class="bg-white rounded-lg w-auto max-w-[92vw] max-h-[90vh] overflow-y-auto scroll-slim p-3 space-y-3">
      <div class="flex items-center justify-between">
        <span class="font-medium text-sm">Рамки с описанием — {{ name }}</span>
        <button class="px-2 py-0.5 text-xs border rounded hover:bg-slate-100" @click="emit('cancel')">Закрыть ✕</button>
      </div>
      <div class="grid md:grid-cols-[minmax(0,1fr)_240px] gap-3">
        <div class="min-w-0">
          <div class="relative select-none bg-slate-100 rounded overflow-hidden" style="touch-action: none">
            <img ref="imgRef" :src="src" class="block h-auto w-auto max-w-full max-h-[70vh] mx-auto" draggable="false" />
            <!-- рисование новой рамки: фон под всем -->
            <div class="absolute inset-0" @mousedown="onDownCreate"></div>
            <template v-for="(b, i) in items" :key="'b' + i">
              <div class="absolute border-2 bg-red-500/10 pointer-events-none"
                :class="i === active ? 'border-red-600' : 'border-red-500/70'" :style="boxStyle(b)"></div>
              <div class="absolute min-w-4 h-4 px-0.5 rounded-sm bg-white border border-red-500 text-red-600 text-[10px] font-bold flex items-center justify-center pointer-events-none"
                :style="badgeStyle(b)">{{ i + 1 }}</div>
              <!-- перенос рамки -->
              <div class="absolute cursor-move" :style="boxStyle(b)" @mousedown.stop="(e) => onDownMove(e, i)"></div>
              <template v-if="i === active">
                <div v-for="h in handles" :key="h" class="absolute w-3 h-3 bg-red-500 border border-white rounded-sm z-10"
                  :style="handleStyle(b, h)" @mousedown.stop="(e) => onDownHandle(e, i, h)"></div>
              </template>
            </template>
          </div>
          <div class="text-xs text-slate-500 mt-1">Тяни по картинке — новая рамка. Тяни рамку — сдвиг, углы — размер. Подпиши рамку справа: текст уйдёт в промпт, рамка нарисуется красной с номером.</div>
        </div>
        <div class="space-y-2">
          <div v-if="!items.length" class="text-xs text-slate-500">Рамок нет. Нарисуй первую мышкой по картинке.</div>
          <div v-for="(b, i) in items" :key="'l' + i"
            class="border rounded p-1.5" :class="i === active ? 'border-red-400' : 'border-slate-200'"
            @mousedown="active = i">
            <div class="flex items-center gap-1">
              <span class="shrink-0 text-[10px] font-bold text-red-600">{{ i + 1 }}</span>
              <input :value="b.label" placeholder="Что в этой рамке" class="flex-1 min-w-0 border rounded p-1 text-xs"
                @input="setLabel(i, $event.target.value)" @focus="active = i" />
              <button class="shrink-0 px-1 text-xs text-slate-400 hover:text-red-600" title="Удалить рамку"
                @click.stop="removeBox(i)">✕</button>
            </div>
          </div>
          <div class="flex gap-1 pt-1">
            <button class="px-2 py-1 text-xs border rounded hover:bg-slate-100" @click="reset">Сбросить</button>
            <span class="flex-1"></span>
            <button class="px-3 py-1 text-xs border rounded hover:bg-slate-100" @click="emit('cancel')">Отмена</button>
            <button class="px-3 py-1 text-xs rounded bg-slate-900 text-white hover:bg-slate-700" @click="save">Готово</button>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, onMounted, onBeforeUnmount } from 'vue'
const props = defineProps({
  src: { type: String, default: '' },
  name: { type: String, default: '' },
  boxes: { type: Array, default: () => [] }
})
const emit = defineEmits(['save', 'cancel'])
const imgRef = ref(null)
const items = ref(props.boxes.map((b) => ({ x: Number(b.x) || 0, y: Number(b.y) || 0, w: Number(b.w) || 0, h: Number(b.h) || 0, label: String(b.label || '') })))
const active = ref(-1)
const drag = ref(null)
const handles = ['nw', 'ne', 'sw', 'se']
const BOXES_MAX = 12

function relOf(e) {
  const el = imgRef.value
  if (!el) return null
  const r = el.getBoundingClientRect()
  if (!r.width || !r.height) return null
  return {
    x: Math.min(1, Math.max(0, (e.clientX - r.left) / r.width)),
    y: Math.min(1, Math.max(0, (e.clientY - r.top) / r.height))
  }
}
function onDownCreate(e) {
  if (items.value.length >= BOXES_MAX) return
  const p = relOf(e)
  if (!p) return
  items.value.push({ x: p.x, y: p.y, w: 0, h: 0, label: '' })
  active.value = items.value.length - 1
  drag.value = { mode: 'create', start: p, idx: items.value.length - 1 }
  e.preventDefault()
}
function onDownMove(e, i) {
  const p = relOf(e)
  if (!p) return
  active.value = i
  drag.value = { mode: 'move', start: p, orig: { ...items.value[i] }, idx: i }
  e.preventDefault()
}
function onDownHandle(e, i, h) {
  active.value = i
  drag.value = { mode: 'resize-' + h, orig: { ...items.value[i] }, idx: i }
  e.preventDefault()
}
function onMove(e) {
  const dr = drag.value
  if (!dr) return
  const it = items.value[dr.idx]
  if (!it) return
  const p = relOf(e)
  if (!p) return
  if (dr.mode === 'create') {
    it.x = Math.min(dr.start.x, p.x)
    it.y = Math.min(dr.start.y, p.y)
    it.w = Math.abs(p.x - dr.start.x)
    it.h = Math.abs(p.y - dr.start.y)
  } else if (dr.mode === 'move') {
    const dx = p.x - dr.start.x
    const dy = p.y - dr.start.y
    it.x = Math.min(1 - dr.orig.w, Math.max(0, dr.orig.x + dx))
    it.y = Math.min(1 - dr.orig.h, Math.max(0, dr.orig.y + dy))
  } else if (dr.mode.startsWith('resize-')) {
    const o = dr.orig
    const x2 = o.x + o.w
    const y2 = o.y + o.h
    let nx = o.x
    let ny = o.y
    let nx2 = x2
    let ny2 = y2
    const m = dr.mode.slice(7)
    if (m.includes('w')) nx = Math.min(p.x, x2 - 0.02)
    if (m.includes('e')) nx2 = Math.max(p.x, o.x + 0.02)
    if (m.includes('n')) ny = Math.min(p.y, y2 - 0.02)
    if (m.includes('s')) ny2 = Math.max(p.y, o.y + 0.02)
    it.x = Math.min(1, Math.max(0, nx))
    it.y = Math.min(1, Math.max(0, ny))
    it.w = Math.min(1 - it.x, Math.max(0.02, nx2 - nx))
    it.h = Math.min(1 - it.y, Math.max(0.02, ny2 - ny))
  }
}
function onUp() {
  const dr = drag.value
  if (dr && dr.mode === 'create') {
    const it = items.value[dr.idx]
    if (it && (it.w < 0.02 || it.h < 0.02)) {
      items.value.splice(dr.idx, 1)
      active.value = -1
    } else if (it) {
      it.x = Math.round(it.x * 10000) / 10000
      it.y = Math.round(it.y * 10000) / 10000
      it.w = Math.round(it.w * 10000) / 10000
      it.h = Math.round(it.h * 10000) / 10000
    }
  }
  drag.value = null
}
function setLabel(i, v) {
  if (items.value[i]) items.value[i].label = v
}
function removeBox(i) {
  items.value.splice(i, 1)
  if (active.value >= items.value.length) active.value = items.value.length - 1
}
function reset() {
  items.value = []
  active.value = -1
}
function save() {
  const r4 = (v) => Math.round((Number(v) || 0) * 10000) / 10000
  emit('save', { boxes: items.value.map((b) => ({ x: r4(b.x), y: r4(b.y), w: r4(b.w), h: r4(b.h), label: String(b.label || '').trim().slice(0, 200) })) })
}
function boxStyle(b) {
  return {
    left: ((Number(b.x) || 0) * 100) + '%',
    top: ((Number(b.y) || 0) * 100) + '%',
    width: ((Number(b.w) || 0) * 100) + '%',
    height: ((Number(b.h) || 0) * 100) + '%'
  }
}
function badgeStyle(b) {
  return { left: ((Number(b.x) || 0) * 100) + '%', top: ((Number(b.y) || 0) * 100) + '%' }
}
function handleStyle(b, h) {
  let lx = Number(b.x) || 0
  let ty = Number(b.y) || 0
  if (h.includes('e')) lx = (Number(b.x) || 0) + (Number(b.w) || 0)
  if (h.includes('s')) ty = (Number(b.y) || 0) + (Number(b.h) || 0)
  return { left: `calc(${lx * 100}% - 6px)`, top: `calc(${ty * 100}% - 6px)`, cursor: h + '-resize' }
}
onMounted(() => {
  window.addEventListener('mouseup', onUp)
  window.addEventListener('mousemove', onMove)
})
onBeforeUnmount(() => {
  window.removeEventListener('mouseup', onUp)
  window.removeEventListener('mousemove', onMove)
})
</script>
