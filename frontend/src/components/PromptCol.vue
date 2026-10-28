<template>
  <div class="border rounded-lg bg-white overflow-hidden flex flex-col min-h-0 max-h-full min-w-0">
    <div class="shrink-0 px-3 py-2 border-b bg-slate-50 font-medium">Промпт</div>
    <div class="flex-1 min-h-0 overflow-y-auto scroll-slim p-3 space-y-3">
      <label class="block">
        <span class="text-xs text-slate-500">Промпт</span>
        <textarea :value="modelValue.prompt" @input="upd('prompt', $event.target.value)" rows="5"
          class="mt-1 w-full border rounded p-2 text-xs"></textarea>
      </label>
      <div class="flex items-center justify-between gap-2">
        <span class="text-xs font-medium">Капшн апсемплера</span>
        <button class="px-2 py-1 text-xs border rounded hover:bg-slate-100 disabled:opacity-40"
          :disabled="enhancePreview && enhancePreview.loading" @click="emit('enhance-preview')">👁 Показать</button>
      </div>
      <div class="text-xs text-slate-400">Студия сама улучшает промпт апсемплером — как она видит эскиз. Подсмотри и учти в промпте вручную.</div>
      <div class="border rounded p-2 space-y-1">
        <div v-if="enhancePreview && enhancePreview.loading" class="text-xs text-slate-500">Апсемплер пишет капшн… (~5–10с)</div>
        <div v-else-if="enhancePreview && enhancePreview.error" class="text-xs text-red-600">{{ enhancePreview.error }}</div>
        <pre v-else-if="enhancePreview && enhancePreview.text" class="text-[11px] whitespace-pre-wrap max-h-48 overflow-y-auto bg-slate-50 border rounded p-2">{{ enhancePreview.text }}</pre>
        <div v-else class="text-xs text-slate-400">Что реально уйдёт в модель.</div>
      </div>
      <label class="block">
        <span class="flex items-center justify-between text-xs"><span class="font-medium">Шаги (steps)</span><span>{{ stepsVal }}</span></span>
        <input type="range" min="8" max="30" step="1" :value="stepsVal"
          @change="updSave('steps', +$event.target.value)" class="w-full accent-slate-900" />
      </label>
      <div class="text-xs text-slate-400">Число шагов денойза. Больше = детальнее и дольше. Guidance зафиксирован 1.0.</div>
      <label class="block">
        <span class="flex items-center justify-between text-xs"><span class="font-medium">Свобода модели</span><span>{{ modelValue.strength }}</span></span>
        <input type="range" min="0.05" max="1" step="0.05" :value="modelValue.strength"
          @change="updSave('strength', +$event.target.value)" class="w-full accent-slate-900" />
      </label>
      <div class="text-xs text-slate-400">Ниже = точнее линии: 0.05 — калька, выше — свободнее.</div>
      <label class="flex items-start gap-2">
        <input type="checkbox" class="mt-0.5" :checked="modelValue.geometry_lock !== false" @change="updSave('geometry_lock', $event.target.checked)" />
        <span class="text-xs"><span class="font-medium">Замок геометрии</span><br />
        <span class="text-slate-400">Запрет двигать стены/окна/двери и менять камеру.</span></span>
      </label>
      <div>
        <span class="text-xs text-slate-500">Режим размера</span>
        <div class="mt-1 flex gap-1">
          <button v-for="m in MODES" :key="m.id" @click="updSave('final_mode', m.id)"
            class="flex-1 px-1 py-1 text-xs border rounded"
            :class="modeVal === m.id ? 'bg-slate-900 text-white' : 'hover:bg-slate-100'"
            :title="m.title">{{ m.label }}</button>
        </div>
      </div>
      <label class="block" :class="modeVal !== 'custom' ? 'opacity-50' : ''">
        <span class="text-xs text-slate-500">Соотношение сторон</span>
        <select :value="ratioVal" @change="setRatio($event.target.value)" :disabled="modeVal !== 'custom'"
          class="mt-1 w-full border rounded p-1.5 text-xs bg-white">
          <option v-for="r in RATIOS" :key="r.id" :value="r.id">{{ r.label }}</option>
          <option v-if="ratioVal === 'custom'" value="custom" disabled>Свои пропорции…</option>
        </select>
      </label>
      <div :class="modeVal !== 'custom' ? 'opacity-50 pointer-events-none' : ''">
        <span class="text-xs text-slate-500">Resolution</span>
        <div class="text-xs text-slate-400">Размер в пикселях. Больше = детальнее, но жрёт VRAM; потолок студии 2048 по длинной. Вторая сторона подтягивается сама — пропорции сохраняются.</div>
        <div class="mt-1 flex gap-1">
          <div class="flex-1 min-w-0 grid grid-cols-2 gap-2">
            <select :value="Number(modelValue.final_w)" @change="updSaveWH('final_w', +$event.target.value)"
              class="w-full border rounded p-1.5 text-xs bg-white">
              <option v-if="!RES_OPTIONS.includes(Number(modelValue.final_w))" :value="Number(modelValue.final_w)">↔ {{ Number(modelValue.final_w) }}</option>
              <option v-for="px in RES_OPTIONS" :key="'w' + px" :value="px">↔ {{ px }}</option>
            </select>
            <select :value="Number(modelValue.final_h)" @change="updSaveWH('final_h', +$event.target.value)"
              class="w-full border rounded p-1.5 text-xs bg-white">
              <option v-if="!RES_OPTIONS.includes(Number(modelValue.final_h))" :value="Number(modelValue.final_h)">↕ {{ Number(modelValue.final_h) }}</option>
              <option v-for="px in RES_OPTIONS" :key="'h' + px" :value="px">↕ {{ px }}</option>
            </select>
          </div>
          <button class="shrink-0 px-2 py-1 text-xs border rounded hover:bg-slate-100 bg-white"
            title="Поменять ширину и высоту местами" @click="swapWH">⇄</button>
        </div>
      </div>
      <div>
        <div class="text-xs text-slate-500 mb-1">Картинок за раз (1–4)</div>
        <div class="flex gap-1">
          <button v-for="n in 4" :key="n" @click="updSave('preview_variants', n)"
            class="flex-1 px-1 py-1 text-xs border rounded"
            :class="variantsVal === n ? 'bg-slate-900 text-white' : 'hover:bg-slate-100'">{{ n }}</button>
        </div>
      </div>
      <label class="flex items-start gap-2">
        <input type="checkbox" class="mt-0.5" :checked="modelValue.preview_random_seeds !== false" @change="updSave('preview_random_seeds', $event.target.checked)" />
        <span class="text-xs"><span class="font-medium">Случайные сиды</span><br />
        <span class="text-slate-400">Вкл — каждый вариант со своим случайным сидом. Выкл — сиды по порядку от базового.</span></span>
      </label>
      <label class="block">
        <span class="text-xs text-slate-500">Seed (пусто = случайно)</span>
        <div class="mt-1 flex gap-1">
          <input type="text" inputmode="numeric" placeholder="Random if empty"
            :value="modelValue.seed < 0 ? '' : modelValue.seed" @input="updSeed($event.target.value)"
            class="flex-1 min-w-0 border rounded p-1.5" />
          <button class="shrink-0 px-2 py-1 text-xs border rounded hover:bg-slate-100 bg-white"
            title="Сбросить seed в случайный" @click="updSave('seed', -1)">🎲</button>
        </div>
      </label>
      <div class="text-xs text-slate-400">Seed — зерно случайности. Пусто = случайно каждый раз; число = повтор даёт попиксельно тот же результат.</div>
      <details class="border rounded">
        <summary class="px-2 py-1 cursor-pointer text-xs text-slate-600">⚙ Advanced</summary>
        <div class="p-2 space-y-3">
          <div class="text-xs text-slate-600 break-all border rounded p-2 bg-slate-50">Папка: {{ modelValue.out_dir }}</div>
          <label v-if="modelValue.project_state !== 'ready'" class="block">
            <span class="text-xs text-slate-500">Папка для рендеров</span>
            <div class="mt-1 flex gap-1">
              <input :value="modelValue.out_dir" @input="upd('out_dir', $event.target.value)"
                class="flex-1 min-w-0 border rounded p-1.5 text-xs" />
              <button class="shrink-0 px-2 py-1 text-xs border rounded hover:bg-slate-100" @click="emit('select-out-dir')">Выбрать…</button>
              <button class="shrink-0 px-2 py-1 text-xs border rounded hover:bg-slate-100" @click="emit('open-out-dir')">Открыть</button>
            </div>
          </label>
          <div v-else class="block">
            <span class="text-xs text-slate-500">Папка для рендеров (папка проекта)</span>
            <div class="mt-1 flex gap-1">
              <input :value="modelValue.out_dir" readonly
                class="flex-1 min-w-0 border rounded p-1.5 text-xs bg-slate-50" />
              <button class="shrink-0 px-2 py-1 text-xs border rounded hover:bg-slate-100" @click="emit('open-out-dir')">Открыть</button>
            </div>
          </div>
          <label class="block">
            <span class="text-xs text-slate-500">Имя файла: {scene} {seed} {date} {suffix}</span>
            <input :value="modelValue.name_template" @input="upd('name_template', $event.target.value)"
              class="mt-1 w-full border rounded p-1.5 text-xs" />
          </label>
          <div class="grid grid-cols-2 gap-2">
            <label class="block">
              <span class="text-xs text-slate-500">Суффикс</span>
              <input :value="modelValue.suffix" @input="upd('suffix', $event.target.value)"
                class="mt-1 w-full border rounded p-1.5" />
            </label>
            <label class="block">
              <span class="text-xs text-slate-500">Расширение</span>
              <select :value="modelValue.ext" @change="updSave('ext', $event.target.value)"
                class="mt-1 w-full border rounded p-1.5">
                <option value="jpg">jpg</option>
                <option value="png">png</option>
              </select>
            </label>
          </div>
          <label class="block">
            <span class="text-xs text-slate-500">Память (Memory)</span>
            <select :value="modelValue.memory_mode || 'balanced'" @change="updSave('memory_mode', $event.target.value)"
              class="mt-1 w-full border rounded p-1.5 text-xs bg-white">
              <option value="auto">auto</option>
              <option value="fast">fast</option>
              <option value="balanced">balanced</option>
              <option value="low_vram">low_vram</option>
            </select>
          </label>
          <div class="flex gap-2">
            <button class="flex-1 px-3 py-2 rounded bg-slate-900 text-white text-xs hover:bg-slate-700" @click="emit('save')">Сохранить</button>
          </div>
          <div class="text-xs text-slate-400">Подключение (URL, ключ, модель) — кнопка «Подключение» в шапке.</div>
        </div>
      </details>
    </div>
  </div>
</template>

<script setup>
import { computed } from 'vue'
const props = defineProps({ modelValue: { type: Object, required: true }, enhancePreview: { type: Object, default: null } })
const emit = defineEmits(['update:modelValue', 'save', 'enhance-preview', 'select-out-dir', 'open-out-dir'])
const RES_OPTIONS = [256, 512, 768, 1024, 1280, 1536, 2048]
const MODES = [
  { id: 'sketch', label: 'Эскиз', title: 'Точный размер эскиза сцены' },
  { id: '1k', label: '1K', title: 'Пропорции эскиза, длинная сторона 1024' },
  { id: '2k', label: '2K', title: 'Пропорции эскиза, длинная сторона 2048' },
  { id: 'custom', label: 'Свой', title: 'Точный размер: соотношение + разрешение ниже' }
]
const RATIOS = [
  { id: '1:1', label: 'Квадрат 1:1' },
  { id: '4:3', label: 'Альбом 4:3' },
  { id: '3:4', label: 'Портрет 3:4' },
  { id: '3:2', label: 'Фото 3:2' },
  { id: '2:3', label: 'Фото 2:3' },
  { id: '16:9', label: 'Широкий 16:9' },
  { id: '9:16', label: 'Портрет 9:16' }
]
const RATIO_VALS = { '1:1': 1, '4:3': 4 / 3, '3:4': 3 / 4, '3:2': 3 / 2, '2:3': 2 / 3, '16:9': 16 / 9, '9:16': 9 / 16 }
function upd(key, value) {
  emit('update:modelValue', { ...props.modelValue, [key]: value })
}
function updSave(key, value) {
  emit('update:modelValue', { ...props.modelValue, [key]: value })
  emit('save')
}
function updSeed(v) {
  const s = String(v ?? '').trim()
  const n = parseInt(s, 10)
  upd('seed', s === '' || Number.isNaN(n) ? -1 : n)
}
const stepsVal = computed(() => {
  const n = Number(props.modelValue.steps) || 16
  return Math.min(30, Math.max(8, n))
})
const variantsVal = computed(() => Number(props.modelValue.preview_variants) || 1)
const modeVal = computed(() => {
  const m = String(props.modelValue.final_mode || 'sketch')
  return ['sketch', '1k', '2k', 'custom'].includes(m) ? m : 'sketch'
})
const ratioVal = computed(() => {
  const w = Number(props.modelValue.final_w)
  const h = Number(props.modelValue.final_h)
  if (w > 0 && h > 0) {
    const r = w / h
    for (const [id, v] of Object.entries(RATIO_VALS)) {
      if (Math.abs(r - v) / v < 0.005) return id
    }
  }
  return 'custom'
})
function setRatio(id) {
  if (id === 'custom' || !RATIO_VALS[id]) return
  const [a, b] = id.split(':').map(Number)
  const curW = Number(props.modelValue.final_w) || 2048
  const curH = Number(props.modelValue.final_h) || 1536
  // Только пропорции: размер берём из текущей длинной стороны.
  const L = Math.min(2048, Math.max(256, Math.max(curW, curH)))
  let w, h
  if (a >= b) { w = L; h = snap16(L * b / a) } else { h = L; w = snap16(L * a / b) }
  emit('update:modelValue', { ...props.modelValue, final_mode: 'custom', final_w: w, final_h: h })
  emit('save')
}
function snap16(x) {
  return Math.min(2048, Math.max(256, Math.round(x / 16) * 16))
}
function updSaveWH(key, v) {
  const other = key === 'final_w' ? 'final_h' : 'final_w'
  const patch = { final_mode: 'custom', [key]: v }
  // Пропорции не сбрасываем: вторую сторону тянем за первой по старому
  // отношению, с привязкой к шагу Resolution.
  const curW = Number(props.modelValue.final_w) || 0
  const curH = Number(props.modelValue.final_h) || 0
  if (curW > 0 && curH > 0) {
    const ratio = key === 'final_w' ? curH / curW : curW / curH
    patch[other] = nearestRes(Math.round(v * ratio))
  }
  emit('update:modelValue', { ...props.modelValue, ...patch })
  emit('save')
}
function nearestRes(x) {
  const c = Math.min(2048, Math.max(256, x))
  let best = RES_OPTIONS[0]
  let bd = Infinity
  for (const o of RES_OPTIONS) {
    const d = Math.abs(o - c)
    if (d < bd) { bd = d; best = o }
  }
  return best
}
function swapWH() {
  emit('update:modelValue', { ...props.modelValue, final_mode: 'custom',
    final_w: props.modelValue.final_h, final_h: props.modelValue.final_w })
  emit('save')
}
</script>
