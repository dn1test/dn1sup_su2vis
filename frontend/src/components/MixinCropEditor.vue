<template>
  <div class="fixed inset-0 z-50 bg-black/70 flex items-center justify-center p-4" @click.self="emit('cancel')">
    <div class="bg-white rounded-lg max-w-3xl w-full max-h-[90vh] overflow-y-auto scroll-slim p-3 space-y-3">
      <div class="flex items-center justify-between">
        <span class="font-medium text-sm">Выделение и поворот — {{ name }}</span>
        <button class="px-2 py-0.5 text-xs border rounded hover:bg-slate-100" @click="emit('cancel')">Закрыть ✕</button>
      </div>
      <div class="grid md:grid-cols-[1fr_220px] gap-3">
        <div>
          <div ref="wrapRef" class="relative select-none bg-slate-100 rounded overflow-hidden" style="touch-action: none">
            <img ref="imgRef" :src="src" class="w-full h-auto block" draggable="false" @load="onImgLoad" />
            <div class="absolute inset-0" @mousedown="onDown" @mousemove="onMove" @mouseup="onUp"></div>
            <div v-if="draft && boxPct" class="absolute border-2 border-dashed border-amber-400 bg-amber-400/10 pointer-events-none"
              :style="boxPct"></div>
            <template v-if="draft && boxPct">
              <div v-for="h in handles" :key="h" class="absolute w-3 h-3 bg-amber-400 border border-white rounded-sm z-10"
                :style="handleStyle(h)" @mousedown.stop="(e) => onDownHandle(e, h)"></div>
            </template>
          </div>
          <div class="text-xs text-slate-500 mt-1">Тяни мышкой по картинке — выберешь часть. Тяни саму рамку — сдвиг, углы — размер. Выкл. «Только выделение» = вся картинка.</div>
        </div>
        <div class="space-y-2">
          <label class="flex items-center gap-2 text-xs">
            <input type="checkbox" :checked="useCrop" @change="useCrop = $event.target.checked" />
            Только выделение
          </label>
          <div class="flex gap-1">
            <button class="flex-1 px-2 py-1 text-xs border rounded hover:bg-slate-100" @click="rotBy(-90)">⟲ 90°</button>
            <button class="flex-1 px-2 py-1 text-xs border rounded hover:bg-slate-100" @click="rotBy(90)">⟳ 90°</button>
          </div>
          <label class="block text-xs text-slate-600">
            Поворот {{ fmtRot(draftRot) }}°
            <input type="range" min="-180" max="180" step="1" :value="draftRot" @input="draftRot = +$event.target.value" class="w-full accent-slate-900" />
          </label>
          <label class="flex items-center gap-1 text-xs text-slate-600">
            Угол:
            <input type="number" min="-180" max="180" step="1" :value="Math.round(draftRot)" @input="draftRot = clampRot(+$event.target.value)" class="border rounded p-1 text-xs w-20" />°
          </label>
          <div class="text-xs text-slate-600">Результат в генерацию:</div>
          <canvas ref="prevRef" class="w-full rounded border bg-slate-100"></canvas>
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
import { ref, computed, watch, nextTick, onMounted, onBeforeUnmount } from 'vue'
const props = defineProps({
  src: { type: String, default: '' },
  name: { type: String, default: '' },
  crop: { type: Object, default: null },
  rotation: { type: [Number, String], default: 0 }
})
const emit = defineEmits(['save', 'cancel'])
const wrapRef = ref(null)
const imgRef = ref(null)
const prevRef = ref(null)
const draft = ref(props.crop ? { ...props.crop } : null)
const useCrop = ref(!!props.crop)
const draftRot = ref(Number(props.rotation) || 0)
const drag = ref(null)
const natSize = ref({ w: 0, h: 0 })
const handles = ['nw', 'ne', 'sw', 'se']

function clampRot(v) {
  if (!Number.isFinite(v)) return 0
  return Math.min(180, Math.max(-180, Math.round(v)))
}
function rotBy(d) {
  let v = (Number(draftRot.value) || 0) + d
  v = ((v + 180) % 360 + 360) % 360 - 180
  if (v === -180) v = 180
  draftRot.value = Math.round(v)
}
function fmtRot(v) {
  const n = Math.round(Number(v) || 0)
  return (n > 0 ? '+' : '') + n
}
function reset() {
  draft.value = null
  useCrop.value = false
  draftRot.value = 0
}
function save() {
  emit('save', { crop: useCrop.value && draft.value ? { ...draft.value } : null, rotation: clampRot(Number(draftRot.value) || 0) })
}
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
function insideRect(p, c) {
  if (!c) return false
  const m = 0.01
  return p.x >= c.x - m && p.x <= c.x + c.w + m && p.y >= c.y - m && p.y <= c.y + c.h + m
}
function onDown(e) {
  const p = relOf(e)
  if (!p) return
  if (useCrop.value && insideRect(p, draft.value)) {
    drag.value = { mode: 'move', start: p, orig: { ...draft.value } }
  } else {
    drag.value = { mode: 'create', start: p }
    draft.value = { x: p.x, y: p.y, w: 0, h: 0 }
    useCrop.value = true
  }
  e.preventDefault()
}
function onDownHandle(e, h) {
  if (!draft.value) return
  drag.value = { mode: 'resize-' + h, orig: { ...draft.value } }
  e.preventDefault()
}
function onMove(e) {
  const dr = drag.value
  if (!dr || !draft.value) return
  const p = relOf(e)
  if (!p) return
  if (dr.mode === 'create') {
    const x = Math.min(dr.start.x, p.x)
    const y = Math.min(dr.start.y, p.y)
    draft.value = { x, y, w: Math.abs(p.x - dr.start.x), h: Math.abs(p.y - dr.start.y) }
  } else if (dr.mode === 'move') {
    const dx = p.x - dr.start.x
    const dy = p.y - dr.start.y
    const w = dr.orig.w
    const h = dr.orig.h
    draft.value = {
      x: Math.min(1 - w, Math.max(0, dr.orig.x + dx)),
      y: Math.min(1 - h, Math.max(0, dr.orig.y + dy)),
      w, h
    }
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
    nx = Math.min(1, Math.max(0, nx))
    ny = Math.min(1, Math.max(0, ny))
    nx2 = Math.min(1, Math.max(0, nx2))
    ny2 = Math.min(1, Math.max(0, ny2))
    draft.value = { x: nx, y: ny, w: Math.max(0.02, nx2 - nx), h: Math.max(0.02, ny2 - ny) }
  }
}
function onUp() {
  if (drag.value && drag.value.mode === 'create' && draft.value) {
    if (draft.value.w < 0.02 || draft.value.h < 0.02) draft.value = null
    else {
      draft.value = {
        x: Math.round(draft.value.x * 10000) / 10000,
        y: Math.round(draft.value.y * 10000) / 10000,
        w: Math.round(draft.value.w * 10000) / 10000,
        h: Math.round(draft.value.h * 10000) / 10000
      }
    }
  }
  drag.value = null
}
const boxPct = computed(() => {
  const c = draft.value
  if (!c || !useCrop.value) return null
  return {
    left: (c.x * 100) + '%',
    top: (c.y * 100) + '%',
    width: (c.w * 100) + '%',
    height: (c.h * 100) + '%'
  }
})
function handleStyle(h) {
  const c = draft.value
  if (!c) return {}
  const px = { x: c.x, y: c.y, w: c.w, h: c.h }
  let lx = px.x
  let ty = px.y
  if (h.includes('e')) lx = px.x + px.w
  if (h.includes('s')) ty = px.y + px.h
  return { left: `calc(${lx * 100}% - 6px)`, top: `calc(${ty * 100}% - 6px)`, cursor: h + '-resize' }
}
function onImgLoad() {
  const el = imgRef.value
  if (el) natSize.value = { w: el.naturalWidth || 0, h: el.naturalHeight || 0 }
  drawPrev()
}
function drawPrev() {
  const cv = prevRef.value
  const el = imgRef.value
  if (!cv || !el || !el.naturalWidth) return
  const c = useCrop.value && draft.value ? draft.value : { x: 0, y: 0, w: 1, h: 1 }
  const sx = Math.round(c.x * el.naturalWidth)
  const sy = Math.round(c.y * el.naturalHeight)
  const sw = Math.max(1, Math.round(c.w * el.naturalWidth))
  const sh = Math.max(1, Math.round(c.h * el.naturalHeight))
  const ang = (Number(draftRot.value) || 0) * Math.PI / 180
  const cos = Math.abs(Math.cos(ang))
  const sin = Math.abs(Math.sin(ang))
  const dw = Math.max(1, Math.round(sw * cos + sh * sin))
  const dh = Math.max(1, Math.round(sw * sin + sh * cos))
  const maxSide = 220
  const sc = Math.min(1, maxSide / Math.max(dw, dh))
  cv.width = Math.max(1, Math.round(dw * sc))
  cv.height = Math.max(1, Math.round(dh * sc))
  const ctx = cv.getContext('2d')
  if (!ctx) return
  ctx.save()
  ctx.translate(cv.width / 2, cv.height / 2)
  ctx.rotate(ang)
  ctx.scale(sc, sc)
  ctx.drawImage(el, sx, sy, sw, sh, -sw / 2, -sh / 2, sw, sh)
  ctx.restore()
}
watch([draft, draftRot, useCrop], () => nextTick(drawPrev), { deep: true })
onMounted(() => {
  window.addEventListener('mouseup', onUp)
  window.addEventListener('mousemove', onMove)
  nextTick(drawPrev)
})
onBeforeUnmount(() => {
  window.removeEventListener('mouseup', onUp)
  window.removeEventListener('mousemove', onMove)
})
</script>
