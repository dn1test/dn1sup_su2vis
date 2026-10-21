<template>
  <footer class="shrink-0 px-4 py-2 border-t bg-white flex items-center gap-2 text-xs"
    :class="tone === 'error' ? 'text-red-700' : tone === 'ok' ? 'text-green-700' : tone === 'work' ? 'text-amber-700' : 'text-slate-600'">
    <span class="inline-block w-2 h-2 rounded-full"
      :class="tone === 'error' ? 'bg-red-500' : tone === 'ok' ? 'bg-green-500' : tone === 'work' ? 'bg-amber-500 animate-pulse' : 'bg-slate-400'"></span>
    <span class="truncate">{{ text }}</span>
  </footer>
</template>

<script setup>
defineProps({ text: { type: String, default: '' }, tone: { type: String, default: 'idle' } })
</script>
