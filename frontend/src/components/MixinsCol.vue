<template>
  <div class="border rounded-lg bg-white overflow-hidden flex flex-col min-h-0 max-h-full">
    <div class="shrink-0 px-3 py-2 border-b bg-slate-50 flex items-center justify-between">
      <span class="font-medium">3 · Примеси</span>
      <span class="text-xs text-slate-500">{{ activeCount }}/{{ items.length }}</span>
    </div>
    <div class="shrink-0 p-3 pb-0 space-y-2">
      <div class="flex gap-2">
        <label class="flex-1 px-3 py-2 rounded bg-slate-900 text-white text-xs text-center cursor-pointer hover:bg-slate-700">
          Добавить…
          <input ref="fileInput" type="file" accept="image/png,image/jpeg,image/webp" multiple class="hidden" @change="onFiles" />
        </label>
        <button class="px-3 py-2 rounded border text-xs hover:bg-slate-100" title="Выбрать файл с диска через SketchUp"
          @click="$emit('add-path')">Из файла…</button>
      </div>
      <div v-if="!items.length" class="text-xs text-slate-500">Картинки-референсы для примеси + подпись «что взять». Учитываются в превью и финале.</div>
      <div v-else class="text-xs text-slate-500">Галочка — участвует в генерации. Подпись дописывается к промпту.</div>
    </div>
    <div class="flex-1 min-h-0 overflow-y-auto scroll-slim p-3 space-y-2">
      <div v-for="m in items" :key="m.id" class="relative border rounded overflow-hidden" :class="m.active === false ? 'opacity-60' : ''">
        <button class="absolute top-1 right-1 z-10 w-6 h-6 text-xs rounded-full bg-black/60 text-white hover:bg-red-600"
          title="Удалить примесь с диска" @click.stop="$emit('delete', m)">✕</button>
        <img v-if="m.data_url" :src="m.data_url" class="w-full h-auto block bg-slate-100" />
        <div v-else class="w-full bg-slate-200 flex items-center justify-center text-xs text-slate-500 py-6">загружаю…</div>
        <div class="p-2 space-y-1">
          <div class="flex items-center gap-2">
            <input type="checkbox" :checked="m.active !== false" @change="$emit('toggle', m)" />
            <span class="text-xs font-medium truncate flex-1" :title="m.name">{{ m.name || m.id }}</span>
          </div>
          <textarea :value="m.caption || ''" @input="$emit('caption', { item: m, caption: $event.target.value })"
            rows="2" placeholder="Что взять: напр. фактура кирпича со стены"
            class="w-full border rounded p-1.5 text-xs"></textarea>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup>
import { computed } from 'vue'
const props = defineProps({ items: { type: Array, default: () => [] } })
const emit = defineEmits(['add-data', 'add-path', 'toggle', 'caption', 'delete'])
function onFiles(e) {
  const files = Array.from(e.target?.files || [])
  e.target.value = ''
  files.forEach((f) => {
    const rd = new FileReader()
    rd.onload = () => emit('add-data', { data_url: String(rd.result || ''), name: f.name })
    rd.readAsDataURL(f)
  })
}
const activeCount = computed(() => props.items.filter((m) => m.active !== false).length)
</script>
