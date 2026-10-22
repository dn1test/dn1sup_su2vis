<template>
  <div class="border rounded-lg bg-white overflow-hidden flex flex-col min-h-0 max-h-full">
    <div class="shrink-0 px-3 py-2 border-b bg-slate-50 flex items-center justify-between">
      <span class="font-medium flex items-center gap-2">
        <label class="flex items-center gap-1 text-xs font-normal text-slate-500 cursor-pointer" title="Выключить колонку: генерация без примесей (только сцена/промпт)">
          <input type="checkbox" :checked="enabled" @change="emit('toggle-enabled', $event.target.checked)" />
        </label>
        Примеси
      </span>
      <span class="flex items-center gap-2">
        <span class="text-xs text-slate-500">{{ activeCount }}/{{ items.length }}</span>
        <button class="px-1.5 py-0.5 text-xs border rounded hover:bg-slate-100" :class="showSettings ? 'bg-slate-200' : ''"
          title="Настройки примесей: дефолты новых карточек" @click="showSettings = !showSettings">⚙</button>
      </span>
    </div>
    <div v-if="showSettings" class="shrink-0 p-3 space-y-2 border-b bg-slate-50/50" :class="!enabled ? 'opacity-50 pointer-events-none' : ''">
      <div class="text-xs font-medium">Для новых примесей</div>
      <div class="text-xs text-slate-500">Подставляется в каждую новую карточку, старые не трогает.</div>
      <label class="block">
        <span class="text-xs text-slate-500">Что брать</span>
        <select :value="settings.mixins_default_role || 'auto'" @change="upd('mixins_default_role', $event.target.value)"
          class="mt-1 w-full border rounded p-1.5 text-xs bg-white">
          <option value="auto">авто — всё</option>
          <option value="style">стиль/настроение</option>
          <option value="material">материал/фактура</option>
          <option value="light">свет/цвет</option>
          <option value="object">объект/деталь</option>
        </select>
      </label>
      <label class="block">
        <span class="text-xs text-slate-500">Где учитывать</span>
        <select :value="settings.mixins_default_apply || 'both'" @change="upd('mixins_default_apply', $event.target.value)"
          class="mt-1 w-full border rounded p-1.5 text-xs bg-white">
          <option value="both">превью+финал</option>
          <option value="preview">только превью</option>
          <option value="final">только финал</option>
        </select>
      </label>
    </div>
    <div class="shrink-0 p-3 pb-0 space-y-2" :class="!enabled ? 'opacity-50 pointer-events-none' : ''">
      <div class="flex gap-2">
        <label class="flex-1 px-3 py-2 rounded bg-slate-900 text-white text-xs text-center cursor-pointer hover:bg-slate-700">
          Добавить…
          <input ref="fileInput" type="file" accept="image/png,image/jpeg,image/webp" multiple class="hidden" @change="onFiles" />
        </label>
        <button class="px-3 py-2 rounded border text-xs hover:bg-slate-100" title="Выбрать файл с диска через SketchUp"
          @click="emit('add-path')">Из файла…</button>
      </div>
      <div v-if="!items.length" class="text-xs text-slate-500">Картинки-референсы для примеси + подпись «что взять». Учитываются в превью и финале.</div>
      <div v-else class="text-xs text-slate-500">Галочка — участвует в генерации. Подпись дописывается к промпту. Порядок = порядок в запросе.</div>
    </div>
    <div class="flex-1 min-h-0 overflow-y-auto scroll-slim p-3 space-y-2" :class="!enabled ? 'opacity-50 pointer-events-none' : ''">
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
          <span v-if="m.crop" class="shrink-0 text-[10px] px-1.5 py-0.5 rounded bg-amber-100 text-amber-900" title="В генерацию уйдёт только выделение">выделение</span>
          <span v-if="numRot(m.rotation) !== 0" class="shrink-0 text-[10px] px-1.5 py-0.5 rounded bg-sky-100 text-sky-900" :title="'Поворот ' + fmtRot(m.rotation) + '°'">{{ fmtRot(m.rotation) }}°</span>
        </div>
        <div class="p-2 space-y-1">
          <div class="flex items-center gap-1">
            <input type="checkbox" :checked="m.active !== false" @change="emit('toggle', m)" />
            <span class="text-xs font-medium truncate flex-1" :title="m.name">{{ m.name || m.id }}</span>
            <button class="px-1.5 py-0.5 text-xs border rounded hover:bg-slate-100 disabled:opacity-30" :disabled="idx === 0"
              title="Выше (сильнее в запросе)" @click="emit('move', { item: m, dir: -1 })">▲</button>
            <button class="px-1.5 py-0.5 text-xs border rounded hover:bg-slate-100 disabled:opacity-30" :disabled="idx === items.length - 1"
              title="Ниже" @click="emit('move', { item: m, dir: 1 })">▼</button>
          </div>
          <div class="flex gap-1">
            <select :value="m.role || 'auto'" @change="emit('role', { item: m, role: $event.target.value })"
              class="flex-1 border rounded p-1 text-xs" title="Что взять с референса">
              <option value="auto">авто — всё</option>
              <option value="style">стиль/настроение</option>
              <option value="material">материал/фактура</option>
              <option value="light">свет/цвет</option>
              <option value="object">объект/деталь</option>
            </select>
            <select :value="m.apply_to || 'both'" @change="emit('apply', { item: m, apply_to: $event.target.value })"
              class="border rounded p-1 text-xs" title="Где учитывать">
              <option value="both">превью+финал</option>
              <option value="preview">только превью</option>
              <option value="final">только финал</option>
            </select>
          </div>
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
    <MixinCropEditor v-if="editing" :src="editing.data_url" :name="editing.name || editing.id"
      :crop="editing.crop || null" :rotation="editing.rotation || 0"
      @cancel="editing = null" @save="onEditorSave" />
  </div>
</template>

<script setup>
import { computed, ref } from 'vue'
import MixinCropEditor from './MixinCropEditor.vue'
import MixinThumb from './MixinThumb.vue'
const showSettings = ref(false)
const props = defineProps({ items: { type: Array, default: () => [] }, enabled: { type: Boolean, default: true },
  settings: { type: Object, default: () => ({}) } })
const emit = defineEmits(['add-data', 'add-path', 'toggle', 'caption', 'neg', 'role', 'weight', 'apply', 'move', 'delete', 'transform', 'toggle-enabled', 'update-settings'])
function upd(key, value) {
  emit('update-settings', { [key]: value })
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
// Примеси уходят в студию base64 в JSON: большие фото с телефона
// раздувают запрос и VRAM. Жмём на canvas до 1024 по длинной,
// пропорции сохраняем, формат исходника держим (прозрачность PNG цела).
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
