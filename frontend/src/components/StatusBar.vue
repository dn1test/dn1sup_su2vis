<template>
  <footer class="relative shrink-0 px-4 py-2 border-t bg-white flex items-center gap-2 text-xs"
    :class="tone === 'error' ? 'text-red-700' : tone === 'ok' ? 'text-green-700' : tone === 'work' ? 'text-amber-700' : 'text-slate-600'">
    <span class="inline-block w-2 h-2 rounded-full shrink-0"
      :class="tone === 'error' ? 'bg-red-500' : tone === 'ok' ? 'bg-green-500' : tone === 'work' ? 'bg-amber-500 animate-pulse' : 'bg-slate-400'"></span>
    <span class="truncate flex-1 min-w-0">{{ text }}</span>
    <button class="shrink-0 max-w-[45%] truncate px-2 py-1 border rounded hover:bg-slate-100 text-slate-700"
      :title="'Показать весь журнал (' + log.length + ')'" @click="toggle">
      <span class="text-slate-400">≣ {{ log.length }} ·</span> {{ live }}
    </button>
    <div v-if="open" class="fixed inset-0 z-40" @click="open = false"></div>
    <div v-if="open"
      class="absolute bottom-full right-2 mb-2 z-50 w-[420px] max-w-[90vw] max-h-[320px] flex flex-col border rounded-lg bg-white shadow-xl text-slate-700">
      <div class="shrink-0 px-3 py-2 border-b bg-slate-50 flex items-center justify-between gap-2 rounded-t-lg">
        <span class="font-medium text-xs">Журнал ({{ log.length }})</span>
        <span class="flex gap-2">
          <button class="px-2 py-1 text-xs border rounded bg-white hover:bg-slate-100" @click="$emit('load-log')">Обновить</button>
          <button class="px-2 py-1 text-xs border rounded bg-white hover:bg-slate-100" @click="$emit('clear-log')">Очистить</button>
          <button class="px-2 py-1 text-xs border rounded bg-white hover:bg-slate-100" @click="open = false">✕</button>
        </span>
      </div>
      <div class="flex-1 min-h-0 overflow-y-auto scroll-slim p-3 space-y-1">
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
    </div>
  </footer>
</template>

<script setup>
import { ref } from 'vue'
defineProps({
  text: { type: String, default: '' },
  tone: { type: String, default: 'idle' },
  log: { type: Array, default: () => [] },
  live: { type: String, default: '' }
})
const emit = defineEmits(['load-log', 'clear-log'])
const open = ref(false)
function toggle() {
  open.value = !open.value
  if (open.value) emit('load-log')
}
function shortFile(f) {
  const s = String(f || '')
  return s.length > 40 ? '…' + s.slice(-39) : s
}
</script>
