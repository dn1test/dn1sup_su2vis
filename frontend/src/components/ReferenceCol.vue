<template>
  <div class="border rounded-lg bg-white overflow-hidden flex flex-col min-h-0 max-h-full min-w-0">
    <div class="shrink-0 px-3 py-2 border-b bg-slate-50">
      <div class="font-medium mb-1">Референс</div>
      <div class="flex gap-1">
        <button v-for="t in tabs" :key="t.id" @click="active = t.id"
          class="flex-1 px-1 py-1 text-xs border rounded"
          :class="active === t.id ? 'bg-slate-900 text-white' : 'hover:bg-slate-100'">{{ t.label }}</button>
      </div>
    </div>
    <!-- Сцены -->
    <div v-if="active === 'scenes'" class="flex-1 min-h-0 flex flex-col overflow-hidden">
      <div class="shrink-0 px-3 pt-3">
        <label class="flex items-center gap-2 text-xs text-slate-600 cursor-pointer">
          <input type="checkbox" :checked="enabledScenes" @change="emit('toggle-enabled-scenes', $event.target.checked)" />
          использовать сцены (выкл — только промпт/примеси)
        </label>
      </div>
      <div class="flex-1 min-h-0 overflow-y-auto scroll-slim p-3 space-y-2" :class="!enabledScenes ? 'opacity-50 pointer-events-none' : ''" :ref="setListEl">
      <div class="flex gap-1">
        <button class="flex-1 px-2 py-1 text-xs border rounded hover:bg-slate-100" @click="emit('refresh')">Обновить</button>
      </div>
      <div v-if="!scenes.length" class="text-xs text-slate-500">Нет сцен. Создайте сцены в модели → «Обновить».</div>
      <div v-else class="text-xs text-slate-500">Выберите одну сцену. Эскиз = сохранённый вид сцены. Покрутили камеру — жмите ⟳ на сцене.</div>
      <label v-for="s in scenes" :key="s.index"
        class="block border rounded overflow-hidden cursor-pointer hover:border-slate-400"
        :class="selected.includes(s.index) ? 'ring-2 ring-blue-500' : ''">
        <div class="flex items-center gap-2 px-2 py-1">
          <input type="radio" name="su2vis-scene" :checked="selected.includes(s.index)" @change="emit('toggle', s.index)" />
          <span class="truncate text-xs font-medium flex-1">{{ s.name }}</span>
          <span v-if="(s.boxes || []).length" class="shrink-0 text-[10px] px-1.5 py-0.5 rounded bg-red-100 text-red-800"
            title="Рамки с описанием уйдут в промпт">{{ (s.boxes || []).length }} рамок</span>
          <button class="px-1.5 py-0.5 text-xs border rounded hover:bg-slate-100" title="Записать текущий вид окна в сцену"
            @click.prevent="emit('sync-view', s.index)">⟳</button>
          <button class="px-1.5 py-0.5 text-xs border rounded hover:bg-slate-100" title="Рамки с описанием — уйдут в промпт, нарисуются на эскизе"
            @click.prevent="openSceneBoxes(s)">▣</button>
        </div>
        <div v-if="thumbs[s.index]" class="relative">
          <img :src="thumbs[s.index]" class="w-full aspect-[4/3] object-cover bg-slate-200" />
          <template v-for="(b, bi) in (s.boxes || [])" :key="'sb' + bi">
            <div class="absolute border-2 border-red-500 bg-red-500/10 pointer-events-none" :style="boxStyle(b)"></div>
            <div class="absolute min-w-4 h-4 px-0.5 rounded-sm bg-white border border-red-500 text-red-600 text-[10px] font-bold flex items-center justify-center pointer-events-none"
              :style="badgeStyle(b)">{{ bi + 1 }}</div>
          </template>
        </div>
        <div v-else class="w-full aspect-[4/3] bg-slate-200 flex items-center justify-center text-xs text-slate-500">вид сцены</div>
        </label>
      </div>
    </div>
    <!-- Примеси -->
    <div v-if="active === 'mixins'" class="flex-1 min-h-0 flex flex-col overflow-hidden">
      <div class="shrink-0 px-3 pt-3">
        <label class="flex items-center gap-2 text-xs text-slate-600 cursor-pointer">
          <input type="checkbox" :checked="enabledMixins" @change="emit('toggle-enabled-mixins', $event.target.checked)" />
          использовать примеси ({{ activeCount }}/{{ items.length }})
        </label>
      </div>
      <div class="shrink-0 p-3 pb-0 space-y-2" :class="!enabledMixins ? 'opacity-50 pointer-events-none' : ''">
        <div class="flex gap-2">
          <label class="flex-1 px-3 py-2 rounded bg-slate-900 text-white text-xs text-center cursor-pointer hover:bg-slate-700">
            Добавить…
            <input ref="fileInput" type="file" accept="image/png,image/jpeg,image/webp" multiple class="hidden" @change="onFiles" />
          </label>
          <button class="px-3 py-2 rounded border text-xs hover:bg-slate-100" title="Выбрать файл с диска через SketchUp"
            @click="emit('add-path')">Из файла…</button>
          <button :disabled="!items.length" @click="askDeleteAll"
            class="px-3 py-2 rounded border text-xs disabled:opacity-40"
            :class="confirmAll ? 'border-red-300 bg-red-50 text-red-700 hover:bg-red-100' : 'hover:bg-slate-100'"
            :title="confirmAll ? 'Ещё раз — удалит все файлы примесей с диска' : 'Удалить все примеси (файлы с диска)'">
            {{ confirmAll ? 'Точно?' : 'Удалить все' }}
          </button>
        </div>
        <label class="block">
          <span class="text-xs text-slate-500">Что брать по умолчанию (новые карточки)</span>
          <select :value="settings.mixins_default_role || 'auto'" @change="emit('update-settings', { mixins_default_role: $event.target.value })"
            class="mt-1 w-full border rounded p-1.5 text-xs bg-white">
            <option value="auto">авто — всё</option>
            <option value="style">стиль/настроение</option>
            <option value="material">материал/фактура</option>
            <option value="light">свет/цвет</option>
            <option value="object">объект/деталь</option>
          </select>
        </label>
        <div v-if="!items.length" class="text-xs text-slate-500">Картинки-референсы + подпись «что взять». Учитываются в рендере.</div>
      </div>
      <div class="flex-1 min-h-0 overflow-y-auto scroll-slim p-3 space-y-2" :class="!enabledMixins ? 'opacity-50 pointer-events-none' : ''">
        <div v-for="(m, idx) in items" :key="m.id" class="relative border rounded overflow-hidden" :class="m.active === false ? 'opacity-60' : ''">
          <button class="absolute top-1 right-1 z-10 w-6 h-6 text-xs rounded-full bg-black/60 text-white hover:bg-red-600"
            title="Удалить файл" @click.stop="emit('delete', m)">✕</button>
          <div v-if="m.data_url" class="relative bg-slate-100">
            <MixinThumb v-if="hasTransform(m) && !showOrig[m.id]" :src="m.data_url" :crop="m.crop" :rotation="m.rotation" />
            <img v-else :src="m.data_url" class="w-full h-auto block" />
            <div v-if="m.crop && (!hasTransform(m) || showOrig[m.id])" class="absolute border-2 border-dashed border-amber-400 bg-amber-400/10 pointer-events-none"
              :style="cropStyle(m.crop)"></div>
            <button v-if="hasTransform(m)" class="absolute bottom-1 right-1 z-10 px-1.5 py-0.5 text-[10px] rounded bg-black/60 text-white hover:bg-black/80"
              :title="showOrig[m.id] ? 'Показать отредактированную' : 'Показать оригинал (редактор тоже правит оригинал)'"
              @click="showOrig[m.id] = !showOrig[m.id]">{{ showOrig[m.id] ? 'правка' : 'оригинал' }}</button>
          </div>
          <div v-else class="w-full bg-slate-200 flex items-center justify-center text-xs text-slate-500 py-6">загружаю…</div>
          <div class="px-2 pt-1 flex items-center gap-1">
            <button class="flex-1 px-2 py-1 text-xs border rounded hover:bg-slate-100" :disabled="!m.data_url"
              title="Выделить мышкой часть картинки и повернуть (правит оригинал)" @click="editing = m">Выделить / повернуть…</button>
            <button class="px-2 py-1 text-xs border rounded hover:bg-slate-100 disabled:opacity-30" :disabled="!m.data_url"
              title="Рамки с подписями на референсе — уйдут в промпт" @click="openMixinBoxes(m)">Рамки…</button>
            <span v-if="m.crop" class="shrink-0 text-[10px] px-1.5 py-0.5 rounded bg-amber-100 text-amber-900" title="В генерацию уйдёт только выделение">выделение</span>
            <span v-if="numRot(m.rotation) !== 0" class="shrink-0 text-[10px] px-1.5 py-0.5 rounded bg-sky-100 text-sky-900" :title="'Поворот ' + fmtRot(m.rotation) + '°'">{{ fmtRot(m.rotation) }}°</span>
            <span v-if="(m.boxes || []).length" class="shrink-0 text-[10px] px-1.5 py-0.5 rounded bg-red-100 text-red-800"
              title="Рамки с подписями уйдут в промпт">{{ (m.boxes || []).length }}</span>
          </div>
          <div class="p-2 space-y-1">
            <div class="flex items-center gap-1">
              <input type="checkbox" :checked="m.active !== false" @change="emit('toggle-mixin', m)" />
              <span class="text-xs font-medium truncate flex-1" :title="m.name">{{ m.name || m.id }}</span>
              <button class="px-1.5 py-0.5 text-xs border rounded hover:bg-slate-100 disabled:opacity-30" :disabled="idx === 0"
                title="Выше (сильнее в запросе)" @click="emit('move', { item: m, dir: -1 })">▲</button>
              <button class="px-1.5 py-0.5 text-xs border rounded hover:bg-slate-100 disabled:opacity-30" :disabled="idx === items.length - 1"
                title="Ниже" @click="emit('move', { item: m, dir: 1 })">▼</button>
            </div>
            <select :value="m.role || 'auto'" @change="emit('role', { item: m, role: $event.target.value })"
              class="w-full border rounded p-1 text-xs" title="Что взять с референса">
              <option value="auto">авто — всё</option>
              <option value="style">стиль/настроение</option>
              <option value="material">материал/фактура</option>
              <option value="light">свет/цвет</option>
              <option value="object">объект/деталь</option>
            </select>
            <textarea :value="m.caption || ''" @input="emit('caption', { item: m, caption: $event.target.value })"
              rows="2" placeholder="Что взять: напр. фактура кирпича со стены"
              class="w-full border rounded p-1.5 text-xs"></textarea>
            <textarea :value="m.caption_neg || ''" @input="emit('neg', { item: m, caption_neg: $event.target.value })"
              rows="1" placeholder="Чего НЕ брать: напр. геометрию, людей"
              class="w-full border rounded p-1.5 text-xs"></textarea>
            <label class="flex items-center gap-2 text-xs text-slate-600">
              <span class="shrink-0">Вес {{ fmtWeight(m.weight) }}</span>
              <input type="range" min="0.1" max="2" step="0.05" :value="numWeight(m.weight)"
                @input="emit('weight', { item: m, weight: +$event.target.value })" class="w-full accent-slate-900" />
            </label>
          </div>
        </div>
      </div>
    </div>
    <!-- Настройки съёма -->
    <div v-if="active === 'settings'" class="flex-1 min-h-0 overflow-y-auto scroll-slim p-3 space-y-2">
      <div class="text-xs font-medium">Эскиз-референс для модели</div>
      <div class="text-xs text-slate-500">Параметры съёма эскиза, который уйдёт референсом в модель.</div>
      <label class="block">
        <span class="text-xs text-slate-500">Размер эскиза</span>
        <select :value="sketch.source" @change="upd('source', $event.target.value)"
          class="mt-1 w-full border rounded p-1.5 text-xs bg-white">
          <option value="hd">HD 1600 по длинной</option>
          <option value="view">Размер вида</option>
          <option value="preset">Точный пресет</option>
        </select>
      </label>
      <label v-if="sketch.source === 'preset'" class="block">
        <span class="text-xs text-slate-500">Пресет</span>
        <select :value="sketch.preset" @change="upd('preset', $event.target.value)"
          class="mt-1 w-full border rounded p-1.5 text-xs bg-white">
          <option v-for="p in sketchPresets" :key="p" :value="p">{{ p }}</option>
        </select>
      </label>
      <label class="flex items-center gap-2 text-xs text-slate-600 cursor-pointer" title="Выключить силуэты на время снимка (рекомендуется для мелких форматов)">
        <input type="checkbox" :checked="sketch.thin_lines !== false" @change="upd('thin_lines', $event.target.checked)" />
        тонкие линии
      </label>
      <label class="flex items-center gap-2 text-xs text-slate-600 cursor-pointer" title="Прятать размерные линии на время снимка">
        <input type="checkbox" :checked="sketch.hide_dims !== false" @change="upd('hide_dims', $event.target.checked)" />
        скрыть размеры
      </label>
      <label class="flex items-center gap-2 text-xs text-slate-600 cursor-pointer" title="Резать пустые поля до контента (+5%) — объект займёт весь кадр">
        <input type="checkbox" :checked="sketch.autocrop === true" @change="upd('autocrop', $event.target.checked)" />
        автообрезка фона
      </label>
      <label class="flex items-center gap-2 text-xs text-slate-600 cursor-pointer" title="Убрать любой фон модели на время снимка — небо, землю и фон в белый">
        <input type="checkbox" :checked="sketch.white_bg === true" @change="upd('white_bg', $event.target.checked)" />
        белый фон
      </label>
    </div>
    <MixinCropEditor v-if="editing" :src="editing.data_url" :name="editing.name || editing.id"
      :crop="editing.crop || null" :rotation="editing.rotation || 0"
      @cancel="editing = null" @save="onEditorSave" />
    <BoxEditor v-if="boxScene !== null" :src="thumbs[boxScene] || ''" :name="sceneName(boxScene)"
      :boxes="sceneBoxes(boxScene)"
      @cancel="boxScene = null" @save="onSceneBoxesSave" />
    <BoxEditor v-if="boxMixin" :src="boxMixinSrc" :name="boxMixin.name || boxMixin.id"
      :boxes="boxMixin.boxes || []"
      @cancel="boxMixin = null" @save="onMixinBoxesSave" />
  </div>
</template>

<script setup>
import { computed, onBeforeUnmount, ref } from 'vue'
import MixinCropEditor from './MixinCropEditor.vue'
import MixinThumb from './MixinThumb.vue'
import BoxEditor from './BoxEditor.vue'
const active = ref('scenes')
const tabs = [
  { id: 'scenes', label: 'Сцены' },
  { id: 'mixins', label: 'Примеси' },
  { id: 'settings', label: 'Настройки' }
]
const props = defineProps({
  scenes: { type: Array, default: () => [] },
  selected: { type: Array, default: () => [] },
  thumbs: { type: Object, default: () => ({}) },
  enabledScenes: { type: Boolean, default: true },
  enabledMixins: { type: Boolean, default: true },
  sketch: { type: Object, default: () => ({ source: 'hd', preset: '1024x768', thin_lines: true, hide_dims: true, autocrop: false, white_bg: false }) },
  items: { type: Array, default: () => [] },
  settings: { type: Object, default: () => ({}) }
})
const emit = defineEmits(['toggle', 'refresh', 'sync-view', 'toggle-enabled-scenes', 'toggle-enabled-mixins',
  'update-sketch', 'preview-dims', 'add-data', 'add-path', 'toggle-mixin', 'caption', 'neg', 'role', 'weight', 'move', 'delete',
  'transform', 'update-settings', 'save-scene-boxes', 'save-mixin-boxes', 'delete-all'])

// Подтверждение удаления всех примесей в самой кнопке: нативный confirm()
// в HtmlDialog недоступен.
const confirmAll = ref(false)
let confirmTimer = null
function askDeleteAll() {
  clearTimeout(confirmTimer)
  if (!confirmAll.value) {
    confirmAll.value = true
    confirmTimer = setTimeout(() => { confirmAll.value = false }, 3000)
    return
  }
  confirmAll.value = false
  emit('delete-all')
}
onBeforeUnmount(() => clearTimeout(confirmTimer))

// Разрешение превью считаем по ширине колонки: пиксели экрана
// (карточка × devicePixelRatio), кламп 320..1600, шаг 50, высота 4:3.
const PREVIEW_MIN_W = 320
const PREVIEW_MAX_W = 1600
const PREVIEW_STEP = 50
let listEl = null
let listObserver = null
let lastPreviewW = 0
function setListEl(el) {
  if (listObserver) { listObserver.disconnect(); listObserver = null }
  listEl = el || null
  if (!listEl) return
  listObserver = new ResizeObserver(() => {
    if (!listEl) return
    const cardW = listEl.clientWidth - 24 // p-3: паддинги по 12px
    if (cardW <= 0) return
    const raw = Math.ceil(cardW * (Number(window.devicePixelRatio) || 1))
    const w = Math.min(PREVIEW_MAX_W, Math.max(PREVIEW_MIN_W, Math.ceil(raw / PREVIEW_STEP) * PREVIEW_STEP))
    if (w === lastPreviewW) return
    lastPreviewW = w
    emit('preview-dims', { w, h: Math.round((w * 3) / 4) })
  })
  listObserver.observe(listEl)
}
onBeforeUnmount(() => { if (listObserver) listObserver.disconnect() })

const sketchPresets = ['800x600', '1024x768', '1280x960']
function upd(key, value) {
  emit('update-sketch', { ...props.sketch, [key]: value })
}
const editing = ref(null)
const showOrig = ref({})
function hasTransform(m) {
  return !!m.crop || numRot(m.rotation) !== 0
}
function onEditorSave({ crop, rotation }) {
  if (!editing.value) return
  const item = editing.value
  editing.value = null
  emit('transform', { item, crop, rotation })
}
function cropStyle(c) {
  if (!c) return {}
  return {
    left: ((Number(c.x) || 0) * 100) + '%',
    top: ((Number(c.y) || 0) * 100) + '%',
    width: ((Number(c.w) || 0) * 100) + '%',
    height: ((Number(c.h) || 0) * 100) + '%'
  }
}
// ── Рамки с описанием (сцены и примеси) ─────────────────────────────
function boxStyle(b) {
  if (!b) return {}
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
const boxScene = ref(null)
const boxMixin = ref(null)
const boxMixinSrc = ref('')
function sceneByIndex(i) {
  return props.scenes.find((s) => s.index === i) || null
}
function sceneName(i) {
  return (sceneByIndex(i) || {}).name || ('Сцена #' + i)
}
function sceneBoxes(i) {
  return (sceneByIndex(i) || {}).boxes || []
}
function openSceneBoxes(s) {
  if (!props.thumbs[s.index]) return
  boxScene.value = s.index
}
function onSceneBoxesSave({ index, boxes }) {
  boxScene.value = null
  emit('save-scene-boxes', { index, boxes })
}
async function openMixinBoxes(m) {
  boxMixinSrc.value = await transformedUrl(m)
  boxMixin.value = m
}
function onMixinBoxesSave({ item, boxes }) {
  boxMixin.value = null
  emit('save-mixin-boxes', { item, boxes })
}
// Рамки примеси живут в системе координат картинки ПОСЛЕ crop+rotation
// (так же рисуются на job-копии в Ruby). Готовим такой data-url на canvas.
function transformedUrl(m) {
  return new Promise((resolve) => {
    const rot = numRot(m.rotation)
    if (!m.data_url || (!m.crop && rot === 0)) { resolve(m.data_url || ''); return }
    const img = new Image()
    img.onload = () => {
      const c = m.crop || { x: 0, y: 0, w: 1, h: 1 }
      const sx = Math.round((Number(c.x) || 0) * img.naturalWidth)
      const sy = Math.round((Number(c.y) || 0) * img.naturalHeight)
      const sw = Math.max(1, Math.round((Number(c.w) || 1) * img.naturalWidth))
      const sh = Math.max(1, Math.round((Number(c.h) || 1) * img.naturalHeight))
      const ang = (Number(m.rotation) || 0) * Math.PI / 180
      const cos = Math.abs(Math.cos(ang))
      const sin = Math.abs(Math.sin(ang))
      const dw = Math.max(1, Math.round(sw * cos + sh * sin))
      const dh = Math.max(1, Math.round(sw * sin + sh * cos))
      const cv = document.createElement('canvas')
      cv.width = dw
      cv.height = dh
      const ctx = cv.getContext('2d')
      if (!ctx) { resolve(m.data_url || ''); return }
      ctx.translate(dw / 2, dh / 2)
      ctx.rotate(ang)
      ctx.drawImage(img, sx, sy, sw, sh, -sw / 2, -sh / 2, sw, sh)
      try { resolve(cv.toDataURL('image/png')) } catch { resolve(m.data_url || '') }
    }
    img.onerror = () => resolve(m.data_url || '')
    img.src = m.data_url
  })
}
function numRot(r) {
  const f = Number(r)
  return Number.isFinite(f) ? Math.round(f) : 0
}
function fmtRot(r) {
  const n = numRot(r)
  return (n > 0 ? '+' : '') + n
}
function onFiles(e) {
  const files = Array.from(e.target?.files || [])
  e.target.value = ''
  files.forEach(async (f) => {
    const shrunk = await shrinkFile(f)
    if (shrunk) {
      emit('add-data', { data_url: shrunk, name: f.name })
      return
    }
    const rd = new FileReader()
    rd.onload = () => emit('add-data', { data_url: String(rd.result || ''), name: f.name })
    rd.readAsDataURL(f)
  })
}
const MIXIN_MAX_SIDE = 1024
function blobToDataUrl(blob) {
  return new Promise((resolve) => {
    const rd = new FileReader()
    rd.onload = () => resolve(String(rd.result || ''))
    rd.onerror = () => resolve('')
    rd.readAsDataURL(blob)
  })
}
function loadViaImage(file) {
  return new Promise((resolve, reject) => {
    const url = URL.createObjectURL(file)
    const img = new Image()
    img.onload = () => {
      URL.revokeObjectURL(url)
      resolve({ width: img.naturalWidth || img.width, draw: (ctx, w, h) => ctx.drawImage(img, 0, 0, w, h) })
    }
    img.onerror = (err) => {
      URL.revokeObjectURL(url)
      reject(err)
    }
    img.src = url
  })
}
async function shrinkFile(f) {
  try {
    if (!f || !String(f.type || '').startsWith('image/')) return ''
    let w0 = 0
    let h0 = 0
    let draw = null
    if ('createImageBitmap' in window) {
      const bmp = await createImageBitmap(f)
      w0 = bmp.width
      h0 = bmp.height
      draw = (ctx, w, h) => ctx.drawImage(bmp, 0, 0, w, h)
    } else {
      const loaded = await loadViaImage(f)
      w0 = loaded.width
      h0 = loaded.height
      draw = loaded.draw
    }
    if (!w0 || !h0) return ''
    const scale = Math.min(1, MIXIN_MAX_SIDE / Math.max(w0, h0))
    if (scale >= 1) return ''
    const w = Math.max(1, Math.round(w0 * scale))
    const h = Math.max(1, Math.round(h0 * scale))
    const canvas = document.createElement('canvas')
    canvas.width = w
    canvas.height = h
    const ctx = canvas.getContext('2d')
    if (!ctx) return ''
    draw(ctx, w, h)
    const outType = f.type === 'image/png' ? 'image/png' : (f.type === 'image/webp' ? 'image/webp' : 'image/jpeg')
    const blob = await new Promise((res) => canvas.toBlob(res, outType, 0.85))
    if (!blob) return ''
    return await blobToDataUrl(blob)
  } catch {
    return ''
  }
}
function numWeight(w) {
  const f = Number(w)
  return Number.isFinite(f) ? Math.min(2, Math.max(0.1, f)) : 1
}
function fmtWeight(w) {
  const f = numWeight(w)
  return Number.isInteger(f) ? String(f) : String(Math.round(f * 100) / 100)
}
const activeCount = computed(() => props.items.filter((m) => m.active !== false).length)
</script>
