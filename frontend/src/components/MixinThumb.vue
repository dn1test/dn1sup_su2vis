<template>
  <canvas ref="cvRef" class="w-full h-auto block bg-slate-100"></canvas>
  <img ref="imgRef" :src="src" class="hidden" @load="draw" />
</template>

<script setup>
// Превью примеси как она уйдёт в генерацию: кроп исходника, затем поворот.
// Оригинал не трогаем: src всегда исходный data_url, перередактирование
// открывается тем же оригиналом.
import { ref, watch, onMounted, nextTick } from 'vue'
const props = defineProps({
  src: { type: String, default: '' },
  crop: { type: Object, default: null },
  rotation: { type: [Number, String], default: 0 }
})
const cvRef = ref(null)
const imgRef = ref(null)
function draw() {
  const cv = cvRef.value
  const el = imgRef.value
  if (!cv || !el || !el.naturalWidth) return
  const c = props.crop || { x: 0, y: 0, w: 1, h: 1 }
  const sx = Math.min(el.naturalWidth - 1, Math.round((Number(c.x) || 0) * el.naturalWidth))
  const sy = Math.min(el.naturalHeight - 1, Math.round((Number(c.y) || 0) * el.naturalHeight))
  const sw = Math.max(1, Math.round((Number(c.w) || 1) * el.naturalWidth))
  const sh = Math.max(1, Math.round((Number(c.h) || 1) * el.naturalHeight))
  const ang = (Number(props.rotation) || 0) * Math.PI / 180
  const cos = Math.abs(Math.cos(ang))
  const sin = Math.abs(Math.sin(ang))
  const dw = Math.max(1, Math.round(sw * cos + sh * sin))
  const dh = Math.max(1, Math.round(sw * sin + sh * cos))
  const cap = 1024
  const sc = Math.min(1, cap / Math.max(dw, dh))
  cv.width = Math.max(1, Math.round(dw * sc))
  cv.height = Math.max(1, Math.round(dh * sc))
  const ctx = cv.getContext('2d')
  if (!ctx) return
  ctx.save()
  ctx.translate(cv.width / 2, cv.height / 2)
  ctx.rotate(ang)
  ctx.scale(sc, sc)
  ctx.drawImage(el, sx, sy, sw, sh, -sw / 2, -sh / 2, sw, sh)
  ctx.restore()
}
watch(() => [props.src, props.crop, props.rotation], () => nextTick(draw), { deep: true })
onMounted(() => {
  const el = imgRef.value
  if (el && el.complete && el.naturalWidth) draw()
  nextTick(draw)
})
</script>
