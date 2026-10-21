<template>
  <div class="border rounded-lg bg-white overflow-hidden flex flex-col min-h-0 max-h-full">
    <div class="shrink-0 px-3 py-2 border-b bg-slate-50 flex items-center justify-between">
      <span class="font-medium">2 · Превью</span>
      <span v-if="job" class="text-xs px-2 py-0.5 rounded border"
        :class="job.status === 'done' ? 'bg-green-50 text-green-700' : job.status === 'cancelled' ? 'bg-slate-100 text-slate-600' : job.status === 'error' ? 'bg-red-50 text-red-700' : 'bg-amber-50 text-amber-700'">
        {{ job.status }} {{ progressText }}
      </span>
    </div>
    <div class="shrink-0 p-3 pb-0 space-y-2">
      <div>
        <div class="text-xs text-slate-500 mb-1">Размер превью</div>
        <div class="text-xs">256px по ширине — минимум студии, всегда</div>
      </div>
      <div>
        <div class="text-xs text-slate-500 mb-1">Вариантов (1–4)</div>
        <div class="flex gap-1">
          <button v-for="n in 4" :key="n" @click="$emit('variants', n)"
            class="flex-1 px-1 py-1 text-xs border rounded"
            :class="variants === n ? 'bg-slate-900 text-white' : 'hover:bg-slate-100'">{{ n }}</button>
        </div>
      </div>
      <div class="flex gap-2">
        <button :disabled="!canRun || busy" @click="$emit('preview')"
          class="flex-1 px-3 py-2 rounded bg-blue-600 text-white text-xs disabled:opacity-40 hover:bg-blue-500">
          Превью (256px × {{ variants }})
        </button>
        <button v-if="busy" @click="$emit('stop')"
          class="px-3 py-2 rounded bg-red-600 text-white text-xs hover:bg-red-500">Стоп</button>
      </div>
      <div v-if="job && job.status === 'error'" class="text-xs text-red-600">{{ job.error }}</div>
      <div v-if="job && job.status === 'cancelled'" class="text-xs text-slate-500">Остановлено, готовы {{ results.length }}.</div>
    </div>
    <div class="flex-1 min-h-0 overflow-y-auto scroll-slim p-3 space-y-2">
      <div v-for="r in results" :key="r.file || (r.scene + '-' + r.seed + '-' + (r.variant || 0))"
        class="relative border rounded overflow-hidden cursor-pointer hover:border-slate-400 w-full mx-auto"
        :style="{ maxWidth: (r.width || 336) + 'px' }"
        :class="selectedSeed === r.seed ? 'ring-2 ring-blue-500' : ''"
        :title="'Выбрать: seed попадёт в настройки' + paramsText(r)"
        @click="$emit('select-preview', { scene: r.scene, seed: r.seed })">
        <button class="absolute top-1 right-1 z-10 w-6 h-6 text-xs rounded-full bg-black/60 text-white hover:bg-red-600"
          title="Удалить файл с диска" @click.stop="$emit('delete', r)">✕</button>
        <img v-if="r.data_url" :src="r.data_url" class="w-full h-auto block" />
        <div v-else-if="r.load_error" class="w-full bg-red-50 flex flex-col items-center justify-center gap-1 p-2 text-center">
          <span class="text-xs text-red-600 break-all">{{ r.load_error }}</span>
          <span class="px-2 py-1 text-xs border rounded bg-white hover:bg-slate-100" @click.stop="$emit('retry', r)">Повторить</span>
        </div>
        <div v-else class="w-full bg-slate-200 flex items-center justify-center text-xs text-slate-500 py-6">загружаю…</div>
        <div class="px-2 py-1 flex items-center justify-between gap-1">
          <span class="text-xs text-slate-600 truncate min-w-0">#{{ r.scene }}<span v-if="r.variant"> · вар.{{ r.variant + 1 }}</span> · seed {{ r.seed }} · {{ r.width }}×{{ r.height }}</span>
          <button class="shrink-0 px-2 py-1 text-xs rounded bg-emerald-600 text-white hover:bg-emerald-500"
            @click.stop="$emit('final-one', { scene: r.scene, seed: r.seed })">В финал</button>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup>
import { computed } from 'vue'
const props = defineProps({
  job: { type: Object, default: null },
  results: { type: Array, default: () => [] },
  busy: { type: Boolean, default: false },
  canRun: { type: Boolean, default: false },
  variants: { type: Number, default: 1 },
  selectedSeed: { type: Number, default: null }
})
defineEmits(['variants', 'preview', 'stop', 'final-one', 'select-preview', 'delete', 'retry'])
function paramsText(r) {
  const p = []
  if (r.strength !== undefined && r.strength !== null) p.push(`сила ${r.strength}`)
  if (r.steps) p.push(`шаги ${r.steps}`)
  if (r.workflow) p.push(r.workflow)
  if (r.file) p.push(String(r.file).split(/[/\\]/).pop())
  return p.length ? ' · ' + p.join(', ') : ''
}
const progressText = computed(() => {
  const p = props.job?.progress
  return p && p.total ? `${p.done || 0}/${p.total}` : ''
})
</script>
