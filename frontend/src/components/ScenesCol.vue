<template>
  <div class="border rounded-lg bg-white overflow-hidden flex flex-col min-h-0 max-h-full">
    <div class="shrink-0 px-3 py-2 border-b bg-slate-50 flex items-center justify-between">
      <span class="font-medium flex items-center gap-2">
        <input type="checkbox" :checked="enabled" @change="$emit('toggle-enabled', $event.target.checked)"
          title="Выключить колонку: генерация без эскиза сцены (только примеси/промпт)" />
        1 · Сцены
      </span>
      <span class="flex items-center gap-2">
        <span class="text-xs text-slate-500">{{ selected.length }}/{{ scenes.length }}</span>
        <button class="px-1.5 py-0.5 text-xs border rounded hover:bg-slate-100" :class="showSettings ? 'bg-slate-200' : ''"
          title="Настройки эскиза-референса" @click="showSettings = !showSettings">⚙</button>
      </span>
    </div>
    <div v-if="!showSettings" class="flex-1 min-h-0 overflow-y-auto scroll-slim p-3 space-y-2" :class="!enabled ? 'opacity-50 pointer-events-none' : ''">
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
    <div v-else class="flex-1 min-h-0 overflow-y-auto scroll-slim p-3 space-y-2" :class="!enabled ? 'opacity-50 pointer-events-none' : ''">
      <div class="text-xs font-medium">Эскиз-референс для модели</div>
      <div class="text-xs text-slate-500">Параметры съёма эскиза, который уйдёт референсом в модель.</div>
      <label class="block">
        <span class="text-xs text-slate-500">Размер эскиза</span>
        <select :value="sketch.source" @change="upd('source', $event.target.value)"
          class="mt-1 w-full border rounded p-1.5 text-xs bg-white">
          <option value="hd">HD 1600 по длинной</option>
          <option value="view">Размер вида</option>
          <option value="preset">Точный пресет</option>
        </select>
      </label>
      <label v-if="sketch.source === 'preset'" class="block">
        <span class="text-xs text-slate-500">Пресет</span>
        <select :value="sketch.preset" @change="upd('preset', $event.target.value)"
          class="mt-1 w-full border rounded p-1.5 text-xs bg-white">
          <option v-for="p in sketchPresets" :key="p" :value="p">{{ p }}</option>
        </select>
      </label>
      <label class="flex items-center gap-2 text-xs text-slate-600 cursor-pointer" title="Выключить силуэты на время снимка (рекомендуется для мелких форматов)">
        <input type="checkbox" :checked="sketch.thin_lines !== false" @change="upd('thin_lines', $event.target.checked)" />
        тонкие линии
      </label>
      <label class="flex items-center gap-2 text-xs text-slate-600 cursor-pointer" title="Прятать размерные линии на время снимка">
        <input type="checkbox" :checked="sketch.hide_dims !== false" @change="upd('hide_dims', $event.target.checked)" />
        скрыть размеры
      </label>
      <label class="flex items-center gap-2 text-xs text-slate-600 cursor-pointer" title="Резать пустые поля до контента (+5%) — объект займёт весь кадр">
        <input type="checkbox" :checked="sketch.autocrop === true" @change="upd('autocrop', $event.target.checked)" />
        автообрезка фона
      </label>
      <label class="flex items-center gap-2 text-xs text-slate-600 cursor-pointer" title="Убрать любой фон модели на время снимка — небо, землю и фон в белый">
        <input type="checkbox" :checked="sketch.white_bg === true" @change="upd('white_bg', $event.target.checked)" />
        белый фон
      </label>
    </div>
  </div>
</template>

<script setup>
import { ref } from 'vue'
const showSettings = ref(false)
const props = defineProps({
  scenes: { type: Array, default: () => [] },
  selected: { type: Array, default: () => [] },
  thumbs: { type: Object, default: () => ({}) },
  enabled: { type: Boolean, default: true },
  sketch: { type: Object, default: () => ({ source: 'hd', preset: '1024x768', thin_lines: true, hide_dims: true, autocrop: false, white_bg: false }) }
})
const emit = defineEmits(['toggle', 'refresh', 'sync-view', 'toggle-enabled', 'update-sketch'])
const sketchPresets = ['800x600', '1024x768', '1280x960']
function upd(key, value) {
  emit('update-sketch', { ...props.sketch, [key]: value })
}
</script>
