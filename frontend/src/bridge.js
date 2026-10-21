// Мост JS <-> Ruby (как в comp_add_view): sketchup.<callback>(id, json),
// ответы пушем window.__dn1Event({type:'result', id, payload}).
const pending = new Map()
const handlers = new Map()
let seq = 0

function su() {
  return typeof window !== 'undefined' ? window.sketchup : undefined
}

function invoke(action, args) {
  const b = su()
  if (!b) return false
  try {
    if (typeof b[action] === 'function') { b[action](...args); return true }
    if (typeof b.callRuby === 'function') { b.callRuby(action, ...args); return true }
    if (typeof b.call_ruby === 'function') { b.call_ruby(action, ...args); return true }
  } catch { /* -> mock */ }
  return false
}

window.__dn1Event = (evt) => {
  if (!evt || typeof evt !== 'object') return
  if (evt.id) {
    const w = pending.get(evt.id)
    if (w) { pending.delete(evt.id); clearTimeout(w.timer); w.resolve(evt.payload); return }
  }
  const list = handlers.get(evt.type)
  if (list) list.forEach((fn) => fn(evt.payload))
}

export function onEvent(type, fn) {
  if (!handlers.has(type)) handlers.set(type, [])
  handlers.get(type).push(fn)
}

export function inSketchup() {
  const b = su()
  return !!b && (typeof b.callRuby === 'function' || Object.keys(b).length > 0)
}

export function callRuby(action, payload) {
  return new Promise((resolve) => {
    const id = `r${++seq}`
    const args = [id]
    if (payload !== undefined) args.push(JSON.stringify(payload))
    if (!invoke(action, args)) { resolve(mockCall(action, payload)); return }
    pending.set(id, {
      resolve,
      timer: setTimeout(() => { if (pending.has(id)) { pending.delete(id); resolve(null) } }, 15000)
    })
  })
}

const mockScenes = [
  { name: 'Сцена 1 — санузел', index: 0, current: true },
  { name: 'Сцена 2 — шкаф', index: 1, current: false }
]

const mockSettings = {
  prompt: 'Photorealistic render based on the provided sketch...',
  seed: -1, seed_locked: false, preview_max: 768, final_mode: 'sketch',
  strength: 1.0, steps: 4, guidance: 1.0, memory_mode: 'balanced',
  allow_oversized: true, suffix: '_photorealistic', ext: 'jpg',
  unsloth_url: 'http://127.0.0.1:8888', unsloth_key: '',
  unsloth_model: 'unsloth/flux-3-image-klein-GGUF',
  unsloth_gguf: 'flux-3-image-klein-UD-Q4_K_XL.gguf',
  sketch_preset: '1024x768', preview_preset: '256', preview_variants: 1,
  final_strength: 0.4, out_dir: '',
  project_state: 'global', project_dir: '', model_name: '',
  final_mode: 'sketch', final_w: 2048, final_h: 1536,
  name_template: '{scene}{suffix}_{date}',
  version: '0.1.0'
}

function mockCall(action, payload) {
  switch (action) {
    case 'settings_get': return { ...mockSettings }
    case 'settings_save': return { ...mockSettings, ...(payload || {}) }
    case 'project_status': return { state: 'global', model_path: '', model_name: '', project_dir: '', out_dir: mockSettings.out_dir, settings_path: '' }
    case 'project_init': return { ok: true, settings: { ...mockSettings, project_state: 'ready', project_dir: 'mock-su2vis' } }
    case 'project_delete': return { ok: true, settings: { ...mockSettings, project_state: 'missing', project_dir: '' } }
    case 'scenes_list': return mockScenes
    case 'scenes_thumb': return { index: payload?.index ?? 0, thumb: null }
    case 'scenes_sync_view': return { index: payload?.index ?? 0, ok: true, thumb: null }
    case 'scenes_capture': return { ok: true, sketches: {} }
    case 'scenes_shot': return { index: payload?.index ?? 0, img: null }
    case 'jobs_start': return { id: 'mock', kind: payload?.kind || 'preview', status: 'done', progress: { done: 1, total: 1 }, results: [], error: null, params: payload }
    case 'jobs_poll': return { id: payload?.id, status: 'done', progress: {}, results: [], error: null }
    case 'jobs_cancel': return { ok: true, id: payload?.id }
    case 'jobs_log': return []
    case 'gallery_list': return []
    case 'gallery_delete': return { ok: true }
    case 'mixins_list': return []
    case 'mixins_add_data': return { ok: true, entry: { id: 'mock-mix.png', file: 'mock-mix.png', name: payload?.name || 'mock', caption: '', active: true, data_url: payload?.data_url } }
    case 'mixins_add_path': return { ok: true, entry: { id: 'mock-mix.png', file: 'mock-mix.png', name: 'mock', caption: '', active: true } }
    case 'mixins_update': return { ok: true, entry: { id: payload?.id, caption: payload?.caption || '', active: payload?.active } }
    case 'mixins_delete': return { ok: true }
    case 'mixins_view': return { ok: true, data_url: null }
    case 'enhance_preview': return { ok: true, enhanced_prompt: 'mock: вне SketchUp — здесь будет текст апсемплера' }
    case 'select_out_dir': return { ok: true, settings: { ...mockSettings, out_dir: 'mock-out' } }
    case 'preview_save': return { ok: true, path: 'mock-prev.png' }
    case 'gen_progress': return { active: false }
    case 'jobs_list': return []
    case 'studio_status': return { ok: false, error: 'mock: вне SketchUp' }
    default: return null
  }
}
