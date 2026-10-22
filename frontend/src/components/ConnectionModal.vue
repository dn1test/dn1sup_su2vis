<template>
  <div class="fixed inset-0 z-50 bg-black/60 flex items-center justify-center p-4" @click.self="$emit('close')">
    <div class="w-full max-w-md bg-white rounded-lg shadow-xl overflow-hidden">
      <div class="px-4 py-2 bg-slate-900 text-white flex items-center justify-between">
        <span class="text-sm font-medium">Подключение к студии</span>
        <button class="px-2 py-0.5 text-xs border border-slate-600 rounded hover:bg-slate-700" @click="$emit('close')">Закрыть ✕</button>
      </div>
      <div class="p-4 space-y-3 max-h-[70vh] overflow-y-auto scroll-slim">
        <label class="block">
          <span class="text-xs text-slate-500">URL студии</span>
          <input :value="modelValue.unsloth_url" @input="upd('unsloth_url', $event.target.value)"
            class="mt-1 w-full border rounded p-1.5 text-xs" placeholder="http://127.0.0.1:8888" />
        </label>
        <label class="block">
          <span class="text-xs text-slate-500">API ключ</span>
          <div class="mt-1 flex gap-1">
            <input :type="showKey ? 'text' : 'password'" :value="modelValue.unsloth_key"
              @input="upd('unsloth_key', $event.target.value)"
              class="flex-1 min-w-0 border rounded p-1.5 text-xs" placeholder="sk-unsloth-…" />
            <button class="shrink-0 px-2 py-1 text-xs border rounded hover:bg-slate-50"
              @click="showKey = !showKey">{{ showKey ? 'Скрыть' : 'Показать' }}</button>
          </div>
        </label>
        <div class="border rounded p-2 space-y-2">
          <div class="flex items-center justify-between gap-2">
            <span class="text-xs font-medium">Модель генерации картинок</span>
            <button class="px-2 py-1 text-xs border rounded hover:bg-slate-50 disabled:opacity-40"
              :disabled="modelsLoading" @click="$emit('refresh-models')">
              {{ modelsLoading ? 'Опрос…' : 'Обновить список' }}
            </button>
          </div>
          <div v-if="modelsError" class="text-xs text-red-600">{{ modelsError }}</div>
          <div v-else-if="modelsLoading" class="text-xs text-slate-500">Опрашиваю студию (GET /v1/models)…</div>
          <label v-else-if="models && models.length" class="block">
            <span class="text-xs text-slate-500">Только image-модели ({{ models.length }})</span>
            <select :value="shownId" @change="stage($event.target.value)"
              class="mt-1 w-full border rounded p-1.5 text-xs">
              <option value="" disabled>Выберите модель…</option>
              <option v-for="m in models" :key="m.id" :value="m.id">
                {{ m.loaded ? '● ' : '' }}{{ m.id }}{{ m.quant ? ' · ' + m.quant : '' }}
              </option>
            </select>
            <div class="mt-1 text-[11px] text-slate-500">● — загружена в студии сейчас. LLM, аудио и апсемплер скрыты.</div>
          </label>
          <button v-if="canApply" @click="applyStaged"
            class="w-full px-3 py-2 rounded bg-emerald-700 text-white text-xs hover:bg-emerald-600">
            Применить: {{ stagedId }} + параметры пресета
          </button>
          <div v-if="presetPreview" class="text-[11px] border rounded p-2 bg-amber-50 text-amber-900">{{ presetPreview }}</div>
          <div v-if="appliedMsg" class="text-[11px] border rounded p-2 bg-green-50 text-green-800">{{ appliedMsg }}</div>
          <div v-else class="text-xs text-slate-400">Нет image-моделей — нажмите «Обновить список». Можно вписать repo/gguf вручную ниже.</div>
          <div v-if="pickedCaps" class="text-[11px] border rounded p-2 bg-slate-50 space-y-0.5">
            <div class="font-medium text-xs">Возможности модели:</div>
            <div class="break-all text-slate-600">{{ pickedCaps }}</div>
          </div>
          <label class="block">
            <span class="text-xs text-slate-500">Репозиторий (unsloth_model)</span>
            <input :value="modelValue.unsloth_model" @input="upd('unsloth_model', $event.target.value)"
              class="mt-1 w-full border rounded p-1.5 text-xs" placeholder="unsloth/flux-3-image-klein-GGUF" />
          </label>
          <label class="block">
            <span class="text-xs text-slate-500">GGUF-файл (unsloth_gguf)</span>
            <input :value="modelValue.unsloth_gguf" @input="upd('unsloth_gguf', $event.target.value)"
              class="mt-1 w-full border rounded p-1.5 text-xs" placeholder="flux-3-image-klein-UD-Q4_K_XL.gguf" />
          </label>
        </div>
        <div v-if="currentStatus" class="text-xs border rounded p-2 bg-slate-50 space-y-0.5">
          <div class="font-medium">Сейчас в студии:</div>
          <div class="break-all text-slate-600">{{ currentStatus }}</div>
        </div>
        <div v-if="pipelineCaps" class="text-xs border rounded p-2 bg-slate-50 space-y-0.5">
          <div class="font-medium">Возможности image-пайплайна:</div>
          <div class="break-all text-slate-600">{{ pipelineCaps }}</div>
        </div>
        <div class="flex gap-2">
          <button class="flex-1 px-3 py-2 rounded bg-slate-900 text-white text-xs hover:bg-slate-700" @click="$emit('save')">Сохранить</button>
          <button class="flex-1 px-3 py-2 rounded border text-xs hover:bg-slate-50" @click="$emit('check')">Проверить студию</button>
        </div>
        <div v-if="status" class="text-xs" :class="status.ok ? 'text-green-700' : 'text-red-600'">{{ status.text }}</div>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, computed } from 'vue'
const props = defineProps({
  modelValue: { type: Object, required: true },
  status: { type: Object, default: null },
  caps: { type: Object, default: null },
  models: { type: Array, default: () => [] },
  modelsLoading: { type: Boolean, default: false },
  modelsError: { type: String, default: '' }
})
const emit = defineEmits(['update:modelValue', 'save', 'check', 'refresh-models', 'close'])
const showKey = ref(false)
const appliedMsg = ref('')
function upd(key, value) {
  if (key === 'unsloth_model' || key === 'unsloth_gguf') stagedId.value = ''
  emit('update:modelValue', { ...props.modelValue, [key]: value })
}
// Применённая в настройках модель == совпала пара repo+gguf.
const appliedId = computed(() => {
  const repo = (props.modelValue.unsloth_model || '').trim()
  const gguf = (props.modelValue.unsloth_gguf || '').trim()
  for (const m of props.models || []) {
    const id = (m.id || '').trim()
    if (!id) continue
    if (id === repo) return id
    if (gguf && (id === `${repo}:${gguf}` || id === `${repo}:${gguf.replace(/\.gguf$/, '')}`)) return id
    if (gguf && id === `${repo}/${gguf}`) return id
  }
  return ''
})
// База имени файла: последний сегмент repo без суффикса -GGUF.
function baseOf(repo) {
  return (String(repo).split('/').pop() || '').replace(/-GGUF$/i, '')
}
// Разбор id модели студии -> {repo, gguf}. Точное имя файла (gguf_file из
// gguf-variants) приоритетно: регистр и префиксы на HF строгие, 404 иначе.
// Затем квант по конвенции unsloth <base>-<quant>.gguf, затем прежнее значение.
function splitModel(id, model, fallbackGguf) {
  const quant = model && model.quant ? String(model.quant) : ''
  const exact = model && model.gguf_file ? String(model.gguf_file) : ''
  let repo = id
  let gguf = fallbackGguf || ''
  if (id.includes(':')) {
    const [r, v] = id.split(':', 2)
    repo = (r || '').trim()
    const variant = (v || '').trim()
    gguf = variant.endsWith('.gguf') && variant.includes('/')
      ? variant
      : `${baseOf(repo)}-${variant.replace(/\.gguf$/, '')}.gguf`
  } else if (id.endsWith('.gguf') && id.includes('/')) {
    const parts = id.split('/')
    gguf = parts.pop()
    repo = parts.join('/')
  } else {
    repo = id
    if (exact) {
      gguf = exact
    } else {
      const q = quant.trim().replace(/\.gguf$/, '')
      if (q) gguf = `${baseOf(repo)}-${q}.gguf`
    }
  }
  return { repo, gguf }
}
// Отложенный выбор из списка: параметры пропишутся по кнопке «Применить».
const stagedId = ref('')
const shownId = computed(() => stagedId.value || appliedId.value)
const canApply = computed(() => !!stagedId.value && stagedId.value !== appliedId.value)
function stage(id) {
  appliedMsg.value = ''
  stagedId.value = (id && id !== appliedId.value) ? id : ''
}
function applyStaged() {
  const id = stagedId.value
  if (!id || id === appliedId.value) return
  const m = (props.models || []).find((x) => x.id === id)
  const preset = (m && m.preset) || null
  const { repo, gguf } = splitModel(id, m, props.modelValue.unsloth_gguf)
  const next = { ...props.modelValue, unsloth_model: repo, unsloth_gguf: gguf }
  if (preset) {
    if (preset.steps) next.steps = preset.steps
    if (preset.guidance !== null && preset.guidance !== undefined) next.guidance = preset.guidance
    if (preset.workflow) next.workflow = preset.workflow
    if (preset.memory_mode) next.memory_mode = preset.memory_mode
    let sizeNote = ''
    if (preset.max_side) {
      const w = Number(next.final_w) || 0
      const h = Number(next.final_h) || 0
      if (w > 0 && h > 0 && Math.max(w, h) > preset.max_side) {
        const s = preset.max_side / Math.max(w, h)
        next.final_mode = 'custom'
        next.final_w = Math.max(128, Math.round(w * s / 16) * 16)
        next.final_h = Math.max(128, Math.round(h * s / 16) * 16)
        sizeNote = `, финал ${next.final_w}×${next.final_h}`
      }
    }
    appliedMsg.value = `Применены модель ${repo} + файл ${gguf} (${preset.source}): steps ${next.steps}, guidance ${next.guidance}, workflow ${next.workflow}, память ${next.memory_mode}${sizeNote} — нажмите Сохранить`
  } else {
    appliedMsg.value = `Прописаны модель ${repo} + файл ${gguf} — нажмите Сохранить`
  }
  stagedId.value = ''
  emit('update:modelValue', next)
}
// Что пропишется по кнопке для отложенного выбора (пресет из студии).
const presetPreview = computed(() => {
  const id = shownId.value
  if (!id) return ''
  const m = (props.models || []).find((x) => x.id === id)
  const p = m && m.preset
  if (!p) return ''
  const bits = [`steps ${p.steps}`, `guidance ${p.guidance}`, `workflow ${p.workflow || 'auto'}`]
  if (p.memory_mode) bits.push(`память ${p.memory_mode}`)
  if (p.max_side) bits.push(`финал ≤ ${p.max_side}`)
  if (p.vram) bits.push(p.vram)
  const { repo, gguf } = splitModel(id, m, props.modelValue.unsloth_gguf)
  const prefix = canApply.value ? 'По кнопке «Применить» пропишется' : 'Пресет'
  return `${prefix} ${p.source}: модель ${repo} + файл ${gguf}; ${bits.join(', ')}`
})
const currentStatus = computed(() => {
  const st = props.status
  if (!st || !st.ok) return ''
  return st.text || ''
})
// Возможности показанной в списке модели: task + квант из /v1/models.
const pickedCaps = computed(() => {
  const id = shownId.value
  if (!id) return ''
  const m = (props.models || []).find((x) => x.id === id)
  if (!m) return ''
  const bits = []
  if (m.task) bits.push(`task: ${m.task}`)
  if (m.quant) bits.push(`квант: ${m.quant}`)
  bits.push(m.loaded ? 'загружена' : 'не загружена')
  return bits.join(' · ')
})
// Возможности image-пайплайна из сырого /api/inference/images/status:
// семейство, workflow, пределы размера, поддержка доп. фич, движок/память.
const pipelineCaps = computed(() => {
  const c = props.caps
  if (!c || typeof c !== 'object') return ''
  const bits = []
  if (c.family) bits.push(`family: ${c.family}`)
  if (Array.isArray(c.workflows) && c.workflows.length) bits.push(`workflow: ${c.workflows.join(', ')}`)
  const maxSide = c.conditioning && c.conditioning.max_output_side
  if (maxSide) bits.push(`макс. сторона: ${maxSide}`)
  const sup = []
  if (c.supports_prompt_upsampler) sup.push('апсемплер')
  if (c.supports_lora) sup.push('LoRA')
  if (c.supports_controlnet) sup.push('ControlNet')
  if (c.supports_negative_prompt) sup.push('негатив')
  bits.push(sup.length ? `умеет: ${sup.join(', ')}` : 'без LoRA/ControlNet/негатива')
  const eng = [c.engine, c.device, c.memory_mode].filter(Boolean).join(' / ')
  if (eng) bits.push(eng)
  return bits.join(' · ')
})
</script>
