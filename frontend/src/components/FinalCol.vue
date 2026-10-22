<template>
  <div class="border rounded-lg bg-white overflow-hidden flex flex-col min-h-0 max-h-full">
    <div class="shrink-0 px-3 py-2 border-b bg-slate-50 flex items-center justify-between">
      <span class="font-medium">Финал</span>
      <span class="flex items-center gap-2">
        <span v-if="job" class="text-xs px-2 py-0.5 rounded border"
          :class="job.status === 'done' ? 'bg-green-50 text-green-700' : job.status === 'cancelled' ? 'bg-slate-100 text-slate-600' : job.status === 'error' ? 'bg-red-50 text-red-700' : 'bg-amber-50 text-amber-700'">
          {{ job.status }} {{ progressText }}
        </span>
        <button class="px-1.5 py-0.5 text-xs border rounded hover:bg-slate-100" :class="showSettings ? 'bg-slate-200' : ''"
          title="Настройки финала: размер и сила доработки" @click="showSettings = !showSettings">⚙</button>
      </span>
    </div>
    <div v-if="showSettings" class="shrink-0 p-3 space-y-2 border-b bg-slate-50/50">
      <div class="text-xs font-medium">Финальный размер</div>
      <div class="text-xs text-slate-400">Aspect ratio — пропорции кадра. «Размер эскиза» держит композицию сцены, остальные режут/тянут под стандарт.</div>
      <label class="block">
        <span class="text-xs text-slate-500">Aspect ratio</span>
        <div class="mt-1 flex gap-1">
          <select :value="aspectVal" @change="setAspect($event.target.value)"
            class="flex-1 min-w-0 border rounded p-1.5 text-xs bg-white">
            <option value="sketch">Размер эскиза</option>
            <option value="1:1">Square (1:1)</option>
            <option value="4:3">Landscape (4:3)</option>
            <option value="3:4">Portrait (3:4)</option>
            <option value="16:9">Wide (16:9)</option>
            <option v-if="aspectVal === '__custom'" value="__custom" disabled>Свой размер…</option>
          </select>
          <button class="shrink-0 px-2 py-1 text-xs border rounded hover:bg-slate-100 bg-white"
            title="Поменять ширину и высоту местами" @click="swapWH">⇄</button>
        </div>
      </label>
      <div>
        <span class="text-xs text-slate-500">Resolution</span>
        <div class="text-xs text-slate-400">Размер в пикселях. Больше = детальнее, но жрёт VRAM; потолок студии 2048 по длинной. Выше эскиза детали додумываются.</div>
        <div class="mt-1 grid grid-cols-2 gap-2">
          <select :value="Number(settings.final_w)" @change="updWH('final_w', +$event.target.value)"
            class="w-full border rounded p-1.5 text-xs bg-white">
            <option v-for="px in RES_OPTIONS" :key="'w' + px" :value="px">↔ {{ px }}</option>
          </select>
          <select :value="Number(settings.final_h)" @change="updWH('final_h', +$event.target.value)"
            class="w-full border rounded p-1.5 text-xs bg-white">
            <option v-for="px in RES_OPTIONS" :key="'h' + px" :value="px">↕ {{ px }}</option>
          </select>
        </div>
      </div>
      <label class="block">
        <span class="flex items-center justify-between text-xs"><span class="font-medium">Доработка финала</span><span>{{ settings.final_strength }}</span></span>
        <input type="range" min="0.05" max="1" step="0.05" :value="settings.final_strength"
          @change="upd('final_strength', +$event.target.value)" class="w-full accent-slate-900" />
      </label>
      <div class="text-xs text-slate-400">Сила доделки превью в финал: 0.2–0.35 держит линии, выше — свободнее.</div>
    </div>
    <div class="shrink-0 p-3 pb-0 space-y-2">
      <div class="flex gap-2">
        <button :disabled="!canRun || busy" @click="$emit('final-all')"
          class="flex-1 px-3 py-2 rounded bg-emerald-600 text-white text-xs disabled:opacity-40 hover:bg-emerald-500">
          Все превью в финал ({{ finalLabel }})
        </button>
        <button v-if="busy" @click="$emit('stop')"
          class="px-3 py-2 rounded bg-red-600 text-white text-xs hover:bg-red-500">Стоп</button>
      </div>
      <div v-if="job && job.status === 'error'" class="text-xs text-red-600">{{ job.error }}</div>
      <div v-if="job && job.status === 'cancelled'" class="text-xs text-slate-500">Остановлено, сохранено {{ results.length }}.</div>
      <div v-if="!results.length" class="text-xs text-slate-500">Финал дорабатывает картинку превью (сила — под шестерёнкой ⚙).</div>
    </div>
    <div class="flex-1 min-h-0 overflow-y-auto scroll-slim p-3 space-y-2">
      <div v-for="r in results" :key="r.file || (r.scene + '-' + r.seed + '-' + (r.variant || 0))" class="relative border rounded overflow-hidden">
        <button class="absolute top-1 right-1 z-10 w-6 h-6 text-xs rounded-full bg-black/60 text-white hover:bg-red-600"
          title="Удалить файл с диска" @click.stop="$emit('delete', r)">✕</button>
        <button class="block w-full text-left" @click="$emit('view', r)" title="Открыть в полном размере">
          <img v-if="r.data_url" :src="r.data_url" class="w-full aspect-[4/3] object-cover bg-slate-200" />
          <div v-else-if="r.load_error" class="w-full aspect-[4/3] bg-red-50 flex flex-col items-center justify-center gap-1 p-2 text-center">
            <span class="text-xs text-red-600 break-all">{{ r.load_error }}</span>
            <span class="px-2 py-1 text-xs border rounded bg-white hover:bg-slate-100" @click.stop="$emit('retry', r)">Повторить</span>
          </div>
          <div v-else class="w-full aspect-[4/3] bg-slate-200 flex items-center justify-center text-xs text-slate-500">загружаю…</div>
        </button>
        <div class="px-2 py-1">
          <div class="text-xs font-medium">Сцена #{{ r.scene ?? 'промпт' }}<span v-if="r.variant"> · вар.{{ r.variant + 1 }}</span> · seed {{ r.seed }} · {{ r.width }}×{{ r.height }}</div>
          <div class="text-xs text-emerald-700 break-all">{{ shortFile(r.file) }}</div>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup>
import { computed, ref } from 'vue'
const showSettings = ref(false)
const props = defineProps({
  job: { type: Object, default: null },
  results: { type: Array, default: () => [] },
  busy: { type: Boolean, default: false },
  canRun: { type: Boolean, default: false },
  finalLabel: { type: String, default: '' },
  settings: { type: Object, default: () => ({}) }
})
const emit = defineEmits(['final-all', 'stop', 'view', 'delete', 'retry', 'update-settings'])
const RES_OPTIONS = [512, 768, 1024, 1280, 1536, 2048]
const ASPECT_SIZES = { '1:1': [1024, 1024], '4:3': [1280, 960], '3:4': [960, 1280], '16:9': [1536, 864] }
// Текущий аспект из final_w/final_h; sketch и прочие режимы — «Свой размер…».
const aspectVal = computed(() => {
  if (props.settings.final_mode !== 'custom') {
    return props.settings.final_mode === 'sketch' ? 'sketch' : '__custom'
  }
  const w = Number(props.settings.final_w)
  const h = Number(props.settings.final_h)
  for (const [k, [aw, ah]] of Object.entries(ASPECT_SIZES)) {
    if (w === aw && h === ah) return k
  }
  return '__custom'
})
function upd(key, value) {
  emit('update-settings', { [key]: value })
}
function setAspect(v) {
  if (v === '__custom') return
  if (v === 'sketch') { upd('final_mode', 'sketch'); return }
  const [w, h] = ASPECT_SIZES[v]
  emit('update-settings', { final_mode: 'custom', final_w: w, final_h: h })
}
function updWH(key, v) {
  emit('update-settings', { final_mode: 'custom', [key]: v })
}
function swapWH() {
  emit('update-settings', { final_mode: 'custom',
    final_w: props.settings.final_h, final_h: props.settings.final_w })
}
const progressText = computed(() => {
  const p = props.job?.progress
  return p && p.total ? `${p.done || 0}/${p.total}` : ''
})
function shortFile(f) {
  const s = String(f || '')
  return s.length > 40 ? '…' + s.slice(-39) : s
}
</script>
