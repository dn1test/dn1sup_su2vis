<template>
  <div class="border rounded-lg bg-white overflow-hidden flex flex-col min-h-0 max-h-full min-w-0">
    <div class="shrink-0 px-3 py-2 border-b bg-slate-50 flex items-center justify-between">
      <span class="font-medium">Рендер</span>
      <span v-if="job" class="text-xs px-2 py-0.5 rounded border"
        :class="job.status === 'done' ? 'bg-green-50 text-green-700' : job.status === 'cancelled' ? 'bg-slate-100 text-slate-600' : job.status === 'error' ? 'bg-red-50 text-red-700' : 'bg-amber-50 text-amber-700'">
        {{ job.status }} {{ progressText }}
      </span>
    </div>
    <div class="shrink-0 p-3 pb-0 space-y-2">
      <div class="flex gap-2">
        <button :disabled="!canRun || busy" @click="emit('render')"
          class="flex-1 px-3 py-2 rounded bg-emerald-600 text-white text-xs disabled:opacity-40 hover:bg-emerald-500">
          Рендер ({{ finalLabel }})
        </button>
        <button v-if="busy" @click="emit('stop')"
          class="px-3 py-2 rounded bg-red-600 text-white text-xs hover:bg-red-500">Стоп</button>
      </div>
      <div v-if="results.length" class="flex justify-end">
        <button :disabled="busy" @click="askDeleteAll"
          class="px-2 py-1 text-xs border rounded disabled:opacity-40"
          :class="confirmAll ? 'border-red-300 bg-red-50 text-red-700 hover:bg-red-100' : 'hover:bg-slate-100'"
          :title="confirmAll ? 'Ещё раз — удалит все файлы с диска' : 'Удалить все отрендеренные файлы с диска'">
          {{ confirmAll ? 'Точно удалить все?' : `Удалить все (${results.length})` }}
        </button>
      </div>
      <div v-if="job && job.status === 'error'" class="text-xs text-red-600">{{ job.error }}</div>
      <div v-if="job && job.status === 'cancelled'" class="text-xs text-slate-500">Остановлено, сохранено {{ results.length }}.</div>
      <div v-if="!results.length" class="text-xs text-slate-500">Рендер идёт напрямую из эскиза сцены + примесей + промпта.</div>
    </div>
    <div class="flex-1 min-h-0 overflow-y-auto scroll-slim p-3 space-y-2">
      <div v-for="r in results" :key="r.file || (r.scene + '-' + r.seed + '-' + (r.variant || 0))" class="relative border rounded overflow-hidden">
        <button class="absolute top-1 right-1 z-10 w-6 h-6 text-xs rounded-full bg-black/60 text-white hover:bg-red-600"
          title="Удалить файл с диска" @click.stop="emit('delete', r)">✕</button>
        <button class="block w-full text-left" @click="emit('view', r)" title="Открыть в полном размере">
          <img v-if="r.data_url" :src="r.data_url" class="w-full aspect-[4/3] object-cover bg-slate-200" />
          <div v-else-if="r.load_error" class="w-full aspect-[4/3] bg-red-50 flex flex-col items-center justify-center gap-1 p-2 text-center">
            <span class="text-xs text-red-600 break-all">{{ r.load_error }}</span>
            <span class="px-2 py-1 text-xs border rounded bg-white hover:bg-slate-100" @click.stop="emit('retry', r)">Повторить</span>
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
import { ref, computed, onUnmounted } from 'vue'
const props = defineProps({
  job: { type: Object, default: null },
  results: { type: Array, default: () => [] },
  busy: { type: Boolean, default: false },
  canRun: { type: Boolean, default: false },
  finalLabel: { type: String, default: '' }
})
const emit = defineEmits(['render', 'stop', 'view', 'delete', 'retry', 'delete-all'])
const progressText = computed(() => {
  const p = props.job?.progress
  return p && p.total ? `${p.done || 0}/${p.total}` : ''
})
function shortFile(f) {
  const s = String(f || '')
  return s.length > 40 ? '…' + s.slice(-39) : s
}
// Подтверждение в самой кнопке: нативный confirm() в HtmlDialog недоступен.
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
onUnmounted(() => clearTimeout(confirmTimer))
</script>
