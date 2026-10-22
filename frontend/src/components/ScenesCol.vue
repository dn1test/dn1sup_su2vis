<template>
  <div class="border rounded-lg bg-white overflow-hidden flex flex-col min-h-0 max-h-full">
    <div class="shrink-0 px-3 py-2 border-b bg-slate-50 flex items-center justify-between">
      <span class="font-medium flex items-center gap-2">
        1 · Сцены SketchUp
        <label class="flex items-center gap-1 text-xs font-normal text-slate-500 cursor-pointer" title="Выключить колонку: генерация без эскиза сцены (только примеси/промпт)">
          <input type="checkbox" :checked="enabled" @change="$emit('toggle-enabled', $event.target.checked)" />
          вкл
        </label>
      </span>
      <span class="text-xs text-slate-500">{{ selected.length }}/{{ scenes.length }}</span>
    </div>
    <div class="flex-1 min-h-0 overflow-y-auto scroll-slim p-3 space-y-2" :class="!enabled ? 'opacity-50 pointer-events-none' : ''">
      <div class="flex gap-1">
        <button class="flex-1 px-2 py-1 text-xs border rounded hover:bg-slate-100" @click="$emit('refresh')">Обновить</button>
      </div>
      <div v-if="!scenes.length" class="text-xs text-slate-500">Нет сцен. Создайте сцены в модели → «Обновить».</div>
      <div v-else class="text-xs text-slate-500">Выберите одну сцену. Эскиз = сохранённый вид сцены. Покрутили камеру — жмите ⟳ на сцене.</div>
      <label v-for="s in scenes" :key="s.index"
        class="block border rounded overflow-hidden cursor-pointer hover:border-slate-400"
        :class="selected.includes(s.index) ? 'ring-2 ring-blue-500' : ''">
        <div class="flex items-center gap-2 px-2 py-1">
          <input type="radio" name="su2vis-scene" :checked="selected.includes(s.index)" @change="$emit('toggle', s.index)" />
          <span class="truncate text-xs font-medium flex-1">{{ s.name }}</span>
          <button class="px-1.5 py-0.5 text-xs border rounded hover:bg-slate-100" title="Записать текущий вид окна в сцену"
            @click.prevent="$emit('sync-view', s.index)">⟳</button>
        </div>
        <img v-if="thumbs[s.index]" :src="thumbs[s.index]" class="w-full aspect-[4/3] object-cover bg-slate-200" />
        <div v-else class="w-full aspect-[4/3] bg-slate-200 flex items-center justify-center text-xs text-slate-500">вид сцены</div>
      </label>
    </div>
  </div>
</template>

<script setup>
defineProps({
  scenes: { type: Array, default: () => [] },
  selected: { type: Array, default: () => [] },
  thumbs: { type: Object, default: () => ({}) },
  enabled: { type: Boolean, default: true }
})
defineEmits(['toggle', 'refresh', 'sync-view', 'toggle-enabled'])
</script>
