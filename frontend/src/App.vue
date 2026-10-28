<template>
  <div class="h-screen flex flex-col overflow-hidden">
    <header class="shrink-0 px-4 py-2 bg-slate-900 text-white flex items-center justify-between">
      <div class="font-medium">DN1Sup SU2Vis <span class="text-slate-400 text-xs">референс → промпт → рендер · v{{ settings.version || '0.1.0' }}</span></div>
      <div class="flex items-center gap-2 text-xs">
        <div class="flex items-center gap-2 cursor-pointer select-none" @click="checkStudio" :title="connTitle">
          <span class="inline-block w-2.5 h-2.5 rounded-full" :class="connDot"></span>
          <span class="text-slate-200">{{ connLabel }}</span>
          <span class="text-slate-400 truncate max-w-[240px]" :title="modelTitle">· {{ modelLabel }}</span>
        </div>
        <button class="px-2 py-1 rounded border border-slate-600 hover:bg-slate-700 text-slate-200"
          title="Настройки подключения: URL, API-ключ, модель" @click="openConnection">⚙ Подключение</button>
      </div>
    </header>
    <div v-if="showProjectBanner" class="shrink-0 px-4 py-2 text-xs flex items-center gap-3"
      :class="projectState === 'unsaved' ? 'bg-amber-100 text-amber-900' : 'bg-sky-100 text-sky-900'">
      <span v-if="projectState === 'unsaved'">
        Модель ещё не сохранена. Сохраните .skp (Файл → Сохранить) — затем рядом с файлом создадим папку {{ projectDirLabel }}/ с параметрами.
      </span>
      <span v-else>
        Файл «{{ settings.model_name }}»: папка {{ projectDirLabel }}/ с параметрами рядом с .skp не создана. Настройки пока общие.
      </span>
      <button v-if="projectState === 'missing'" class="shrink-0 px-2 py-1 border rounded bg-white hover:bg-slate-50"
        @click="createProject">Создать {{ projectDirLabel }}/</button>
      <button class="shrink-0 px-2 py-1 border rounded bg-white hover:bg-slate-50"
        @click="recheckProject">Проверить снова</button>
      <button class="shrink-0 px-2 py-1 text-slate-500 hover:text-slate-800" @click="projectDismissed = true">Позже</button>
    </div>
    <div class="flex-1 min-h-0 overflow-hidden grid gap-3 p-3 grid-cols-[minmax(0,1fr)_300px_minmax(0,1fr)]">
      <ReferenceCol :scenes="scenes" :selected="selected" :thumbs="thumbs"
        :enabled-scenes="useScenes" :enabled-mixins="useMixins" :sketch="sketchOpts"
        :items="mixins" :settings="settings"
        @toggle="toggle" @toggle-enabled-scenes="setUseScenes" @toggle-enabled-mixins="setUseMixins"
        @update-sketch="setSketch" @preview-dims="setPreviewDims" @refresh="loadScenes" @sync-view="syncView"
        @add-data="addMixinData" @add-path="addMixinPath" @toggle-mixin="toggleMixin"
        @update-settings="updateColumnSettings"
        @caption="captionMixin" @neg="negMixin" @role="roleMixin" @weight="weightMixin"
        @move="moveMixin" @delete="deleteMixin" @transform="transformMixin"
        @save-scene-boxes="saveSceneBoxes" @save-mixin-boxes="saveMixinBoxes" @delete-all="deleteAllMixins" />
      <PromptCol v-model="settings" :enhance-preview="enhancePreview"
        @save="saveSettings" @enhance-preview="previewEnhance" @select-out-dir="selectOutDir" @open-out-dir="openOut" />
      <RenderCol :job="finalAgg" :results="finals" :busy="busy"
        :can-run="canRender" :final-label="finalLabel"
        @render="startFinal" @stop="stopCurrent" @view="viewFinal" @delete="deleteFinal" @retry="retryFinal"
        @delete-all="deleteAllFinals" />
    </div>
    <StatusBar :text="statusText" :tone="statusTone" :log="jobLog" :live="liveLogText"
      @load-log="loadLog" @clear-log="clearLog" />
    <ConnectionModal v-if="showConnection" v-model="settings" :status="studioStatus" :caps="studioCaps"
      :models="studioModels" :models-loading="modelsLoading" :models-error="modelsError"
      @save="saveSettings" @check="checkStudio" @ensure="ensureStudio" @refresh-models="loadModels" @close="showConnection = false" />
    <div v-if="viewer" class="fixed inset-0 z-50 bg-black/80 flex items-center justify-center p-4" @click.self="viewer = null">
      <div class="max-w-full max-h-full overflow-auto scroll-slim bg-white rounded p-2">
        <div class="flex items-center justify-between gap-4 px-1 pb-1">
          <span class="text-xs text-slate-600 break-all">{{ viewer.label }}</span>
          <button class="shrink-0 px-2 py-0.5 text-xs border rounded hover:bg-slate-100" @click="viewer = null">Закрыть ✕</button>
        </div>
        <div v-if="viewer.loading" class="text-xs text-slate-500 p-4">Загружаю полный размер…</div>
        <img v-else-if="viewer.src" :src="viewer.src" class="max-w-none" />
        <div v-else class="text-xs text-red-600 p-4">{{ viewer.error || 'не удалось загрузить' }}</div>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, computed, onMounted } from 'vue'
import { callRuby } from './bridge.js'
import ReferenceCol from './components/ReferenceCol.vue'
import PromptCol from './components/PromptCol.vue'
import RenderCol from './components/RenderCol.vue'
import ConnectionModal from './components/ConnectionModal.vue'
import StatusBar from './components/StatusBar.vue'

const scenes = ref([])
const selected = ref([])
const thumbs = ref({})
const mixins = ref([])
const captionTimers = {}
const settings = ref({ preview_variants: 1, final_mode: 'sketch', steps: 16 })
const finals = ref([])
const finalJobs = ref([])
const busy = ref(false)
const capturing = ref(false)
const studioStatus = ref(null)
const checkingStudio = ref(false)
const studioStarting = ref(false)
const studioModel = ref({ repo: '', gguf: '' })

function shortModel(repo) {
  const base = String(repo || '').split('/').pop() || ''
  return base.replace(/-GGUF$/i, '') || '—'
}
const modelLabel = computed(() => shortModel(studioModel.value.repo || settings.value.unsloth_model))
const modelTitle = computed(() => {
  const repo = studioModel.value.repo || settings.value.unsloth_model || ''
  const gguf = studioModel.value.gguf || settings.value.unsloth_gguf || ''
  if (!repo) return 'Модель неизвестна — откройте «Подключение»'
  const loaded = studioModel.value.repo ? 'загружена в студии' : 'выбрана в настройках (студия не опрошена)'
  return `${repo}${gguf ? ' / ' + gguf : ''} — ${loaded}. Нажмите чтобы перепроверить`
})

const connLabel = computed(() => {
  if (studioStarting.value) return 'Unsloth: запуск…'
  if (checkingStudio.value || studioStatus.value === null) return 'Unsloth: проверка…'
  return studioStatus.value.ok ? 'Unsloth: подключено' : 'Unsloth: нет связи'
})
const connDot = computed(() => {
  if (studioStarting.value || checkingStudio.value || studioStatus.value === null) return 'bg-slate-400 animate-pulse'
  return studioStatus.value.ok ? 'bg-green-400' : 'bg-red-500'
})
const connTitle = computed(() => {
  const url = settings.value.unsloth_url || ''
  if (studioStarting.value) return `Запускаю студию на ${url}…`
  if (checkingStudio.value) return 'Проверяю студию…'
  if (studioStatus.value?.ok) return `Подключено к ${url} — нажмите чтобы перепроверить`
  return `${studioStatus.value?.text || 'нет связи'} (${url}) — нажмите чтобы перепроверить`
})
const jobLog = ref([])
const genProgress = ref(null)
const viewer = ref(null)
const enhancePreview = ref(null)
const notice = ref(null)
const projectDismissed = ref(false)
const showConnection = ref(false)
const studioModels = ref([])
const studioCaps = ref(null)
const modelsLoading = ref(false)
const modelsError = ref('')

const projectState = computed(() => settings.value.project_state || 'global')
// Имя папки проекта для баннера (фактическое имя даёт project_init).
const projectDirLabel = computed(() => {
  const d = String(settings.value.project_dir || '')
  const base = d.split(/[\\/]/).pop()
  return base && base !== '.' ? base : (settings.value.model_name ? `su2vis_${settings.model_name}` : 'su2vis')
})
const useScenes = computed(() => settings.value.use_scenes !== false)
const useMixins = computed(() => settings.value.use_mixins !== false)
// Размер превью сцен приходит из ReferenceCol (по ширине колонки).
// Смена размера — дебаунс-перезагрузка превью после остановки resize.
const previewDims = ref(null)
let previewDimsTimer = null
function setPreviewDims(d) {
  const w = Number(d && d.w) || 0
  const h = Number(d && d.h) || 0
  if (w <= 0 || h <= 0) return
  const changed = !previewDims.value || previewDims.value.w !== w
  previewDims.value = { w, h }
  if (!changed) return
  clearTimeout(previewDimsTimer)
  previewDimsTimer = setTimeout(() => { loadScenes() }, 500)
}
const canRender = computed(() => {
  if (useScenes.value) return selected.value.length > 0
  if (useMixins.value) return mixins.value.some((m) => m.active !== false)
  return (settings.value.prompt || '').trim().length > 0
})
const showProjectBanner = computed(() => {
  if (projectDismissed.value) return false
  return projectState.value === 'missing' || projectState.value === 'unsaved'
})

function flash(text) {
  notice.value = text
  setTimeout(() => { if (notice.value === text) notice.value = null }, 6000)
}
let pollTimer = null

const finalLabel = computed(() => {
  const m = settings.value.final_mode
  if (m === 'custom') return `${settings.value.final_w}x${settings.value.final_h}`
  if (m === '1k') return '1K'
  if (m === '2k') return '2K'
  return 'эскиз'
})

const activeJob = computed(() => {
  return finalJobs.value.find((j) => !['done', 'error', 'cancelled'].includes(j.status)) || finalJobs.value[finalJobs.value.length - 1] || null
})

function agg(list) {
  if (!list.length) return null
  const done = list.filter((j) => ['done', 'error', 'cancelled'].includes(j.status)).length
  const running = list.some((j) => !['done', 'error', 'cancelled'].includes(j.status))
  const err = list.find((j) => j.status === 'error')
  return {
    kind: 'final', status: err && !running ? 'error' : running ? 'running' : list[list.length - 1].status,
    error: err?.error, progress: { done, total: list.length }
  }
}

const finalAgg = computed(() => agg(finalJobs.value))

const statusText = computed(() => {
  if (capturing.value) return 'Снимаю эскизы сцен…'
  const j = activeJob.value
  if (busy.value && j) {
    const p = j.progress || {}
    const total = p.total || 0
    const done = p.done || 0
    let live = ''
    if (genProgress.value && genProgress.value.active) {
      const g = genProgress.value
      const pct = Math.round((g.fraction || 0) * 100)
      live = ` · денойз ${g.step || 0}/${g.total_steps || 0} (${pct}%)`
    }
    return `Работает рендер: ${done}/${total}${p.scene !== undefined ? `, сцена #${p.scene}` : ''}${live} — «Стоп» остановит и на студии.`
  }
  if (finalAgg.value?.status === 'error') return `Рендер: ошибка — ${finalAgg.value.error}`
  if (finalJobs.value.some((j) => j.status === 'cancelled')) return 'Остановлено пользователем.'
  if (notice.value) return notice.value
  if (useScenes.value && !scenes.value.length) return 'Создайте сцены в модели и нажмите «Обновить».'
  if (!settings.value.unsloth_key) return 'Откройте «Подключение» в шапке и введите API-ключ студии.'
  if (!finals.value.length) {
    if (!useScenes.value && !useMixins.value) return 'Сцены и примеси выключены — генерация только по промпту: жмите «Рендер».'
    if (!useScenes.value) return 'Сцены выключены — выберите примеси и запустите «Рендер».'
    if (!useMixins.value) return 'Выберите сцену и запустите «Рендер» (примеси выключены).'
    return 'Выберите сцену и запустите «Рендер».'
  }
  return `Готово: рендеров ${finals.value.length}.`
})

const statusTone = computed(() => {
  if (busy.value) return 'work'
  if (finalAgg.value?.status === 'error') return 'error'
  if (finals.value.length) return 'ok'
  return 'idle'
})

const liveLogText = computed(() => {
  if (genProgress.value && genProgress.value.active) {
    const g = genProgress.value
    const pct = Math.round((g.fraction || 0) * 100)
    return `денойз ${g.step || 0}/${g.total_steps || 0} (${pct}%)`
  }
  const j = activeJob.value
  if (busy.value && j) {
    const p = j.progress || {}
    const total = p.total || 0
    const done = p.done || 0
    return `работает рендер: ${done}/${total}${p.scene !== undefined ? `, сцена #${p.scene}` : ''}`
  }
  const e = jobLog.value.length ? jobLog.value[jobLog.value.length - 1] : null
  if (!e) return 'журнал пуст'
  if (e.event === 'job_start') return `▸ рендер: сцены ${(e.scenes || []).join(',')}, seed ${e.seed}, steps ${e.steps || ''}`
  if (e.event === 'scene_done') return `· сцена #${e.scene}, seed ${e.seed}, ${e.size}, ${e.gen_s}с`
  if (e.event === 'job_done') return `■ ${e.status} за ${e.total_s}с${e.error ? ': ' + e.error : ''}`
  return String(e.event || 'журнал')
})

async function loadSettings() {
  const s = await callRuby('settings_get')
  if (s) {
    settings.value = s
    if (s.project_state === 'ready') projectDismissed.value = false
  }
}

async function createProject() {
  const r = await callRuby('project_init')
  if (r && r.ok && r.settings) {
    settings.value = r.settings
    projectDismissed.value = false
    flash(`Папка ${projectDirLabel.value}/ создана рядом с .skp — настройки теперь свои для этого файла`)
    loadGallery()
    loadMixins()
  } else {
    flash('Не создал su2vis/: ' + (r?.error || 'ошибка'))
  }
}

async function recheckProject() {
  projectDismissed.value = false
  await loadSettings()
}

async function loadScenes() {
  const list = await callRuby('scenes_list')
  scenes.value = Array.isArray(list) ? list : []
  if (!selected.value.length && scenes.value.length) selected.value = [scenes.value[0].index]
  const next = {}
  const white = settings.value.sketch_white_bg === true
  const noshadow = settings.value.sketch_no_shadows === true
  const dims = previewDims.value || {}
  for (const s of scenes.value) {
    const t = await callRuby('scenes_thumb', { index: s.index, white_bg: white, no_shadows: noshadow, w: dims.w, h: dims.h })
    if (t && t.thumb) next[t.index] = t.thumb
  }
  thumbs.value = next
}

async function loadAll() {
  await loadSettings()
  await loadScenes()
}

async function syncView(index) {
  const dims = previewDims.value || {}
  const r = await callRuby('scenes_sync_view', { index, white_bg: settings.value.sketch_white_bg === true, no_shadows: settings.value.sketch_no_shadows === true, w: dims.w, h: dims.h })
  if (r && r.thumb) thumbs.value = { ...thumbs.value, [r.index]: r.thumb }
}

function toggle(i) {
  selected.value = [i]
}

async function setUseScenes(v) {
  settings.value.use_scenes = !!v
  await saveSettings()
}

async function setUseMixins(v) {
  settings.value.use_mixins = !!v
  await saveSettings()
}

const sketchOpts = computed(() => ({
  source: settings.value.sketch_source || 'hd',
  preset: settings.value.sketch_preset || '1600x1200',
  style: settings.value.sketch_style || 'model',
  thin_lines: settings.value.sketch_thin_lines !== false,
  hide_dims: settings.value.sketch_hide_dims !== false,
  autocrop: settings.value.sketch_autocrop === true,
  white_bg: settings.value.sketch_white_bg === true,
  no_shadows: settings.value.sketch_no_shadows === true
}))

function sketchPayload() {
  const o = sketchOpts.value
  const m = String(o.preset || '').match(/(\d+)\s*x\s*(\d+)/i)
  return {
    source: o.source, thin_lines: !!o.thin_lines, hide_dims: !!o.hide_dims,
    autocrop: !!o.autocrop, white_bg: !!o.white_bg, no_shadows: !!o.no_shadows,
    preset_w: m ? +m[1] : 0, preset_h: m ? +m[2] : 0
  }
}

async function setSketch(patch) {
  const p = patch || {}
  if (p.source !== undefined) settings.value.sketch_source = p.source
  if (p.preset !== undefined) settings.value.sketch_preset = p.preset
  if (p.style !== undefined) settings.value.sketch_style = p.style
  if (p.thin_lines !== undefined) settings.value.sketch_thin_lines = !!p.thin_lines
  if (p.hide_dims !== undefined) settings.value.sketch_hide_dims = !!p.hide_dims
  if (p.autocrop !== undefined) settings.value.sketch_autocrop = !!p.autocrop
  if (p.no_shadows !== undefined) settings.value.sketch_no_shadows = !!p.no_shadows
  if (p.white_bg !== undefined || p.no_shadows !== undefined) {
    if (p.white_bg !== undefined) settings.value.sketch_white_bg = !!p.white_bg
    await saveSettings()
    await loadScenes()
    return
  }
  await saveSettings()
}

async function updateColumnSettings(patch) {
  settings.value = { ...settings.value, ...(patch || {}) }
  await saveSettings()
}

async function saveSettings() {
  const s = await callRuby('settings_save', settings.value)
  if (s) settings.value = s
}

async function ensureStudio() {
  try {
    const r = await callRuby('studio_ensure', { settings: settings.value })
    if (r && r.state && r.state.status === 'starting') studioStarting.value = true
    return r
  } catch { return null }
}

async function checkStudio() {
  if (checkingStudio.value) return
  checkingStudio.value = true
  studioStatus.value = { ok: false, text: 'Проверка…' }
  try {
    const r = await callRuby('studio_status', { settings: settings.value })
    studioStatus.value = r && r.ok
      ? { ok: true, text: `Студия OK: ${r.status.repo_id || 'модель'} (${(r.status.workflows || []).join(',')})` }
      : { ok: false, text: `Ошибка: ${r?.error || 'нет ответа'}` }
    if (r && r.ok) studioStarting.value = false
    if (r && r.ok && r.status) {
      studioModel.value = { repo: r.status.repo_id || '', gguf: r.status.gguf_filename || '' }
    }
  } finally {
    checkingStudio.value = false
  }
}

function openConnection() {
  showConnection.value = true
  loadModels()
}

async function loadModels() {
  if (modelsLoading.value) return
  modelsLoading.value = true
  modelsError.value = ''
  try {
    const r = await callRuby('studio_models', { settings: settings.value })
    if (r && r.ok) {
      studioModels.value = Array.isArray(r.models) ? r.models : []
      studioCaps.value = r.status && typeof r.status === 'object' ? r.status : null
      const st = r.status
      if (st) {
        studioModel.value = { repo: st.repo_id || '', gguf: st.gguf_filename || '' }
        const cur = studioStatus.value
        const txt = `Студия OK: ${st.repo_id || 'модель'}${st.gguf_filename ? '/' + st.gguf_filename : ''} (${(st.workflows || []).join(',')})`
        if (!cur || !cur.ok || cur.text !== txt) studioStatus.value = { ok: true, text: txt }
      }
      if (!studioModels.value.length) modelsError.value = 'Студия не подтвердила klein (проверь URL и ключ).'
      else if (!((studioModels.value[0] || {}).variants || []).length) modelsError.value = 'Студия не отдала варианты квантования (проверь связь и повтори).'
    } else {
      modelsError.value = r?.error || 'не удалось опросить студию'
      studioModels.value = []
      studioCaps.value = null
    }
  } catch (e) {
    modelsError.value = e?.message || 'не удалось опросить студию'
    studioModels.value = []
    studioCaps.value = null
  } finally {
    modelsLoading.value = false
  }
}

async function captureSketches(list, hd = false) {
  capturing.value = true
  try {
    const r = await callRuby('scenes_capture', { scenes: list, hd, sketch: sketchPayload() })
    if (!r || !r.ok) throw new Error(r?.error || 'снимок не удался')
    return r.sketches || {}
  } finally {
    capturing.value = false
  }
}

async function startFinal() {
  await saveSettings()
  if (useScenes.value) {
    if (!selected.value.length) return
  } else if (useMixins.value) {
    if (!activeMixins().length) { flash('Включите хотя бы одну примесь или включите сцены/только промпт'); return }
  } else if (!(settings.value.prompt || '').trim()) {
    flash('Введите промпт — сцены и примеси выключены')
    return
  }
  busy.value = true
  finalJobs.value = []
  const list = useScenes.value ? selected.value : []
  const sketches = useScenes.value ? await captureSketches(list, true) : {}
  for (const scene of (list.length ? list : [null])) {
    if (scene === null && list.length) continue
    const scenesArg = scene === null ? [] : [scene]
    const j = await callRuby('jobs_start', { kind: 'final', scenes: scenesArg, sketches, mixins: activeMixins(), settings: settings.value })
    if (j) finalJobs.value.push(j)
  }
  if (!finalJobs.value.length) {
    const j = await callRuby('jobs_start', { kind: 'final', scenes: [], sketches, mixins: activeMixins(), settings: settings.value })
    if (j) finalJobs.value.push(j)
  }
  startPoll()
}

async function viewFinal(r) {
  if (r.data_url) {
    viewer.value = { src: r.data_url, label: r.file }
    return
  }
  viewer.value = { loading: true, label: r.file }
  const res = await callRuby('final_view', { file: r.file })
  if (res && res.ok) viewer.value = { src: res.data_url, label: r.file }
  else viewer.value = { error: (res && res.error) || 'не удалось загрузить', label: r.file }
}

async function retryFinal(r) {
  if (!r.file) return
  r.load_error = null
  const res = await callRuby('final_view', { file: r.file })
  if (res && res.ok) r.data_url = res.data_url
  else r.load_error = (res && res.error) || 'не удалось загрузить'
}

async function previewEnhance() {
  enhancePreview.value = { loading: true }
  const ref = selected.value.length ? (thumbs.value[selected.value[0]] || null) : null
  const started = await callRuby('enhance_preview', { prompt: settings.value.prompt, reference: ref })
  const task = started && started.ok && started.task ? started.task : null
  if (!task || !task.id) {
    enhancePreview.value = { error: (started && started.error) || 'не удалось запустить апсемплер' }
    return
  }
  for (let i = 0; i < 300; i++) {
    await new Promise((r) => setTimeout(r, 2000))
    const p = await callRuby('enhance_poll', { id: task.id })
    const t = p && p.ok && p.task ? p.task : null
    if (!t) { enhancePreview.value = { error: 'потеряна задача апсемплера' }; return }
    if (t.status === 'done') {
      if (t.text) enhancePreview.value = { text: t.text }
      else enhancePreview.value = { error: 'студия вернула пустой enhanced_prompt' }
      return
    }
    if (t.status === 'error') { enhancePreview.value = { error: t.error || 'не удалось получить капшн' }; return }
  }
  enhancePreview.value = { error: 'апсемплер не ответил за 10 минут' }
}

async function selectOutDir() {
  const res = await callRuby('select_out_dir')
  if (res && res.ok && res.settings) {
    settings.value = res.settings
    flash('Папка рендеров: ' + (res.settings.out_dir || ''))
  } else if (res && res.error) {
    flash('Не удалось выбрать папку: ' + res.error)
  }
}

async function stopCurrent() {
  for (const job of finalJobs.value) {
    if (job?.id && !['done', 'error', 'cancelled'].includes(job.status)) {
      await callRuby('jobs_cancel', { id: job.id })
    }
  }
  pollJob()
}

function startPoll() {
  stopPoll()
  pollTimer = setInterval(pollJob, 2000)
  pollJob()
}

async function pollJob() {
  const list = finalJobs.value
  if (!list.length) return
  const live = settings.value.studio_live_preview !== false
  const polls = await Promise.all([
    ...list.map((job) => callRuby('jobs_poll', { id: job.id })),
    ...(live ? [callRuby('gen_progress')] : [])
  ])
  const g = live ? polls[polls.length - 1] : null
  genProgress.value = g && g.active ? g : null
  const updated = polls.slice(0, list.length)
  finalJobs.value = updated.filter(Boolean)
  const incoming = finalJobs.value.flatMap((j) => (j && j.results ? j.results : []))
  for (const r of incoming) {
    const i = finals.value.findIndex((f) => (f.file && f.file === r.file) || (!f.file && !r.file && f.scene === r.scene))
    if (i >= 0) finals.value[i] = { ...r, data_url: finals.value[i].data_url }
    else finals.value.push(r)
  }
  for (const f of finals.value) {
    if (!f.data_url && f.file && !f.load_error) {
      const res = await callRuby('final_view', { file: f.file })
      if (res && res.ok) f.data_url = res.data_url
      else f.load_error = (res && res.error) || 'не удалось загрузить'
    }
  }
  const states = finalJobs.value.map((j) => j.status)
  if (states.length && states.every((s) => ['done', 'error', 'cancelled'].includes(s))) {
    busy.value = false
    genProgress.value = null
    stopPoll()
    loadLog()
  }
}

function stopPoll() {
  if (pollTimer) { clearInterval(pollTimer); pollTimer = null }
}

function openOut() {
  callRuby('open_out_dir')
}

async function loadLog() {
  const l = await callRuby('jobs_log', { limit: 50 })
  if (Array.isArray(l)) jobLog.value = l
}

async function loadGallery() {
  const g = await callRuby('gallery_list')
  if (!Array.isArray(g)) return
  finals.value = g.filter((e) => e && e.kind !== 'preview')
  for (const r of finals.value.slice(0, 100)) {
    if (!r.data_url && r.file && !r.load_error) {
      const res = await callRuby('final_view', { file: r.file })
      if (res && res.ok) r.data_url = res.data_url
      else r.load_error = (res && res.error) || 'не удалось загрузить'
    }
  }
}

function activeMixins() {
  if (!useMixins.value) return []
  return mixins.value
    .filter((m) => m.active !== false)
    .map((m) => ({ path: m.file, file: m.file, caption: m.caption || '', caption_neg: m.caption_neg || '',
      role: m.role || 'auto', weight: Number(m.weight) || 1, apply_to: 'final', active: true,
      crop: m.crop || null, rotation: Number(m.rotation) || 0, boxes: m.boxes || [] }))
}

async function loadMixins() {
  const list = await callRuby('mixins_list')
  mixins.value = Array.isArray(list) ? list : []
  for (const m of mixins.value.slice(0, 30)) {
    if (!m.data_url && m.id) {
      const res = await callRuby('mixins_view', { id: m.id })
      if (res && res.ok) m.data_url = res.data_url
    }
  }
}

async function addMixinData({ data_url, name }) {
  if (!data_url) return
  const res = await callRuby('mixins_add_data', { data_url, name: name || '' })
  if (res && res.ok && res.entry) {
    res.entry.data_url = data_url
    mixins.value = [...mixins.value, res.entry]
  } else if (res && res.error) {
    flash('Не добавил примесь: ' + res.error)
  }
}

async function addMixinPath() {
  const res = await callRuby('mixins_add_path')
  if (res && res.ok && res.entry) {
    mixins.value = [...mixins.value, res.entry]
    const v = await callRuby('mixins_view', { id: res.entry.id })
    if (v && v.ok) {
      const i = mixins.value.findIndex((m) => m.id === res.entry.id)
      if (i >= 0) mixins.value[i] = { ...mixins.value[i], data_url: v.data_url }
    }
  } else if (res && res.error) {
    flash('Не добавил примесь: ' + res.error)
  }
}

async function toggleMixin(m) {
  const next = !(m.active !== false)
  m.active = next
  const res = await callRuby('mixins_update', { id: m.id, active: next })
  if (!(res && res.ok)) flash('Не сохранил примесь: ' + ((res && res.error) || 'ошибка'))
}

function captionMixin({ item, caption }) {
  item.caption = caption
  clearTimeout(captionTimers[item.id])
  captionTimers[item.id] = setTimeout(async () => {
    await callRuby('mixins_update', { id: item.id, caption })
  }, 800)
}

function negMixin({ item, caption_neg }) {
  item.caption_neg = caption_neg
  clearTimeout(captionTimers[item.id])
  captionTimers[item.id] = setTimeout(async () => {
    await callRuby('mixins_update', { id: item.id, caption_neg })
  }, 800)
}

function roleMixin({ item, role }) {
  item.role = role
  callRuby('mixins_update', { id: item.id, role })
}

function weightMixin({ item, weight }) {
  item.weight = weight
  clearTimeout(captionTimers[item.id])
  captionTimers[item.id] = setTimeout(async () => {
    await callRuby('mixins_update', { id: item.id, weight })
  }, 800)
}

async function transformMixin({ item, crop, rotation }) {
  item.crop = crop
  item.rotation = rotation
  const res = await callRuby('mixins_update', { id: item.id, crop, rotation })
  if (!(res && res.ok)) flash('Не сохранил выделение: ' + ((res && res.error) || 'ошибка'))
}

async function saveSceneBoxes({ index, boxes }) {
  const s = scenes.value.find((x) => x.index === index)
  if (s) s.boxes = boxes
  const res = await callRuby('scenes_boxes_save', { index, boxes })
  if (res && res.ok) {
    if (s) s.boxes = res.boxes || boxes
    flash(boxes.length ? `Рамки сцены сохранены (${boxes.length}) — уйдут в промпт и на эскиз` : 'Рамки сцены убраны')
  } else {
    flash('Не сохранил рамки: ' + ((res && res.error) || 'ошибка'))
  }
}

async function saveMixinBoxes({ item, boxes }) {
  item.boxes = boxes
  const res = await callRuby('mixins_update', { id: item.id, boxes })
  if (!(res && res.ok)) flash('Не сохранил рамки: ' + ((res && res.error) || 'ошибка'))
}

async function moveMixin({ item, dir }) {
  const i = mixins.value.findIndex((x) => x.id === item.id)
  const j = i + dir
  if (i < 0 || j < 0 || j >= mixins.value.length) return
  const next = [...mixins.value]
  const [m] = next.splice(i, 1)
  next.splice(j, 0, m)
  mixins.value = next
  await callRuby('mixins_reorder', { ids: next.map((x) => x.id) })
}

async function deleteMixin(m) {
  const res = await callRuby('mixins_delete', { id: m.id })
  if (res && res.ok) {
    mixins.value = mixins.value.filter((x) => x.id !== m.id)
  } else {
    flash('Не удалил примесь: ' + ((res && res.error) || 'ошибка'))
  }
}

async function deleteAllMixins() {
  const res = await callRuby('mixins_delete_all')
  if (res && res.ok) {
    mixins.value = []
    flash(res.deleted ? `Удалил примесей: ${res.deleted}` : 'Примесей нет')
  } else {
    flash('Не удалил примеси: ' + ((res && res.error) || 'ошибка'))
  }
}

async function deleteEntry(r, arr) {
  if (!r.file) { flash('У этой картинки нет файла на диске'); return }
  const res = await callRuby('gallery_delete', { file: r.file })
  if (res && res.ok) {
    const i = arr.value.findIndex((x) => x.file === r.file)
    if (i >= 0) arr.value.splice(i, 1)
  } else {
    flash('Не удалил: ' + (res?.error || 'ошибка'))
  }
}
const deleteFinal = (r) => deleteEntry(r, finals)

async function deleteAllFinals() {
  const res = await callRuby('gallery_delete_all')
  if (res && res.ok) {
    finals.value = []
    flash(res.deleted ? `Удалил рендеров: ${res.deleted}` : 'Папка рендеров пуста')
  } else {
    flash('Не удалил: ' + ((res && res.error) || 'ошибка'))
  }
}

async function clearLog() {
  await callRuby('jobs_log_clear')
  jobLog.value = []
}

onMounted(async () => {
  await loadAll()
  await loadLog()
  await loadGallery()
  await loadMixins()
  await ensureStudio()
  await checkStudio()
  for (let i = 0; i < 30 && (!studioStatus.value || !studioStatus.value.ok); i++) {
    await new Promise((r) => setTimeout(r, 2000))
    await checkStudio()
  }
  if (!studioStatus.value || !studioStatus.value.ok) studioStarting.value = false
})
</script>
