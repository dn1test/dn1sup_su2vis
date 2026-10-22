<template>
  <div class="border rounded-lg bg-white overflow-hidden flex flex-col min-h-0 max-h-full">
    <div class="shrink-0 px-3 py-2 border-b bg-slate-50 flex gap-1">
      <button @click="tab = 'settings'"
        class="flex-1 px-2 py-1 text-xs rounded"
        :class="tab === 'settings' ? 'bg-slate-900 text-white' : 'hover:bg-slate-200'">5 · Настройки</button>
      <button @click="tab = 'log'; $emit('load-log')"
        class="flex-1 px-2 py-1 text-xs rounded"
        :class="tab === 'log' ? 'bg-slate-900 text-white' : 'hover:bg-slate-200'">Журнал ({{ log.length }})</button>
    </div>
    <div v-if="tab === 'log'" class="flex-1 min-h-0 overflow-y-auto scroll-slim p-3 space-y-1">
      <div class="flex gap-2">
        <button class="px-2 py-1 text-xs border rounded hover:bg-slate-100" @click="$emit('load-log')">Обновить</button>
        <button class="px-2 py-1 text-xs border rounded hover:bg-slate-100" @click="$emit('clear-log')">Очистить</button>
      </div>
      <div v-if="!log.length" class="text-xs text-slate-500">Пока пусто.</div>
      <div v-for="(e, i) in log" :key="i" class="text-[11px] leading-tight border-b last:border-0 py-0.5"
        :class="e.status === 'error' ? 'text-red-700' : e.event === 'job_done' ? 'font-medium' : 'text-slate-600'">
        <span class="text-slate-400">{{ e.time }}</span>
        <span v-if="e.event === 'job_start'"> ▸ {{ e.kind }}: сцены {{ (e.scenes || []).join(',') }}, seed {{ e.seed }}</span>
        <span v-else-if="e.event === 'scene_done'"> · сцена #{{ e.scene }}<span v-if="e.variant">/в.{{ e.variant + 1 }}</span>, seed {{ e.seed }}, {{ e.size }}, {{ e.gen_s }}с<span v-if="e.file"> → {{ shortFile(e.file) }}</span></span>
        <span v-else-if="e.event === 'job_done'"> ■ {{ e.status }} за {{ e.total_s }}с<span v-if="e.error">: {{ e.error }}</span></span>
        <span v-else> {{ e.event }}</span>
      </div>
    </div>
    <div v-show="tab === 'settings'" class="flex-1 min-h-0 overflow-y-auto scroll-slim p-3 space-y-3">
      <div class="border rounded p-2 text-xs bg-slate-50">
        <div class="text-slate-600 break-all">Папка: {{ modelValue.out_dir }}</div>
      </div>
      <label class="block">
        <span class="text-xs text-slate-500">Промпт</span>
        <textarea :value="modelValue.prompt" @input="upd('prompt', $event.target.value)" rows="5"
          class="mt-1 w-full border rounded p-2 text-xs"></textarea>
      </label>
      <div class="flex items-center justify-between gap-2">
        <span class="text-xs font-medium">Enhance prompt</span>
        <div class="flex items-center gap-2">
          <button class="px-2 py-1 text-xs border rounded hover:bg-slate-100 disabled:opacity-40"
            :disabled="enhancePreview && enhancePreview.loading" @click="$emit('enhance-preview')">✨ Preview</button>
          <label class="relative inline-flex cursor-pointer items-center" title="Улучшить промпт (FLUX-апсемплер)">
            <input type="checkbox" class="peer sr-only" :checked="modelValue.enhance_prompt" @change="upd('enhance_prompt', $event.target.checked)" />
            <span class="block h-5 w-9 rounded-full bg-slate-300 transition-colors peer-checked:bg-emerald-500"></span>
            <span class="absolute left-0.5 top-0.5 h-4 w-4 rounded-full bg-white shadow transition-transform peer-checked:translate-x-4"></span>
          </label>
        </div>
      </div>
      <div class="text-xs text-slate-400">Улучшить промпт (FLUX-апсемплер): что реально уйдёт в модель.</div>
      <div class="border rounded p-2 space-y-2">
        <div class="flex items-center justify-between">
          <span class="text-xs font-medium">Предпросмотр Enhance</span>
        </div>
        <div v-if="enhancePreview && enhancePreview.loading" class="text-xs text-slate-500">Апсемплер пишет капшн… (~5–10с)</div>
        <div v-else-if="enhancePreview && enhancePreview.error" class="text-xs text-red-600">{{ enhancePreview.error }}</div>
        <pre v-else-if="enhancePreview && enhancePreview.text" class="text-[11px] whitespace-pre-wrap max-h-48 overflow-y-auto bg-slate-50 border rounded p-2">{{ enhancePreview.text }}</pre>
        <div v-else class="text-xs text-slate-400">Как тумблер Preview в студии: что реально уйдёт в модель.</div>
      </div>
      <div class="grid grid-cols-2 gap-2">
        <label class="block">
          <span class="text-xs text-slate-500">Seed</span>
          <input type="text" inputmode="numeric" placeholder="Random if empty"
            :value="modelValue.seed < 0 ? '' : modelValue.seed" @input="updSeed($event.target.value)"
            class="mt-1 w-full border rounded p-1.5" />
        </label>
        <label class="flex items-end gap-2 pb-1">
          <input type="checkbox" :checked="modelValue.seed_locked" @change="upd('seed_locked', $event.target.checked)" />
          <span class="text-xs">Замок seed</span>
        </label>
      </div>
      <div class="space-y-2">
        <div class="text-xs font-medium">Финальный размер</div>
        <label class="block">
          <span class="text-xs text-slate-500">Aspect ratio</span>
          <div class="mt-1 flex gap-1">
            <select :value="aspectVal" @change="setAspect($event.target.value)"
              class="flex-1 min-w-0 border rounded p-1.5 text-xs">
              <option value="sketch">Размер эскиза</option>
              <option value="1:1">Square (1:1)</option>
              <option value="4:3">Landscape (4:3)</option>
              <option value="3:4">Portrait (3:4)</option>
              <option value="16:9">Wide (16:9)</option>
              <option v-if="aspectVal === '__custom'" value="__custom" disabled>Свой размер…</option>
            </select>
            <button class="shrink-0 px-2 py-1 text-xs border rounded hover:bg-slate-100"
              title="Поменять ширину и высоту местами" @click="swapWH">⇄</button>
          </div>
        </label>
        <div>
          <span class="text-xs text-slate-500">Resolution</span>
          <div class="mt-1 grid grid-cols-2 gap-2">
            <select :value="Number(modelValue.final_w)" @change="updWH('final_w', +$event.target.value)"
              class="w-full border rounded p-1.5 text-xs">
              <option v-for="px in RES_OPTIONS" :key="'w' + px" :value="px">↔ {{ px }}</option>
            </select>
            <select :value="Number(modelValue.final_h)" @change="updWH('final_h', +$event.target.value)"
              class="w-full border rounded p-1.5 text-xs">
              <option v-for="px in RES_OPTIONS" :key="'h' + px" :value="px">↕ {{ px }}</option>
            </select>
          </div>
        </div>
        <label class="block">
          <span class="flex items-center justify-between text-xs"><span class="font-medium">Доработка финала</span><span>{{ modelValue.final_strength }}</span></span>
          <input type="range" min="0.05" max="1" step="0.05" :value="modelValue.final_strength"
            @input="upd('final_strength', +$event.target.value)" class="w-full accent-slate-900" />
        </label>
      </div>
      <div class="space-y-2">
        <label class="block">
          <span class="flex items-center justify-between text-xs"><span class="font-medium">Steps</span><span>{{ modelValue.steps }}</span></span>
          <input type="range" min="1" max="8" step="1" :value="modelValue.steps"
            @input="upd('steps', +$event.target.value)" class="w-full accent-slate-900" />
        </label>
        <label class="block">
          <span class="flex items-center justify-between text-xs"><span class="font-medium">Guidance</span><span>{{ modelValue.guidance }}</span></span>
          <input type="range" min="0" max="5" step="0.5" :value="modelValue.guidance"
            @input="upd('guidance', +$event.target.value)" class="w-full accent-slate-900" />
        </label>
        <label class="block">
          <span class="flex items-center justify-between text-xs"><span class="font-medium">Batch size</span><span>{{ modelValue.preview_variants }}</span></span>
          <input type="range" min="1" max="4" step="1" :value="Number(modelValue.preview_variants) || 1"
            @input="upd('preview_variants', +$event.target.value)" class="w-full accent-slate-900" />
        </label>
      </div>
      <details class="border rounded">
        <summary class="px-2 py-1 cursor-pointer text-xs text-slate-600">⚙ Advanced</summary>
        <div class="p-2 space-y-3">
      <label v-if="modelValue.project_state !== 'ready'" class="block">
        <span class="text-xs text-slate-500">Папка для рендеров</span>
        <div class="mt-1 flex gap-1">
          <input :value="modelValue.out_dir" @input="upd('out_dir', $event.target.value)"
            class="flex-1 min-w-0 border rounded p-1.5 text-xs" />
          <button class="shrink-0 px-2 py-1 text-xs border rounded hover:bg-slate-100" @click="$emit('select-out-dir')">Выбрать…</button>
          <button class="shrink-0 px-2 py-1 text-xs border rounded hover:bg-slate-100" @click="$emit('open-out-dir')">Открыть</button>
        </div>
      </label>
      <div v-else class="block">
        <span class="text-xs text-slate-500">Папка для рендеров (папка проекта)</span>
        <div class="mt-1 flex gap-1">
          <input :value="modelValue.out_dir" readonly
            class="flex-1 min-w-0 border rounded p-1.5 text-xs bg-slate-50" />
          <button class="shrink-0 px-2 py-1 text-xs border rounded hover:bg-slate-100" @click="$emit('open-out-dir')">Открыть</button>
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
          <select :value="modelValue.ext" @change="upd('ext', $event.target.value)"
            class="mt-1 w-full border rounded p-1.5">
            <option value="jpg">jpg</option>
            <option value="png">png</option>
          </select>
        </label>
      </div>
      <label class="block">
        <span class="text-xs text-slate-500">Strength: {{ modelValue.strength }}</span>
        <input type="range" min="0.05" max="1" step="0.05" :value="modelValue.strength"
          @input="upd('strength', +$event.target.value)" class="w-full" />
      </label>
      <div class="grid grid-cols-2 gap-2">
        <label class="block">
          <span class="text-xs text-slate-500">Память</span>
          <select :value="modelValue.memory_mode" @change="upd('memory_mode', $event.target.value)"
            class="mt-1 w-full border rounded p-1.5">
            <option value="auto">auto</option>
            <option value="fast">fast</option>
            <option value="balanced">balanced</option>
            <option value="low_vram">low_vram</option>
          </select>
        </label>
        <label class="flex items-end gap-2 pb-1">
          <input type="checkbox" :checked="modelValue.allow_oversized" @change="upd('allow_oversized', $event.target.checked)" />
          <span class="text-xs">Allow oversized</span>
        </label>
      </div>
      <div class="grid grid-cols-2 gap-2">
        <label class="block">
          <span class="text-xs text-slate-500">Hires-fix финала</span>
          <select :value="String(modelValue.final_upscale)" @change="upd('final_upscale', +$event.target.value)"
            class="mt-1 w-full border rounded p-1.5 text-xs">
            <option value="0">выкл</option>
            <option value="1.5">1.5×</option>
            <option value="2">2×</option>
          </select>
        </label>
        <label class="block">
          <span class="text-xs text-slate-500">Workflow</span>
          <select :value="modelValue.workflow" @change="upd('workflow', $event.target.value)"
            class="mt-1 w-full border rounded p-1.5 text-xs">
            <option value="auto">авто</option>
            <option value="reference">reference</option>
          </select>
        </label>
      </div>
      <div class="flex gap-2">
        <button class="flex-1 px-3 py-2 rounded bg-slate-900 text-white text-xs hover:bg-slate-700" @click="$emit('save')">Сохранить</button>
      </div>
      <div class="text-xs text-slate-400">Подключение (URL, ключ, модель) — кнопка «Подключение» в шапке.</div>
      <div v-if="status" class="text-xs" :class="status.ok ? 'text-green-700' : 'text-red-600'">{{ status.text }}</div>
        </div>
      </details>
    </div>
  </div>
</template>

<script setup>
import { computed, ref } from 'vue'
const tab = ref('settings')
const props = defineProps({ modelValue: { type: Object, required: true }, status: { type: Object, default: null }, log: { type: Array, default: () => [] }, enhancePreview: { type: Object, default: null } })
const emit = defineEmits(['update:modelValue', 'save', 'check', 'load-log', 'clear-log', 'enhance-preview', 'select-out-dir', 'open-out-dir'])
const RES_OPTIONS = [512, 768, 1024, 1280, 1536, 2048]
const ASPECT_SIZES = { '1:1': [1024, 1024], '4:3': [1280, 960], '3:4': [960, 1280], '16:9': [1536, 864] }
// Текущий аспект из final_w/final_h; 1k/2k и прочие режимы — «Свой размер…».
const aspectVal = computed(() => {
  if (props.modelValue.final_mode !== 'custom') {
    return props.modelValue.final_mode === 'sketch' ? 'sketch' : '__custom'
  }
  const w = Number(props.modelValue.final_w)
  const h = Number(props.modelValue.final_h)
  for (const [k, [aw, ah]] of Object.entries(ASPECT_SIZES)) {
    if (w === aw && h === ah) return k
  }
  return '__custom'
})
function upd(key, value) {
  emit('update:modelValue', { ...props.modelValue, [key]: value })
}
function setAspect(v) {
  if (v === '__custom') return
  if (v === 'sketch') { upd('final_mode', 'sketch'); return }
  const [w, h] = ASPECT_SIZES[v]
  emit('update:modelValue', { ...props.modelValue, final_mode: 'custom', final_w: w, final_h: h })
}
function updWH(key, v) {
  emit('update:modelValue', { ...props.modelValue, final_mode: 'custom', [key]: v })
}
function swapWH() {
  emit('update:modelValue', { ...props.modelValue, final_mode: 'custom',
    final_w: props.modelValue.final_h, final_h: props.modelValue.final_w })
}
// Пустое поле = случайно (-1), как «Random if empty» в студии.
function updSeed(v) {
  const s = String(v ?? '').trim()
  const n = parseInt(s, 10)
  upd('seed', s === '' || Number.isNaN(n) ? -1 : n)
}
function shortFile(f) {
  const s = String(f || '')
  return s.length > 40 ? '…' + s.slice(-39) : s
}
</script>
