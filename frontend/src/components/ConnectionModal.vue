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
          <span class="text-xs text-slate-500">Команда запуска студии (headless, без GUI)</span>
          <input :value="modelValue.unsloth_cmd || 'unsloth'" @input="upd('unsloth_cmd', $event.target.value)"
            class="mt-1 w-full border rounded p-1.5 text-xs" placeholder="unsloth" />
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
        <label class="flex items-center gap-2 text-xs text-slate-700">
          <input type="checkbox" :checked="modelValue.unsloth_autostart !== false"
            @change="upd('unsloth_autostart', $event.target.checked)" />
          Запускать студию автоматически при открытии панели
        </label>
        <div class="border rounded p-2 space-y-2 text-xs">
          <div class="flex items-center justify-between gap-2">
            <span class="font-medium">Модель: flux-3-image-klein</span>
            <button class="px-2 py-1 border rounded hover:bg-slate-50 disabled:opacity-40"
              :disabled="modelsLoading" @click="$emit('refresh-models')">
              {{ modelsLoading ? 'Опрос…' : 'Обновить' }}
            </button>
          </div>
          <div class="text-slate-600">steps 4 · guidance 1.0 · workflow auto · память balanced · финал ≤ 2048</div>
          <div v-if="modelsError" class="text-red-600">{{ modelsError }}</div>
          <div v-else-if="modelsLoading" class="text-slate-500">Опрашиваю варианты квантования…</div>
          <label v-else-if="quantOptions.length" class="block">
            <span class="text-slate-500">Квантование GGUF (● — скачан, ◆ — загружен сейчас)</span>
            <select :value="shownGguf" @change="stage($event.target.value)"
              class="mt-1 w-full border rounded p-1.5 text-xs">
              <option v-for="q in quantOptions" :key="q.filename" :value="q.filename">
                {{ q.downloaded ? '● ' : '' }}{{ q.current ? '◆ ' : '' }}{{ q.quant }}{{ q.downloaded ? '' : ' (скачается при применении)' }}
              </option>
            </select>
            <div class="mt-1 text-[11px] text-slate-500 break-all">{{ shownGguf }}</div>
          </label>
          <button v-if="canApply" @click="applyStaged"
            class="w-full px-3 py-2 rounded bg-emerald-700 text-white text-xs hover:bg-emerald-600">
            Применить квант: {{ stagedGguf }}
          </button>
          <div v-if="appliedMsg" class="border rounded p-2 bg-green-50 text-green-800">{{ appliedMsg }}</div>
          <div v-else-if="!quantOptions.length" class="text-slate-400">Нет данных о квантах — нажмите «Обновить». Текущий файл: {{ modelValue.unsloth_gguf }}</div>
        </div>
        <div v-if="currentStatus" class="text-xs border rounded p-2 bg-slate-50 space-y-0.5">
          <div class="font-medium">Сейчас в студии:</div>
          <div class="break-all text-slate-600">{{ currentStatus }}</div>
        </div>
        <details class="border rounded" open>
          <summary class="px-2 py-1 cursor-pointer text-xs text-slate-600">⚙ Advanced — load-time тюнинг (применяется при следующей загрузке)</summary>
          <div class="p-2 space-y-2">
            <div class="text-[11px] text-slate-500">Меняют загрузку модели, не отдельную генерацию. После смены — переоткройте панель или дождитесь перезагрузки модели.</div>
            <div class="grid grid-cols-2 gap-2">
              <div class="block">
                <span class="text-xs text-slate-500">Family</span>
                <div class="mt-1 w-full border rounded p-1.5 text-xs bg-slate-50 text-slate-600">FLUX.3-KLEIN (auto)</div>
              </div>
              <div class="block">
                <span class="text-xs text-slate-500">On model selection</span>
                <div class="mt-1 w-full border rounded p-1.5 text-xs bg-slate-50 text-slate-600">Download and load</div>
              </div>
            </div>
            <div class="text-[11px] text-slate-500">Family — семейство модели, зафиксировано на klein. On model selection — скачать квант при выборе и загрузить.</div>
            <div class="grid grid-cols-2 gap-2">
              <label class="block">
                <span class="text-xs text-slate-500">Engine</span>
                <select :value="modelValue.studio_engine || 'auto'" @change="upd('studio_engine', $event.target.value)"
                  class="mt-1 w-full border rounded p-1.5 text-xs bg-white">
                  <option value="auto">Auto</option>
                  <option value="diffusers">diffusers</option>
                </select>
              </label>
              <label class="block">
                <span class="text-xs text-slate-500">Speed</span>
                <select :value="modelValue.studio_speed || 'auto'" @change="upd('studio_speed', $event.target.value)"
                  class="mt-1 w-full border rounded p-1.5 text-xs bg-white">
                  <option value="auto">Auto</option>
                  <option value="default">Default</option>
                  <option value="fast">Fast</option>
                  <option value="balanced">Balanced</option>
                  <option value="quality">Quality</option>
                </select>
              </label>
            </div>
            <div class="text-[11px] text-slate-500">Engine — бэкенд инференса. Speed — пресет скорость/качество.</div>
            <div class="grid grid-cols-2 gap-2">
              <label class="block">
                <span class="text-xs text-slate-500">Precision</span>
                <select :value="modelValue.studio_precision || 'auto'" @change="upd('studio_precision', $event.target.value)"
                  class="mt-1 w-full border rounded p-1.5 text-xs bg-white">
                  <option value="auto">Auto (fastest)</option>
                  <option value="off">Off</option>
                  <option value="fp16">FP16</option>
                  <option value="bf16">BF16</option>
                  <option value="int8">INT8</option>
                  <option value="fp32">FP32</option>
                </select>
              </label>
              <label class="block">
                <span class="text-xs text-slate-500">Text encoder precision</span>
                <select :value="modelValue.studio_text_encoder_precision || 'default'" @change="upd('studio_text_encoder_precision', $event.target.value)"
                  class="mt-1 w-full border rounded p-1.5 text-xs bg-white">
                  <option value="default">Default</option>
                  <option value="auto">Auto</option>
                  <option value="int8">INT8</option>
                  <option value="fp16">FP16</option>
                  <option value="bf16">BF16</option>
                  <option value="fp32">FP32</option>
                </select>
              </label>
            </div>
            <div class="text-[11px] text-slate-500">Precision — точность трансформера (выше = чуть лучше свет/градиенты, но больше VRAM). Text encoder — точность понимания промпта (ниже = хуже слушается длинный промпт).</div>
            <div class="grid grid-cols-2 gap-2">
              <label class="block">
                <span class="text-xs text-slate-500">Attention</span>
                <select :value="modelValue.studio_attention || 'auto'" @change="upd('studio_attention', $event.target.value)"
                  class="mt-1 w-full border rounded p-1.5 text-xs bg-white">
                  <option value="auto">Auto</option>
                  <option value="cudnn">cuDNN</option>
                  <option value="flash">Flash</option>
                  <option value="sdpa">SDPA</option>
                  <option value="sage">Sage</option>
                </select>
              </label>
              <label class="block">
                <span class="text-xs text-slate-500">Step cache</span>
                <select :value="modelValue.studio_step_cache || 'auto'" @change="upd('studio_step_cache', $event.target.value)"
                  class="mt-1 w-full border rounded p-1.5 text-xs bg-white">
                  <option value="auto">Auto</option>
                  <option value="on">On</option>
                  <option value="off">Off</option>
                </select>
              </label>
            </div>
            <div class="text-[11px] text-slate-500">Attention — реализация внимания (на качество почти не влияет, решает скорость/VRAM). Step cache — кеш шагов: быстрее, ценой микропотери точности (на 4 шагах klein выигрыш мал).</div>
            <label class="block">
              <span class="text-xs text-slate-500">Text encoder file(s)</span>
              <div class="mt-1 w-full border rounded p-1.5 text-xs bg-slate-50 text-slate-500 break-all">../text_encoders/clip_l.safetensors (студия)</div>
            </label>
            <label class="block">
              <span class="text-xs text-slate-500">VAE file</span>
              <div class="mt-1 w-full border rounded p-1.5 text-xs bg-slate-50 text-slate-500 break-all">../vae/ae.safetensors (студия)</div>
            </label>
            <div class="text-[11px] text-slate-500">Пути к кастомным файлам — только в студии, сюда не выносим: легко сломать генерацию.</div>
            <label class="block">
              <span class="text-xs text-slate-500">Memory</span>
              <select :value="modelValue.memory_mode || 'balanced'" @change="upd('memory_mode', $event.target.value)"
                class="mt-1 w-full border rounded p-1.5 text-xs bg-white">
                <option value="auto">Auto</option>
                <option value="fast">Fast</option>
                <option value="balanced">Balanced</option>
                <option value="low_vram">Low VRAM</option>
              </select>
            </label>
            <div class="text-[11px] text-slate-500">Memory — как делить веса GPU/RAM (balanced = скорость почти как resident, но заметно меньше VRAM).</div>
            <label class="flex items-center justify-between gap-2 text-xs text-slate-700">
              <span>CPU offload <span class="text-slate-400">— сгружать часть в RAM: влезет 2K на слабой карте, но медленнее</span></span>
              <input type="checkbox" :checked="modelValue.studio_cpu_offload !== false"
                @change="upd('studio_cpu_offload', $event.target.checked)" />
            </label>
            <label class="flex items-center justify-between gap-2 text-xs text-slate-700">
              <span>Allow oversized generations <span class="text-slate-400">— генерить, даже если оценка VRAM против (риск OOM)</span></span>
              <input type="checkbox" :checked="modelValue.allow_oversized !== false"
                @change="upd('allow_oversized', $event.target.checked)" />
            </label>
            <label class="flex items-center justify-between gap-2 text-xs text-slate-700">
              <span>Live preview <span class="text-slate-400">— живой денойз-процент в статусбаре (только показ)</span></span>
              <input type="checkbox" :checked="modelValue.studio_live_preview !== false"
                @change="upd('studio_live_preview', $event.target.checked)" />
            </label>
            <div v-if="loadedBuild" class="text-[11px] border rounded p-2 bg-slate-50 space-y-0.5">
              <div class="font-medium text-xs">Loaded build:</div>
              <div class="break-all text-slate-600">{{ loadedBuild }}</div>
            </div>
          </div>
        </details>
        <div v-if="pipelineCaps" class="text-xs border rounded p-2 bg-slate-50 space-y-0.5">
          <div class="font-medium">Возможности image-пайплайна:</div>
          <div class="break-all text-slate-600">{{ pipelineCaps }}</div>
        </div>
        <div class="flex gap-2">
          <button class="flex-1 px-3 py-2 rounded bg-slate-900 text-white text-xs hover:bg-slate-700" @click="$emit('save')">Сохранить</button>
          <button class="flex-1 px-3 py-2 rounded border text-xs hover:bg-slate-50" @click="$emit('check')">Проверить студию</button>
        </div>
        <button class="w-full px-3 py-2 rounded border border-emerald-700 text-emerald-800 text-xs hover:bg-emerald-50"
          @click="$emit('ensure')">Запустить студию (headless, без GUI)</button>
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
const emit = defineEmits(['update:modelValue', 'save', 'check', 'ensure', 'refresh-models', 'close'])
const showKey = ref(false)
const stagedGguf = ref('')
const appliedMsg = ref('')
function upd(key, value) {
  if (key === 'unsloth_gguf') stagedGguf.value = ''
  emit('update:modelValue', { ...props.modelValue, [key]: value })
}
// Варианты квантования klein из моста (models[0].variants).
const quantOptions = computed(() => {
  const m = (props.models || [])[0] || {}
  const cur = (m.current_gguf || m.gguf_file || props.modelValue.unsloth_gguf || '').trim()
  const arr = Array.isArray(m.variants) ? m.variants : []
  return arr.filter((v) => v && v.filename).map((v) => ({
    filename: String(v.filename),
    quant: String(v.quant || v.filename),
    downloaded: !!v.downloaded,
    current: String(v.filename) === cur
  }))
})
const shownGguf = computed(() => stagedGguf.value || (props.modelValue.unsloth_gguf || ''))
const canApply = computed(() => !!stagedGguf.value && stagedGguf.value !== (props.modelValue.unsloth_gguf || ''))
function stage(filename) {
  appliedMsg.value = ''
  stagedGguf.value = (filename && filename !== (props.modelValue.unsloth_gguf || '')) ? filename : ''
}
function applyStaged() {
  if (!canApply.value) return
  const f = stagedGguf.value
  stagedGguf.value = ''
  appliedMsg.value = `Прописан квант ${f} (steps 4, guidance 1.0) — нажмите Сохранить`
  emit('update:modelValue', { ...props.modelValue, unsloth_gguf: f, steps: 4, guidance: 1.0 })
}
const currentStatus = computed(() => {
  const st = props.status
  if (!st || !st.ok) return ''
  return st.text || ''
})
// Возможности image-пайплайна из сырого /api/inference/images/status.
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
// Loaded build: что реально загружено в студии (трансформер/текст-энкодер/память/внимание).
const loadedBuild = computed(() => {
  const c = props.caps
  if (!c || typeof c !== 'object') return ''
  const bits = []
  const gguf = c.gguf_filename || c.gguf_file || ''
  if (gguf) bits.push(`Transformer ${gguf} (GGUF as-is)`)
  else if (c.repo_id) bits.push(`Transformer ${c.repo_id}`)
  if (c.text_encoder_precision) bits.push(`Text encoder ${c.text_encoder_precision}`)
  if (c.memory_mode) bits.push(`Memory ${c.memory_mode}`)
  if (c.attention) bits.push(`Attention ${c.attention}`)
  if (c.engine) bits.push(`Engine ${c.engine}`)
  if (c.precision) bits.push(`Precision ${c.precision}`)
  return bits.join(' · ')
})
</script>
