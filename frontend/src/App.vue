<template>
  <div class="h-screen flex flex-col overflow-hidden">
    <header class="shrink-0 px-4 py-2 bg-slate-900 text-white flex items-center justify-between">
      <div class="font-medium">DN1Sup SU2Vis <span class="text-slate-400 text-xs">сцены → примеси → превью → финал · v{{ settings.version || '0.1.0' }}</span></div>
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
        Модель ещё не сохранена. Сохраните .skp (Файл → Сохранить) — затем рядом с файлом создадим папку su2vis/ с параметрами.
      </span>
      <span v-else>
        Файл «{{ settings.model_name }}»: папка su2vis/ с параметрами рядом с .skp не создана. Настройки пока общие.
      </span>
      <button v-if="projectState === 'missing'" class="shrink-0 px-2 py-1 border rounded bg-white hover:bg-slate-50"
        @click="createProject">Создать su2vis/</button>
      <button class="shrink-0 px-2 py-1 border rounded bg-white hover:bg-slate-50"
        @click="recheckProject">Проверить снова</button>
      <button class="shrink-0 px-2 py-1 text-slate-500 hover:text-slate-800" @click="projectDismissed = true">Позже</button>
    </div>
    <div class="flex-1 min-h-0 overflow-hidden grid gap-3 p-3 md:grid-cols-2 xl:grid-cols-[200px_240px_360px_340px_1fr]">
      <ScenesCol :scenes="scenes" :selected="selected" :thumbs="thumbs" :enabled="useScenes" :sketch="sketchOpts"
        @toggle="toggle" @toggle-enabled="setUseScenes" @update-sketch="setSketch"
        @refresh="loadScenes" @sync-view="syncView" />
      <MixinsCol :items="mixins" :enabled="useMixins" :settings="settings"
        @add-data="addMixinData" @add-path="addMixinPath" @toggle="toggleMixin"
        @toggle-enabled="setUseMixins" @update-settings="updateColumnSettings"
        @caption="captionMixin" @neg="negMixin" @role="roleMixin" @weight="weightMixin"
        @apply="applyMixin" @move="moveMixin" @delete="deleteMixin" @transform="transformMixin" />
      <PreviewCol :job="previewAgg" :results="previews" :busy="busy"
        :can-run="canPreview" :variants="Number(settings.preview_variants || 1)" :selected-seed="Number(settings.seed)"
        :settings="settings" @update-settings="updateColumnSettings"
        @variants="setVariants" @select-preview="selectPreview"
        @preview="startPreview" @stop="stopCurrent" @final-one="finalOne" @delete="deletePreview" @retry="retryFinal" />
      <SettingsCol v-model="settings" :status="studioStatus" :enhance-preview="enhancePreview"
        @save="saveSettings" @enhance-preview="previewEnhance" @select-out-dir="selectOutDir" @open-out-dir="openOut" />
      <FinalCol :job="finalAgg" :results="finals" :busy="busy"
        :can-run="previews.length > 0" :final-label="finalLabel" :settings="settings"
        @update-settings="updateColumnSettings"
        @final-all="finalAll" @stop="stopCurrent" @view="viewFinal" @delete="deleteFinal" @retry="retryFinal" />
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
import ScenesCol from './components/ScenesCol.vue'
import PreviewCol from './components/PreviewCol.vue'
import MixinsCol from './components/MixinsCol.vue'
import FinalCol from './components/FinalCol.vue'
import SettingsCol from './components/SettingsCol.vue'
import ConnectionModal from './components/ConnectionModal.vue'
import StatusBar from './components/StatusBar.vue'

const scenes = ref([])
const selected = ref([])
const thumbs = ref({})
const mixins = ref([])
const captionTimers = {}
const settings = ref({ preview_preset: '256', preview_variants: 1, final_mode: 'sketch' })
const previews = ref([])
const finals = ref([])
const previewJobs = ref([])
const finalJobs = ref([])
const busy = ref(false)
const busyKind = ref(null)
const capturing = ref(false)
const studioStatus = ref(null)
const checkingStudio = ref(false)
// true пока фоновый автозапуск студии не дал связи (шапка показывает «запуск…»).
const studioStarting = ref(false)
// Модель, загруженная в студии сейчас (repo/gguf из images/status).
// В шапке показываем её; пока студия не опрошена — выбранную в настройках.
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
// Выключатели колонок: хранятся в settings (per-file), дефолт true для старых сохранений.
const useScenes = computed(() => settings.value.use_scenes !== false)
const useMixins = computed(() => settings.value.use_mixins !== false)
// Что можно запустить: сцена / примеси / только промпт.
const canPreview = computed(() => {
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
let pollKind = null

const finalLabel = computed(() => {
  const m = settings.value.final_mode
  if (m === 'custom') return `${settings.value.final_w}x${settings.value.final_h}`
  if (m === '1k') return '1K'
  if (m === '2k') return '2K'
  return 'эскиз'
})

const activeJob = computed(() => {
  const list = pollKind === 'final' ? finalJobs.value : previewJobs.value
  return list.find((j) => !['done', 'error', 'cancelled'].includes(j.status)) || list[list.length - 1] || null
})

function agg(list, kind) {
  if (!list.length) return null
  const done = list.filter((j) => ['done', 'error', 'cancelled'].includes(j.status)).length
  const running = list.some((j) => !['done', 'error', 'cancelled'].includes(j.status))
  const err = list.find((j) => j.status === 'error')
  return {
    kind, status: err && !running ? 'error' : running ? 'running' : list[list.length - 1].status,
    error: err?.error, progress: { done, total: list.length }
  }
}

const previewAgg = computed(() => agg(previewJobs.value, 'preview'))
const finalAgg = computed(() => agg(finalJobs.value, 'final'))

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
      live = ` · денойз ${g.step || 0}/${g.total_steps || 4} (${pct}%)`
    }
    return `Работает ${j.kind === 'final' ? 'финал' : 'превью'}: ${done}/${total}${p.scene !== undefined ? `, сцена #${p.scene}` : ''}${live} — «Стоп» остановит и на студии.`
  }
  if (previewAgg.value?.status === 'error') return `Превью: ошибка — ${previewAgg.value.error}`
  if (finalAgg.value?.status === 'error') return `Финал: ошибка — ${finalAgg.value.error}`
  if (previewJobs.value.some((j) => j.status === 'cancelled') || finalJobs.value.some((j) => j.status === 'cancelled')) return 'Остановлено пользователем.'
  if (notice.value) return notice.value
  if (useScenes.value && !scenes.value.length) return 'Создайте сцены в модели и нажмите «Обновить».'
  if (!settings.value.unsloth_key) return 'Откройте «Подключение» в шапке и введите API-ключ студии.'
  if (!previews.value.length) {
    if (!useScenes.value && !useMixins.value) return 'Сцены и примеси выключены — генерация только по промпту: жмите «Превью».'
    if (!useScenes.value) return 'Сцены выключены — выберите примеси и запустите «Превью».'
    if (!useMixins.value) return 'Выберите сцену и запустите «Превью» (примеси выключены).'
    return 'Выберите сцену и запустите «Превью».'
  }
  if (!finals.value.length) return 'Превью готово: seed зафиксирован — жмите «В финал» на карточке или «Все превью в финал».'
  return `Готово: финалов ${finals.value.length}. Seed превью сохранён для повторов.`
})

const statusTone = computed(() => {
  if (busy.value) return 'work'
  if (previewAgg.value?.status === 'error' || finalAgg.value?.status === 'error') return 'error'
  if (finals.value.length) return 'ok'
  return 'idle'
})

// Правая часть статусбара: живой прогресс, иначе последняя запись журнала.
const liveLogText = computed(() => {
  if (genProgress.value && genProgress.value.active) {
    const g = genProgress.value
    const pct = Math.round((g.fraction || 0) * 100)
    return `денойз ${g.step || 0}/${g.total_steps || 4} (${pct}%)`
  }
  const j = activeJob.value
  if (busy.value && j) {
    const p = j.progress || {}
    const total = p.total || 0
    const done = p.done || 0
    return `работает ${j.kind === 'final' ? 'финал' : 'превью'}: ${done}/${total}${p.scene !== undefined ? `, сцена #${p.scene}` : ''}`
  }
  const e = jobLog.value.length ? jobLog.value[jobLog.value.length - 1] : null
  if (!e) return 'журнал пуст'
  if (e.event === 'job_start') return `▸ ${e.kind}: сцены ${(e.scenes || []).join(',')}, seed ${e.seed}`
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
    flash('Папка su2vis/ создана рядом с .skp — настройки теперь свои для этого файла')
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
  for (const s of scenes.value) {
    const t = await callRuby('scenes_thumb', { index: s.index, white_bg: white })
    if (t && t.thumb) next[t.index] = t.thumb
  }
  thumbs.value = next
}

async function loadAll() {
  await loadSettings()
  await loadScenes()
}

async function syncView(index) {
  const r = await callRuby('scenes_sync_view', { index, white_bg: settings.value.sketch_white_bg === true })
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

// Параметры съёма эскиза-референса (блок в 1-й колонке → settings → scenes_capture).
const sketchOpts = computed(() => ({
  source: settings.value.sketch_source || 'hd',
  preset: settings.value.sketch_preset || '1024x768',
  thin_lines: settings.value.sketch_thin_lines !== false,
  hide_dims: settings.value.sketch_hide_dims !== false,
  autocrop: settings.value.sketch_autocrop === true,
  white_bg: settings.value.sketch_white_bg === true
}))

function sketchPayload() {
  const o = sketchOpts.value
  const m = String(o.preset || '').match(/(\d+)\s*x\s*(\d+)/i)
  return {
    source: o.source, thin_lines: !!o.thin_lines, hide_dims: !!o.hide_dims,
    autocrop: !!o.autocrop, white_bg: !!o.white_bg,
    preset_w: m ? +m[1] : 0, preset_h: m ? +m[2] : 0
  }
}

async function setSketch(patch) {
  const p = patch || {}
  if (p.source !== undefined) settings.value.sketch_source = p.source
  if (p.preset !== undefined) settings.value.sketch_preset = p.preset
  if (p.thin_lines !== undefined) settings.value.sketch_thin_lines = !!p.thin_lines
  if (p.hide_dims !== undefined) settings.value.sketch_hide_dims = !!p.hide_dims
  if (p.autocrop !== undefined) settings.value.sketch_autocrop = !!p.autocrop
  if (p.white_bg !== undefined) {
    settings.value.sketch_white_bg = !!p.white_bg
    await saveSettings()
    await loadScenes()
    return
  }
  await saveSettings()
}

async function setVariants(n) {
  settings.value.preview_variants = Math.min(4, Math.max(1, Number(n) || 1))
  await saveSettings()
}

// Правки из шестерёнок колонок (превью/финал/примеси): слить и сохранить сразу.
async function updateColumnSettings(patch) {
  settings.value = { ...settings.value, ...(patch || {}) }
  await saveSettings()
}

async function selectPreview({ scene, seed }) {
  settings.value.seed = seed
  await saveSettings()
  flash(`Выбрано превью #${scene}, seed ${seed} — в настройках`)
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

// Эскизы снимаем на главном потоке ДО старта фоновой задачи:
// write_image из рабочего Thread отдаёт устаревший кадр.
// Параметры съёма — из блока «Эскиз-референс» 1-й колонки.
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

async function startPreview() {
  await saveSettings()
  if (useScenes.value) {
    if (!selected.value.length) return
  } else if (useMixins.value) {
    if (!activeMixins().length) { flash('Включите хотя бы одну примесь или включите сцены/только промпт'); return }
  } else if (!(settings.value.prompt || '').trim()) {
    flash('Введите промпт в настройках — сцены и примеси выключены')
    return
  }
  busy.value = true
  busyKind.value = 'preview'
  // Галерею с диска не трогаем: новые результаты подмержатся в pollJob.
  previewJobs.value = []
  // Без сцены эскизы не снимаем — чистый text-to-image / только примеси.
  const list = useScenes.value ? selected.value : []
  const sketches = useScenes.value ? await captureSketches(list, true) : {}
  if (!useScenes.value) {
    const j = await callRuby('jobs_start', { kind: 'preview', scenes: [], sketches, mixins: activeMixins(), settings: { ...settings.value, preview_preset: '256' } })
    if (j) previewJobs.value.push(j)
    startPoll('preview')
    return
  }
  for (const scene of list) {
    const j = await callRuby('jobs_start', { kind: 'preview', scenes: [scene], sketches, mixins: activeMixins(), settings: { ...settings.value, preview_preset: '256' } })
    if (j) previewJobs.value.push(j)
  }
  startPoll('preview')
}

// Ключ эскиза для задачи: сцена — её индекс, без сцены — 'prompt'.
function sketchKey(scene) {
  return scene === null || scene === undefined ? 'prompt' : scene
}

async function finalOne({ scene, seed }) {
  const entry = previews.value.find((r) => r.scene === scene && r.seed === seed)
  if (!entry || !entry.data_url) { flash('Нет картинки превью для финала — запустите превью заново'); return }
  await saveSettings()
  busy.value = true
  busyKind.value = 'final'
  const sketches = await savePreviewRefs([entry])
  const st = useScenes.value
    ? { ...settings.value, seeds: { [scene]: seed }, from_preview: true }
    : { ...settings.value, seeds: { prompt: seed }, from_preview: true }
  const j = await callRuby('jobs_start', { kind: 'final', scenes: useScenes.value ? [scene] : [], sketches, mixins: activeMixins(), settings: st })
  if (j) finalJobs.value = [...finalJobs.value, j]
  startPoll('final')
}

async function finalAll() {
  if (!previews.value.length) return
  await saveSettings()
  busy.value = true
  busyKind.value = 'final'
  const list = previews.value.filter((r) => r.data_url).map((r) => ({ scene: r.scene, seed: r.seed }))
  if (!list.length) { flash('Нет картинок превью для финала'); busy.value = false; return }
  const sketches = await savePreviewRefs(list.map((x) => previews.value.find((r) => r.scene === x.scene && r.seed === x.seed)))
  finalJobs.value = []
  if (!useScenes.value) {
    const seed = list[0].seed
    const st = { ...settings.value, seeds: { prompt: seed }, from_preview: true }
    const j = await callRuby('jobs_start', { kind: 'final', scenes: [], sketches, mixins: activeMixins(), settings: st })
    if (j) finalJobs.value.push(j)
    startPoll('final')
    return
  }
  const scenes = [...new Set(list.map((x) => x.scene))]
  for (const scene of scenes) {
    const seed = list.find((x) => x.scene === scene).seed
    const st = { ...settings.value, seeds: { [scene]: seed }, from_preview: true }
    const j = await callRuby('jobs_start', { kind: 'final', scenes: [scene], sketches, mixins: activeMixins(), settings: st })
    if (j) finalJobs.value.push(j)
  }
  startPoll('final')
}

// Байты выбранных превью — в файлы для финала (мост preview_save).
async function savePreviewRefs(entries) {
  const sketches = {}
  for (const r of entries) {
    const res = await callRuby('preview_save', { scene: r.scene ?? 0, seed: r.seed, data_url: r.data_url })
    if (!res || !res.ok) throw new Error(res?.error || 'не сохранил превью для финала')
    sketches[sketchKey(r.scene)] = res.path
  }
  return sketches
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

// Догрузка картинки для карточки (финал из задачи или галерея с диска).
// Неудача видна сразу на карточке + кнопка «Повторить», а не вечная загрузка.
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
  // Апсемплер считается в фоне (Ruby Enhance): стартуем и опрашиваем,
  // каждый опрос быстрый — главный поток SketchUp не висит.
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
  const list = pollKind === 'final' ? finalJobs.value : previewJobs.value
  for (const job of list) {
    if (job?.id && !['done', 'error', 'cancelled'].includes(job.status)) {
      await callRuby('jobs_cancel', { id: job.id })
    }
  }
  pollJob()
}

function startPoll(kind) {
  stopPoll()
  pollKind = kind
  pollTimer = setInterval(pollJob, 2000)
  pollJob()
}

async function pollJob() {
  const list = pollKind === 'final' ? finalJobs.value : previewJobs.value
  if (!list.length) return
  const live = settings.value.studio_live_preview !== false
  const polls = await Promise.all([
    ...list.map((job) => callRuby('jobs_poll', { id: job.id })),
    ...(live ? [callRuby('gen_progress')] : [])
  ])
  const g = live ? polls[polls.length - 1] : null
  genProgress.value = g && g.active ? g : null
  const updated = polls.slice(0, list.length)
  if (pollKind === 'preview') {
    previewJobs.value = updated.filter(Boolean)
    // Свежие результаты + сохранённая галерея (файлы на диске не теряем).
    const fresh = previewJobs.value.flatMap((j) => j.results || [])
    const seen = new Set(fresh.map((r) => r.file).filter(Boolean))
    previews.value = [...fresh, ...previews.value.filter((r) => r.file && !seen.has(r.file))]
    const first = previewJobs.value.find((j) => j.status === 'done' && j.results?.length)
    if (first && !previewJobs.value.some((j) => !['done', 'error', 'cancelled'].includes(j.status))) {
      settings.value.seed = first.results[0].seed
      await saveSettings()
    }
  } else {
    finalJobs.value = updated.filter(Boolean)
    const incoming = updated.flatMap((j) => (j && j.results ? j.results : []))
    for (const r of incoming) {
      const i = finals.value.findIndex((f) => (f.file && f.file === r.file) || (!f.file && !r.file && f.scene === r.scene))
      if (i >= 0) finals.value[i] = { ...r, data_url: finals.value[i].data_url }
      else finals.value.push(r)
    }
    // Догружаем картинки для просмотра (лениво, по одной за опрос).
    // Ошибку показываем на карточке с повтором, а не вечной «загрузкой».
    for (const f of finals.value) {
      if (!f.data_url && f.file && !f.load_error) {
        const res = await callRuby('final_view', { file: f.file })
        if (res && res.ok) f.data_url = res.data_url
        else f.load_error = (res && res.error) || 'не удалось загрузить'
      }
    }
  }
  const states = (pollKind === 'final' ? finalJobs.value : previewJobs.value).map((j) => j.status)
  if (states.length && states.every((s) => ['done', 'error', 'cancelled'].includes(s))) {
    busy.value = false
    busyKind.value = null
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

// Галерея с диска: файлы из папки пользователя должны быть на месте
// при открытии панели. Картинки догружаем лениво (до 100 новейших).
async function loadGallery() {
  const g = await callRuby('gallery_list')
  if (!Array.isArray(g)) return
  previews.value = g.filter((e) => e && e.kind === 'preview')
  finals.value = g.filter((e) => e && e.kind !== 'preview')
  for (const r of [...previews.value, ...finals.value].slice(0, 100)) {
    if (!r.data_url && r.file && !r.load_error) {
      const res = await callRuby('final_view', { file: r.file })
      if (res && res.ok) r.data_url = res.data_url
      else r.load_error = (res && res.error) || 'не удалось загрузить'
    }
  }
}

// Примеси: дополнительные референсы с подписями «что взять».
// Колонка выключена — в задачу ничего не уходит.
function activeMixins() {
  if (!useMixins.value) return []
  return mixins.value
    .filter((m) => m.active !== false)
    .map((m) => ({ path: m.file, file: m.file, caption: m.caption || '', caption_neg: m.caption_neg || '',
      role: m.role || 'auto', weight: Number(m.weight) || 1, apply_to: m.apply_to || 'both', active: true,
      crop: m.crop || null, rotation: Number(m.rotation) || 0 }))
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

function applyMixin({ item, apply_to }) {
  item.apply_to = apply_to
  callRuby('mixins_update', { id: item.id, apply_to })
}

async function transformMixin({ item, crop, rotation }) {
  item.crop = crop
  item.rotation = rotation
  const res = await callRuby('mixins_update', { id: item.id, crop, rotation })
  if (!(res && res.ok)) flash('Не сохранил выделение: ' + ((res && res.error) || 'ошибка'))
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

// Удаление — только по иконке ✕ на картинке. Автоматической чистки нет.
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
const deletePreview = (r) => deleteEntry(r, previews)
const deleteFinal = (r) => deleteEntry(r, finals)

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
  // Студия стартует десятки секунд: допроверяем в фоне до связи.
  for (let i = 0; i < 30 && (!studioStatus.value || !studioStatus.value.ok); i++) {
    await new Promise((r) => setTimeout(r, 2000))
    await checkStudio()
  }
  if (!studioStatus.value || !studioStatus.value.ok) studioStarting.value = false
})
</script>
