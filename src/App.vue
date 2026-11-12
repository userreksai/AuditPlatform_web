<script setup lang="ts">
import { computed, nextTick, onBeforeUnmount, onMounted, reactive, ref, watch } from 'vue'
import Icon from './Icon.vue'
import { ApiError, csvCell, request } from './api'
import { demoDashboard, demoRDS } from './demo'
import type { AuditUser, Dashboard, Policy, RDSSecret, RDSSecretsView, SyncStatus } from './types'

const demo = new URLSearchParams(location.search).get('demo') === '1'
const authenticated = ref(demo)
const booting = ref(!demo)
const loginBusy = ref(false)
const loginError = ref('')
const login = reactive({ username: 'auditroot', password: '' })
const currentUsername = ref(demo ? 'demo-viewer' : '')
const page = ref('audit')
const mobileMenu = ref(false)
const loading = ref(false)
const loadError = ref('')
const syncBusy = ref(false)
const saving = ref(false)
const toast = ref('')
let toastTimer: ReturnType<typeof setTimeout> | undefined
let pollTimer: ReturnType<typeof setInterval> | undefined
let polling = false
const data = ref<Dashboard>(demo ? demoDashboard() : { accounts: [], users: [], sync: { running: false, started_at: '', last_finished_at: '', next_run_at: '', timezone: 'Asia/Shanghai', schedule: '09:00', last_result: 'never', logs: [] } })
const query = ref('')
const accountFilter = ref('')
const mfaFilter = ref('')
const ipFilter = ref('')
const reviewFilter = ref('')
const currentPage = ref(1)
const pageSize = ref(15)
const selected = ref<AuditUser | null>(null)
const detailTab = ref('overview')
const drawer = ref<HTMLDialogElement | null>(null)
const annotation = reactive({ owner: '', review_status: 'pending', note: '' })

const navigation = [
  { id: 'audit', label: 'IAM 用户审计', icon: 'users' },
  { id: 'accounts', label: 'AWS 账号', icon: 'building' },
  { id: 'secrets', label: 'SecretsManager', icon: 'key' },
  { id: 'logs', label: '获取记录', icon: 'clock' },
]
const pageNames: Record<string, string> = { audit: 'IAM 用户审计', accounts: 'AWS 账号', secrets: 'SecretsManager', logs: '获取记录', guide: '使用说明' }
const columns = [
  { key: 'account_id', label: '账号 ID', width: '160px' },
  { key: 'account_name', label: '账号名称', width: '210px' },
  { key: 'username', label: '用户名', width: '200px' },
  { key: 'owner', label: '负责人', width: '140px' },
  { key: 'review_status', label: '需求检查', width: '130px' },
  { key: 'direct', label: '用户直接权限', width: '220px' },
  { key: 'groups', label: '所属用户组', width: '180px' },
  { key: 'console_access', label: '控制台登录权限', width: '160px' },
  { key: 'mfa_enabled', label: '是否启用 MFA', width: '145px' },
  { key: 'access_keys', label: 'Access Key ID', width: '240px' },
  { key: 'key_status', label: 'Key 状态', width: '130px' },
  { key: 'ip_policy', label: 'IP 限制策略', width: '210px' },
  { key: 'ip_status', label: 'IP 白名单限制', width: '155px' },
  { key: 'ip_explanation', label: 'IP 判断说明', width: '360px' },
  { key: 'ip_ranges', label: 'IP/CIDR 白名单范围', width: '230px' },
  { key: 'secrets_access', label: 'Secrets Manager 读取权限', width: '200px' },
  { key: 'secrets_evidence', label: 'Secrets Manager 权限来源', width: '320px' },
  { key: 'rds_secret_access', label: 'RDS 托管信息查询', width: '200px' },
  { key: 'rds_secret_evidence', label: 'RDS 托管信息查询权限来源', width: '360px' },
  { key: 'inherited', label: '用户组继承权限', width: '260px' },
  { key: 'created_at', label: '创建时间', width: '190px' },
  { key: 'password_last_used', label: '密码最后使用时间', width: '190px' },
  { key: 'user_id', label: '用户 ID', width: '245px' },
]
const visibleKeys = ref(['account_name', 'username', 'owner', 'review_status', 'console_access', 'mfa_enabled', 'direct', 'ip_status', 'ip_ranges', 'secrets_access', 'rds_secret_access', 'access_keys'])
const visibleColumns = computed(() => columns.filter(c => visibleKeys.value.includes(c.key)))
const scopedUsers = computed(() => data.value.users.filter(u => !accountFilter.value || u.account_id === accountFilter.value))
const filteredUsers = computed(() => scopedUsers.value.filter(u => {
  const searchable = [u.username, u.account_name, u.account_id, u.user_id, u.owner, u.arn, ...(u.groups || []), ...(u.ip_ranges || []), ...(u.policies || []).map(p => p.name), ...(u.access_keys || []).map(k => k.id)].join(' ').toLowerCase()
  return (!query.value || searchable.includes(query.value.toLowerCase().trim())) && (!mfaFilter.value || u.mfa_enabled === mfaFilter.value) && (!ipFilter.value || u.ip_status === ipFilter.value) && (!reviewFilter.value || u.review_status === reviewFilter.value)
}))
const pages = computed(() => Math.max(1, Math.ceil(filteredUsers.value.length / pageSize.value)))
const rows = computed(() => filteredUsers.value.slice((currentPage.value - 1) * pageSize.value, currentPage.value * pageSize.value))
const selectedAccountName = computed(() => data.value.accounts.find(a => a.id === accountFilter.value)?.name || '全部 AWS 账号')
const metrics = computed(() => [
  { label: 'IAM 用户总数', value: scopedUsers.value.length, suffix: '位用户', icon: 'users', color: 'blue', foot: `覆盖 ${accountFilter.value ? 1 : data.value.accounts.length} 个 AWS 账号` },
  { label: '可登录控制台', value: scopedUsers.value.filter(u => u.console_access === 'enabled').length, suffix: '位用户', icon: 'grid', color: 'violet', foot: '已创建控制台登录配置' },
  { label: '控制台用户未启用 MFA', value: scopedUsers.value.filter(u => u.console_access === 'enabled' && u.mfa_enabled === 'disabled').length, suffix: '位用户', icon: 'lock', color: 'orange', foot: '建议优先检查登录保护' },
  { label: '未发现 IP 条件', value: scopedUsers.value.filter(u => u.ip_status === 'unrestricted').length, suffix: '位用户', icon: 'shield', color: 'rose', foot: '需结合完整策略进一步审查' },
])
const activeFilterCount = computed(() => [query.value, mfaFilter.value, ipFilter.value, reviewFilter.value].filter(Boolean).length)
const allPolicies = computed(() => selected.value ? [...(selected.value.policies || []), ...(selected.value.permissions_boundary ? [selected.value.permissions_boundary] : [])] : [])

watch([query, accountFilter, mfaFilter, ipFilter, reviewFilter, pageSize], () => { currentPage.value = 1 })
watch(pages, total => { if (currentPage.value > total) currentPage.value = total })
watch(selected, async user => {
  if (!user) { drawer.value?.close(); return }
  detailTab.value = 'overview'
  Object.assign(annotation, { owner: user.owner || '', review_status: user.review_status || 'pending', note: user.note || '' })
  await nextTick()
  if (!drawer.value?.open) drawer.value?.showModal()
})

const displayDate = (value?: string, fallback = '—') => {
  if (!value) return fallback
  const date = new Date(value)
  return Number.isNaN(date.getTime()) ? value : date.toLocaleString('zh-CN', { timeZone: 'Asia/Shanghai', hour12: false, year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit' }).replaceAll('/', '-')
}
const labels: Record<string, string> = { enabled: '已启用', disabled: '未启用', unknown: '未知', restricted: '发现拒绝条件', conditional: '存在条件', unrestricted: '未发现 IP 条件', pending: '待检查', reviewed: '已检查', attention: '需关注', success: '获取成功', partial: '部分成功', error: '获取失败', running: '获取中', never: '尚未获取', Active: '启用', Inactive: '停用', Unknown: '未知' }
const stateLabel = (value: string) => labels[value] || value || '未知'
const secretsLabels: Record<string, string> = { full: '可读取全部 Secret', limited: '可读取（受限/带条件）', denied: '已被拒绝', none: '无读取权限', unknown: '未知' }
const secretsClasses: Record<string, string> = { full: 'error', limited: 'partial', denied: 'success', none: 'success', unknown: 'unknown' }
const secretsLabel = (u: AuditUser) => secretsLabels[u.secrets_access || 'unknown'] || '未知'
const secretsClass = (u: AuditUser) => secretsClasses[u.secrets_access || 'unknown'] || 'unknown'
const rdsAccessLabels: Record<string, string> = { full: '可查询（托管状态+轮换详情）', limited: '可查询（受限/带条件）', rds_only: '仅可查看是否托管', denied: '已被拒绝', none: '无法查询', unknown: '未知' }
const rdsAccessClasses: Record<string, string> = { full: 'enabled', limited: 'partial', rds_only: 'partial', denied: 'disabled', none: 'disabled', unknown: 'unknown' }
const rdsAccessLabel = (u: AuditUser) => rdsAccessLabels[u.rds_secret_access || 'unknown'] || '未知'
const rdsAccessClass = (u: AuditUser) => rdsAccessClasses[u.rds_secret_access || 'unknown'] || 'unknown'
// ---- SecretsManager 页面（RDS 主用户密码托管）
const rdsData = ref<RDSSecretsView>(demo ? demoRDS() : { accounts: [], items: [] })
const rdsError = ref('')
const rdsQuery = ref('')
const rdsAccountFilter = ref('')
const rdsRegionFilter = ref('')
const rdsMigratedFilter = ref('')
const rdsVerdictFilter = ref('')
const rdsPage = ref(1)
const rdsPageSize = ref(15)
const rdsColumns = [
  { key: 'account_name', label: '账号名称', width: '200px' },
  { key: 'account_id', label: 'AWS账号ID', width: '150px' },
  { key: 'region', label: '区域', width: '140px' },
  { key: 'identifier', label: '实例/集群名称', width: '220px' },
  { key: 'master_username', label: '主用户名', width: '140px' },
  { key: 'migrated', label: '是否已迁移至Secrets Manager', width: '210px' },
  { key: 'verdict', label: '迁移核验结论', width: '360px' },
  { key: 'rotation_period', label: '实际轮换周期', width: '150px' },
  { key: 'rotation_enabled', label: '自动轮换', width: '120px' },
  { key: 'last_rotated_at', label: '上次轮换时间（北京时间）', width: '190px' },
  { key: 'next_rotation_at', label: '下次轮换最晚时间（北京时间）', width: '210px' },
]
const verdictLabels: Record<string, string> = { pass: '核验通过', warn: '需关注', fail: '存在问题', not_migrated: '未迁移', unknown: '未能完整核验' }
const verdictClasses: Record<string, string> = { pass: 'success', warn: 'partial', fail: 'error', not_migrated: 'attention', unknown: 'unknown' }
const rotationLabels: Record<string, string> = { enabled: '已开启', disabled: '未开启', unknown: '未知' }
const rotationClasses: Record<string, string> = { enabled: 'success', disabled: 'error', unknown: 'unknown' }
const rdsRegions = computed(() => [...new Set(rdsData.value.items.map(i => i.region))].sort())
const rdsScoped = computed(() => rdsData.value.items.filter(i => !rdsAccountFilter.value || i.account_id === rdsAccountFilter.value))
const rdsFiltered = computed(() => rdsScoped.value.filter(i => {
  const searchable = [i.identifier, i.account_name, i.account_id, i.region, i.master_username, i.engine, i.secret_arn].join(' ').toLowerCase()
  return (!rdsQuery.value || searchable.includes(rdsQuery.value.toLowerCase().trim())) && (!rdsRegionFilter.value || i.region === rdsRegionFilter.value) && (!rdsMigratedFilter.value || i.migrated === rdsMigratedFilter.value) && (!rdsVerdictFilter.value || i.verdict === rdsVerdictFilter.value)
}))
const rdsPages = computed(() => Math.max(1, Math.ceil(rdsFiltered.value.length / rdsPageSize.value)))
const rdsRows = computed(() => rdsFiltered.value.slice((rdsPage.value - 1) * rdsPageSize.value, rdsPage.value * rdsPageSize.value))
const rdsMetrics = computed(() => [
  { label: 'RDS 实例/集群', value: rdsScoped.value.length, suffix: '个', icon: 'grid', color: 'blue', foot: `覆盖 ${rdsAccountFilter.value ? 1 : rdsData.value.accounts.length} 个 AWS 账号` },
  { label: '已迁移至 Secrets Manager', value: rdsScoped.value.filter(i => i.migrated === 'yes').length, suffix: '个', icon: 'key', color: 'violet', foot: '主用户密码由 RDS 托管' },
  { label: '未迁移', value: rdsScoped.value.filter(i => i.migrated === 'no').length, suffix: '个', icon: 'lock', color: 'orange', foot: '仍使用 RDS 本地主密码' },
  { label: '核验需关注/有问题', value: rdsScoped.value.filter(i => ['warn', 'fail', 'unknown'].includes(i.verdict)).length, suffix: '个', icon: 'alert', color: 'rose', foot: '轮换关闭、逾期或状态异常' },
])
const rdsActiveFilters = computed(() => [rdsQuery.value, rdsRegionFilter.value, rdsMigratedFilter.value, rdsVerdictFilter.value].filter(Boolean).length)
watch([rdsQuery, rdsAccountFilter, rdsRegionFilter, rdsMigratedFilter, rdsVerdictFilter, rdsPageSize], () => { rdsPage.value = 1 })
watch(rdsPages, total => { if (rdsPage.value > total) rdsPage.value = total })
const kindLabel = (i: RDSSecret) => i.kind === 'cluster' ? '集群' : '实例'
function rdsText(i: RDSSecret, key: string): string {
  if (key === 'identifier') return `${i.identifier}（${kindLabel(i)}${i.engine ? ` · ${i.engine} ${i.engine_version}`.trimEnd() : ''}）`
  if (key === 'migrated') return i.migrated === 'yes' ? '已迁移' : '未迁移'
  if (key === 'verdict') return `${verdictLabels[i.verdict] || i.verdict}：${i.verdict_text}`
  if (key === 'rotation_period') return i.rotation_period || (i.migrated === 'yes' ? '未提供' : '—')
  if (key === 'rotation_enabled') return rotationLabels[i.rotation_enabled] || '—'
  if (key === 'last_rotated_at') return displayDate(i.last_rotated_at, i.migrated === 'yes' ? '无记录' : '—')
  if (key === 'next_rotation_at') return i.next_rotation_at ? `${displayDate(i.next_rotation_at)}${i.next_rotation_source === 'estimated' ? '（推算）' : ''}` : (i.migrated === 'yes' ? '未提供' : '—')
  return String(i[key as keyof RDSSecret] || '—')
}
function clearRDSFilters() { rdsQuery.value = ''; rdsRegionFilter.value = ''; rdsMigratedFilter.value = ''; rdsVerdictFilter.value = '' }
async function fetchRDS() {
  if (demo) return
  rdsError.value = ''
  try {
    const result = await request<RDSSecretsView>('/api/rds-secrets')
    rdsData.value = { accounts: result.accounts || [], items: (result.items || []).map(i => ({ ...i, warnings: i.warnings || [] })) }
  } catch (error) {
    if (error instanceof ApiError && error.status === 401) authenticated.value = false
    else rdsError.value = error instanceof Error ? error.message : '无法加载 RDS 托管数据'
  }
}
function exportRDSCSV() {
  const text = [rdsColumns.map(c => csvCell(c.label)).join(','), ...rdsFiltered.value.map(i => rdsColumns.map(c => csvCell(rdsText(i, c.key))).join(','))].join('\r\n')
  const link = document.createElement('a')
  const url = URL.createObjectURL(new Blob(['\uFEFF', text], { type: 'text/csv;charset=utf-8;' }))
  link.href = url; link.download = `RDS-SecretsManager${demo ? '-演示' : ''}-${new Date().toISOString().slice(0, 10)}.csv`
  link.click(); URL.revokeObjectURL(url)
  notify(`已导出当前筛选结果 ${rdsFiltered.value.length} 个实例/集群`)
}
const policyTypes: Record<string, string> = { aws_managed: 'AWS 托管', customer_managed: '客户托管', inline: '内联策略', boundary: '权限边界' }
const policyType = (p: Policy) => policyTypes[p.type] || p.type
const policySource = (p: Policy) => p.source === 'group' ? `用户组 · ${p.group_name}` : p.source === 'boundary' ? '权限边界' : '直接绑定'
const ipPolicies = (u: AuditUser) => (u.policies || []).filter(p => p.ip_conditions?.length)
function cellText(u: AuditUser, key: string): string {
  if (key === 'direct') return (u.policies || []).filter(p => p.source === 'direct').map(p => p.name).join('、') || '—'
  if (key === 'inherited') return (u.policies || []).filter(p => p.source === 'group').map(p => `${p.group_name} → ${p.name}`).join('；') || '—'
  if (key === 'access_keys') return (u.access_keys || []).map(k => k.id).join('\n') || (u.warnings?.some(w => /ListAccessKeys|access.?key|访问密钥/i.test(w)) ? '未知 / 采集不完整' : '无 Access Key')
  if (key === 'key_status') return (u.access_keys || []).map(k => `${k.id}: ${stateLabel(k.status)}`).join('\n') || '—'
  if (key === 'ip_policy') return ipPolicies(u).map(p => p.name).join('、') || '—'
  if (key === 'groups') return (u.groups || []).join('、') || '—'
  if (key === 'ip_ranges') return (u.ip_ranges || []).join('\n') || '—'
  if (key === 'secrets_access') return secretsLabel(u)
  if (key === 'secrets_evidence') return (u.secrets_evidence || []).join('\n') || '—'
  if (key === 'rds_secret_access') return rdsAccessLabel(u)
  if (key === 'rds_secret_evidence') return (u.rds_secret_evidence || []).join('\n') || '—'
  if (['console_access', 'mfa_enabled', 'ip_status', 'review_status'].includes(key)) return stateLabel(String(u[key as keyof AuditUser] || 'unknown'))
  if (['created_at', 'password_last_used'].includes(key)) return displayDate(String(u[key as keyof AuditUser] || ''), key === 'password_last_used' ? '无记录 / 未提供' : '未知')
  return String(u[key as keyof AuditUser] || '—')
}
function notify(message: string) {
  toast.value = message
  clearTimeout(toastTimer)
  toastTimer = setTimeout(() => { toast.value = '' }, 4500)
}
async function fetchDashboard() {
  if (demo) return
  loading.value = true; loadError.value = ''
  try {
    const result = await request<Dashboard>('/api/dashboard')
    data.value = { ...result, accounts: result.accounts || [], users: result.users || [], sync: { ...result.sync, logs: result.sync.logs || [] } }
    if (selected.value) selected.value = data.value.users.find(u => u.user_id === selected.value?.user_id && u.account_id === selected.value?.account_id) || null
    await fetchRDS()
  } catch (error) {
    if (error instanceof ApiError && error.status === 401) authenticated.value = false
    else loadError.value = error instanceof Error ? error.message : '无法加载审计数据'
  } finally { loading.value = false }
}
async function signIn() {
  if (!login.username || !login.password) { loginError.value = '请输入账号和密码'; return }
  loginBusy.value = true; loginError.value = ''
  try {
    const result = await request<{ username: string }>('/api/auth/login', { method: 'POST', body: JSON.stringify(login) })
    authenticated.value = true; currentUsername.value = result.username; login.password = ''
    await fetchDashboard()
  } catch (error) { loginError.value = error instanceof Error ? error.message : '登录失败，请重试' }
  finally { loginBusy.value = false }
}
async function signOut() {
  if (demo) { location.href = location.pathname; return }
  try { await request('/api/auth/logout', { method: 'POST' }); authenticated.value = false; selected.value = null }
  catch (error) { notify(error instanceof Error ? error.message : '退出失败') }
}
async function startSync() {
  if (demo) { notify('演示模式不能连接 AWS。请退出演示，配置后端凭证后再获取。'); return }
  syncBusy.value = true
  try {
    const result = await request<{ message: string }>('/api/sync', { method: 'POST' })
    notify(result.message || '全量获取已开始，请在获取记录中查看进度')
    data.value.sync = await request<SyncStatus>('/api/sync/status')
  } catch (error) { notify(error instanceof Error ? error.message : '无法启动获取') }
  finally { syncBusy.value = false }
}
async function pollSync() {
  if (demo || !authenticated.value || polling) return
  polling = true
  try {
    const previous = data.value.sync
    const status = await request<SyncStatus>('/api/sync/status')
    data.value.sync = { ...status, logs: status.logs || [] }
    if ((previous.running && !status.running) || previous.last_finished_at !== status.last_finished_at) await fetchDashboard()
  } catch (error) { if (error instanceof ApiError && error.status === 401) authenticated.value = false }
  finally { polling = false }
}
async function saveAnnotations() {
  if (!selected.value) return
  if (demo) { notify('演示模式仅供查看，审计备注未保存。'); return }
  saving.value = true
  try {
    await request(`/api/users/${encodeURIComponent(selected.value.account_id)}/${encodeURIComponent(selected.value.user_id)}/annotations`, { method: 'PATCH', body: JSON.stringify(annotation) })
    const user = data.value.users.find(u => u.account_id === selected.value?.account_id && u.user_id === selected.value?.user_id)
    if (user) Object.assign(user, annotation)
    Object.assign(selected.value, annotation)
    notify('审计备注已保存')
  } catch (error) { notify(error instanceof Error ? error.message : '保存失败') }
  finally { saving.value = false }
}
function exportCSV() {
  const text = [columns.map(c => csvCell(c.label)).join(','), ...filteredUsers.value.map(u => columns.map(c => csvCell(cellText(u, c.key))).join(','))].join('\r\n')
  const link = document.createElement('a')
  const url = URL.createObjectURL(new Blob(['\uFEFF', text], { type: 'text/csv;charset=utf-8;' }))
  link.href = url; link.download = `AWS-IAM审计${demo ? '-演示' : ''}-${new Date().toISOString().slice(0, 10)}.csv`
  link.click(); URL.revokeObjectURL(url)
  notify(`已导出当前筛选结果 ${filteredUsers.value.length} 位用户，包含全部 ${columns.length} 个字段`)
}
function clearFilters() { query.value = ''; mfaFilter.value = ''; ipFilter.value = ''; reviewFilter.value = '' }
function navigate(id: string) { page.value = id; mobileMenu.value = false }
function selectAccount(id: string) { accountFilter.value = id; page.value = 'audit'; mobileMenu.value = false }
async function copy(value: string) {
  try { await navigator.clipboard.writeText(value); notify('已复制') } catch { notify('浏览器不支持复制，请手动选择文本') }
}
onMounted(async () => {
  if (!demo) {
    try { const me = await request<{ username: string }>('/api/auth/me'); authenticated.value = true; currentUsername.value = me.username; await fetchDashboard() }
    catch (error) { if (!(error instanceof ApiError && error.status === 401)) loginError.value = '后端连接失败，请检查服务是否启动。' }
    finally { booting.value = false }
  }
  pollTimer = setInterval(pollSync, 5000)
})
onBeforeUnmount(() => { clearInterval(pollTimer); clearTimeout(toastTimer) })
</script>

<template>
  <div v-if="booting" class="boot-screen"><div class="brand-mark"><Icon name="shield" :size="30" /></div><div class="loader"></div><p>正在连接审计平台…</p></div>
  <main v-else-if="!authenticated" class="login-shell">
    <section class="login-story">
      <a class="brand login-brand" href="/"><span class="brand-mark"><Icon name="shield" :size="25" /></span><span>云鉴 <small>CLOUD AUDIT</small></span></a>
      <div class="login-pitch"><span class="eyebrow light">AWS IDENTITY & ACCESS AUDIT</span><h1>每一个权限，<br />都有迹可循。</h1><p>从多账号到 IAM 用户，从策略到 IP 条件，<br />让云上身份与访问权限清晰可见。</p>
        <div class="policy-visual"><div class="visual-line"></div><div class="visual-node"><Icon name="cloud" /><span>AWS 账号</span><b>01</b></div><div class="visual-node indent"><Icon name="users" /><span>IAM 用户与用户组</span><b>02</b></div><div class="visual-node indent2"><Icon name="shield" /><span>策略 · IP 条件</span><b>03</b></div></div>
      </div>
      <div class="login-foot"><span class="live-dot"></span>每日北京时间 09:00 自动更新 <span>·</span> SQLite 轻量存储</div>
    </section>
    <section class="login-form-area"><div class="login-card"><span class="eyebrow">WELCOME BACK</span><h2>登录审计工作台</h2><p class="muted">统一查看 AWS 账号与 IAM 用户权限</p><form @submit.prevent="signIn"><label for="username">管理账号</label><div class="input-with-icon"><Icon name="users" :size="18" /><input id="username" v-model="login.username" autocomplete="username" required placeholder="请输入账号" /></div><label for="password">登录密码</label><div class="input-with-icon"><Icon name="lock" :size="18" /><input id="password" v-model="login.password" type="password" autocomplete="current-password" required placeholder="请输入密码" /></div><p v-if="loginError" class="form-error" role="alert"><Icon name="alert" :size="16" />{{ loginError }}</p><button class="btn primary login-submit" :disabled="loginBusy"><Icon :name="loginBusy ? 'refresh' : 'lock'" :class="{ spin: loginBusy }" :size="17" />{{ loginBusy ? '正在登录…' : '登录工作台' }}<Icon name="chevron" :size="17" /></button></form><div class="login-note"><Icon name="shield" :size="16" /><span>管理账号与密码由服务端配置文件维护</span></div></div><p class="login-copyright">云鉴 · AWS 账号审计平台</p></section>
  </main>
  <div v-else class="app-shell">
    <div v-if="mobileMenu" class="mobile-overlay" @click="mobileMenu = false"></div>
    <aside class="sidebar" :class="{ 'mobile-open': mobileMenu }">
      <a class="brand" href="/" @click.prevent="navigate('audit')"><span class="brand-mark"><Icon name="shield" :size="25" /></span><span>云鉴 <small>CLOUD AUDIT</small></span></a>
      <div class="workspace-label">AWS 账号审计平台 <span>PRO</span></div>
      <div class="nav-caption">工作空间</div>
      <nav aria-label="主导航"><button v-for="item in navigation" :key="item.id" class="nav-item" :class="{ active: page === item.id }" @click="navigate(item.id)"><Icon :name="item.icon" :size="19" /><span>{{ item.label }}</span><span v-if="item.id === 'audit'" class="nav-count">{{ data.users.length }}</span><span v-if="item.id === 'logs' && data.sync.running" class="live-dot"></span></button></nav>
      <div class="sidebar-bottom"><div class="schedule-mini"><div><Icon name="clock" :size="17" /><strong>每日自动获取</strong><span class="tag mini green">已配置</span></div><p>北京时间 <b>09:00</b></p><span>Asia/Shanghai · UTC+8</span></div><button class="nav-item help-nav" :class="{ active: page === 'guide' }" @click="navigate('guide')"><Icon name="help" :size="18" />使用说明<Icon name="external" :size="14" /></button><div class="sidebar-version"><span>云鉴审计平台</span><span>v1.0.0</span></div></div>
    </aside>
    <div class="main-shell">
      <header class="topbar"><div class="breadcrumb"><button class="icon-button mobile-toggle" aria-label="打开导航" @click="mobileMenu = true"><Icon name="menu" /></button><Icon name="cloud" :size="18" /><span>工作空间</span><Icon name="chevron" :size="13" /><strong>{{ pageNames[page] }}</strong></div><div class="topbar-right"><span class="environment"><span class="live-dot"></span>{{ demo ? '演示工作空间' : '审计工作空间' }}</span><div class="topbar-divider"></div><span class="avatar">{{ currentUsername.slice(0, 1).toUpperCase() || 'A' }}</span><span class="current-user">{{ currentUsername }}<small>{{ demo ? '只读演示' : '平台管理员' }}</small></span><button class="icon-button logout-button" aria-label="退出登录" title="退出登录" @click="signOut"><Icon name="logout" :size="18" /></button></div></header>
      <div v-if="demo" class="demo-banner"><Icon name="alert" :size="16" /><strong>演示模式</strong><span>当前为示例数据；不会连接 AWS，也不会保存备注或执行获取。</span><a href="/">退出演示</a></div>
      <main class="content">
        <div class="page-heading"><div><div class="eyebrow">IDENTITY & ACCESS MANAGEMENT</div><h1>{{ pageNames[page] }}<span v-if="page === 'audit'" class="heading-pill">IAM</span></h1><p>{{ page === 'audit' ? '以 IAM 用户为核心，追溯每一项权限与 IP 访问条件。' : page === 'accounts' ? '集中查看多账号接入状态与最近一次数据获取结果。' : page === 'secrets' ? '核验 RDS 主用户密码是否已迁移至 Secrets Manager 托管，以及自动轮换的周期与时间。' : page === 'logs' ? '追踪手动与定时获取任务，掌握每个账号的更新情况。' : '了解数据来源、权限关系与部署后的使用方式。' }}</p></div><div class="heading-actions"><button v-if="page === 'audit'" class="btn" :disabled="!filteredUsers.length" @click="exportCSV"><Icon name="download" :size="17" />导出 CSV</button><button v-if="page === 'secrets'" class="btn" :disabled="!rdsFiltered.length" @click="exportRDSCSV"><Icon name="download" :size="17" />导出 CSV</button><button class="btn primary" :disabled="syncBusy || data.sync.running" @click="startSync"><Icon name="refresh" :size="17" :class="{ spin: data.sync.running || syncBusy }" />{{ data.sync.running ? '正在获取…' : '立即全部获取' }}</button></div></div>
        <div v-if="loadError" class="notice error" role="alert"><Icon name="alert" :size="18" /><span>{{ loadError }}</span><button @click="fetchDashboard">重新加载</button></div>
        <div v-if="data.accounts.some(a => a.status === 'error' || a.status === 'partial')" class="notice warning"><Icon name="alert" :size="18" /><span>部分账号获取不完整，页面保留最近一次有效快照。请查看账号状态与获取记录。</span><button @click="navigate('accounts')">查看账号</button></div>

        <template v-if="page === 'audit'">
          <section class="metrics-grid" aria-label="审计概览"><article v-for="metric in metrics" :key="metric.label" class="metric-card"><div class="metric-top"><span>{{ metric.label }}</span><span class="metric-icon" :class="metric.color"><Icon :name="metric.icon" :size="20" /></span></div><div class="metric-number">{{ loading && !data.users.length ? '—' : metric.value }}<small>{{ metric.suffix }}</small></div><div class="metric-foot"><span :class="['metric-dot', metric.color]"></span>{{ metric.foot }}</div></article></section>
          <section class="sync-strip"><span class="sync-strip-icon"><Icon name="refresh" :size="18" :class="{ spin: data.sync.running }" /></span><div class="sync-strip-copy"><strong>{{ data.sync.running ? '全量获取进行中' : '数据获取计划' }}</strong><span>每日北京时间 <b>{{ data.sync.schedule || '09:00' }}</b> 自动更新</span></div><span class="sync-strip-separator"></span><div class="sync-timestamp">最近完成 <strong>{{ displayDate(data.sync.last_finished_at, '尚未获取') }}</strong></div><div class="sync-timestamp next-sync">下次计划 <strong>{{ displayDate(data.sync.next_run_at, '由服务端计算') }}</strong></div><button @click="navigate('logs')">查看记录<Icon name="chevron" :size="14" /></button></section>
          <section class="table-panel">
            <div class="panel-heading"><div><h2>IAM 用户清单 <span>{{ filteredUsers.length }}</span></h2><p>用户 · 用户组 · 策略 · IP 条件，一处掌握</p></div><details class="columns-menu"><summary class="btn small"><Icon name="columns" :size="16" />显示字段<span>{{ visibleKeys.length }}/{{ columns.length }}</span><Icon name="down" :size="13" /></summary><div class="columns-popover"><div class="popover-heading"><strong>显示字段</strong><button @click="visibleKeys = columns.map(c => c.key)">显示全部</button></div><label v-for="col in columns" :key="col.key"><input v-model="visibleKeys" type="checkbox" :value="col.key" :disabled="visibleKeys.length === 1 && visibleKeys.includes(col.key)" />{{ col.label }}</label><small>完整字段始终包含在用户详情与 CSV 中</small></div></details></div>
            <div class="filters"><div class="search-field"><Icon name="search" :size="18" /><input v-model="query" aria-label="搜索用户、账号、策略或 IP" placeholder="搜索用户名、账号、策略或 IP…" /><button v-if="query" aria-label="清除搜索" @click="query = ''"><Icon name="close" :size="15" /></button><kbd>/</kbd></div><label class="select-filter"><span class="sr-only">AWS 账号</span><select v-model="accountFilter"><option value="">全部 AWS 账号</option><option v-for="account in data.accounts" :key="account.id" :value="account.id">{{ account.name }}</option></select><Icon name="down" :size="13" /></label><label class="select-filter"><span class="sr-only">MFA 状态</span><select v-model="mfaFilter"><option value="">MFA 状态</option><option value="enabled">MFA 已启用</option><option value="disabled">MFA 未启用</option><option value="unknown">MFA 未知</option></select><Icon name="down" :size="13" /></label><label class="select-filter"><span class="sr-only">IP 条件</span><select v-model="ipFilter"><option value="">IP 条件</option><option value="restricted">发现拒绝条件</option><option value="conditional">存在条件</option><option value="unrestricted">未发现 IP 条件</option><option value="unknown">未知</option></select><Icon name="down" :size="13" /></label><label class="select-filter review-filter"><span class="sr-only">需求检查</span><select v-model="reviewFilter"><option value="">需求检查</option><option value="pending">待检查</option><option value="reviewed">已检查</option><option value="attention">需关注</option></select><Icon name="down" :size="13" /></label><button v-if="activeFilterCount" class="text-button" @click="clearFilters">重置</button></div>
            <div class="table-context"><span><span class="status-dot success"></span>{{ selectedAccountName }}<span class="context-divider">/</span>{{ filteredUsers.length }} 位 IAM 用户</span><span><Icon name="columns" :size="13" />横向滚动查看更多字段 · 点击用户名查看完整关系</span></div>
            <div v-if="loading && !data.users.length" class="table-loading"><div v-for="i in 6" :key="i" class="skeleton-row"><span v-for="j in 5" :key="j"></span></div></div>
            <div v-else-if="!filteredUsers.length" class="empty-state"><div class="empty-icon"><Icon :name="data.users.length ? 'search' : 'shield'" :size="36" /></div><h3>{{ data.users.length ? '没有匹配的 IAM 用户' : data.accounts.length ? '等待首次数据获取' : '接入你的第一个 AWS 账号' }}</h3><p>{{ data.users.length ? '尝试调整搜索关键词或筛选条件。' : data.accounts.length ? '点击“立即全部获取”，从已配置的账号读取 IAM 权限。' : '在后端 config.yaml 的 accounts 中填写 Access Key，重启服务后开始获取。' }}</p><button v-if="data.users.length" class="btn" @click="clearFilters">清除筛选</button><button v-else class="btn" @click="navigate('guide')">查看配置说明<Icon name="chevron" :size="15" /></button></div>
            <div v-else class="table-scroll" tabindex="0" aria-label="IAM 用户审计表，可横向滚动"><table><thead><tr><th v-for="col in visibleColumns" :key="col.key" :style="{ minWidth: col.width }">{{ col.label }}<span v-if="col.key === 'username'" class="header-sort">↓</span></th><th class="action-col">操作</th></tr></thead><tbody><tr v-for="user in rows" :key="`${user.account_id}/${user.user_id}`"><td v-for="col in visibleColumns" :key="col.key" :class="{ mono: ['account_id', 'user_id', 'access_keys', 'ip_ranges'].includes(col.key) }"><template v-if="col.key === 'username'"><button class="user-cell" @click="selected = user"><span class="user-avatar">{{ user.username.slice(0, 1).toUpperCase() }}</span><span><strong>{{ user.username }}</strong><small>IAM 用户</small></span></button></template><template v-else-if="col.key === 'account_name'"><div class="account-cell"><strong>{{ user.account_name }}</strong><small class="mono">{{ user.account_id }}</small></div></template><span v-else-if="col.key === 'secrets_access'" class="tag" :class="secretsClass(user)" :title="user.secrets_explanation"><span class="tag-dot"></span>{{ secretsLabel(user) }}</span><span v-else-if="col.key === 'rds_secret_access'" class="tag" :class="rdsAccessClass(user)" :title="user.rds_secret_explanation"><span class="tag-dot"></span>{{ rdsAccessLabel(user) }}</span><span v-else-if="['mfa_enabled', 'console_access', 'ip_status', 'review_status'].includes(col.key)" class="tag" :class="String(user[col.key as keyof AuditUser] || 'unknown')"><span class="tag-dot"></span>{{ cellText(user, col.key) }}</span><template v-else-if="col.key === 'direct'"><div class="policy-cell"><span v-for="policy in user.policies?.filter(p => p.source === 'direct').slice(0, 2)" :key="policy.id" class="policy-chip"><Icon name="file" :size="12" />{{ policy.name }}</span><span v-if="user.policies?.filter(p => p.source === 'direct').length > 2" class="muted">+{{ user.policies.filter(p => p.source === 'direct').length - 2 }}</span><span v-if="!user.policies?.some(p => p.source === 'direct')" class="muted">—</span></div></template><span v-else :title="cellText(user, col.key)" class="cell-value">{{ cellText(user, col.key) }}</span></td><td class="action-col"><button class="row-detail" @click="selected = user" :aria-label="`查看 ${user.username} 的详情`">详情<Icon name="chevron" :size="13" /></button></td></tr></tbody></table></div>
            <div class="pagination"><span>共 <strong>{{ filteredUsers.length }}</strong> 位用户<span class="pagination-range" v-if="filteredUsers.length">，显示 {{ (currentPage - 1) * pageSize + 1 }}–{{ Math.min(currentPage * pageSize, filteredUsers.length) }}</span></span><div><label>每页 <select v-model.number="pageSize" aria-label="每页条数"><option :value="15">15</option><option :value="30">30</option><option :value="50">50</option></select> 条</label><button class="page-arrow" aria-label="上一页" :disabled="currentPage === 1" @click="currentPage--"><Icon name="chevron" :size="15" class="rotate" /></button><span class="page-number">{{ currentPage }}</span><span class="muted">/ {{ pages }}</span><button class="page-arrow" aria-label="下一页" :disabled="currentPage >= pages" @click="currentPage++"><Icon name="chevron" :size="15" /></button></div></div>
          </section>
          <div class="evidence-note"><Icon name="help" :size="16" /><p>IP 结果为策略条件摘要，不代表最终有效授权。完整判断还需结合 SCP、资源策略、权限边界及请求上下文；“未发现”不等于无限制。</p></div>
        </template>

        <template v-else-if="page === 'accounts'"><div class="section-toolbar"><span>已配置 <b>{{ data.accounts.length }}</b> 个账号</span><button class="btn small" :disabled="loading" @click="fetchDashboard"><Icon name="refresh" :size="15" />刷新状态</button></div><div class="accounts-grid"><article v-for="(account, i) in data.accounts" :key="account.id" class="account-card"><div class="account-card-top"><span class="account-large-icon" :class="`color-${i % 3}`"><Icon name="cloud" :size="28" /></span><span class="tag" :class="account.status">{{ stateLabel(account.status) }}</span></div><h2>{{ account.name }}</h2><p class="mono">{{ account.id }}</p><dl><div><dt>账号别名</dt><dd>{{ account.alias || '未设置' }}</dd></div><div><dt>负责人</dt><dd>{{ account.owner || '未设置' }}</dd></div><div><dt>IAM 用户</dt><dd>{{ account.user_count }} 位</dd></div><div><dt>最近更新</dt><dd>{{ displayDate(account.last_synced_at, '尚未获取') }}</dd></div></dl><p v-if="account.error" class="account-error"><Icon name="alert" :size="15" />{{ account.error }}</p><button class="account-card-link" @click="selectAccount(account.id)">查看 IAM 用户<Icon name="chevron" :size="16" /></button></article></div><div v-if="!data.accounts.length" class="table-panel empty-state"><div class="empty-icon"><Icon name="cloud" :size="36" /></div><h3>尚未配置 AWS 账号</h3><p>在服务端配置文件中添加 accounts，支持配置多个账号的 Access Key。</p><button class="btn" @click="navigate('guide')">查看配置说明</button></div><div class="notice neutral"><Icon name="lock" :size="18" /><span>AWS Access Key 仅保存在服务端配置文件中，前端不会读取或展示密钥。</span></div></template>

        <template v-else-if="page === 'secrets'">
          <div v-if="rdsError" class="notice error" role="alert"><Icon name="alert" :size="18" /><span>{{ rdsError }}</span><button @click="fetchRDS">重新加载</button></div>
          <div v-if="rdsData.accounts.some(a => a.status === 'error' || a.status === 'partial')" class="notice warning"><Icon name="alert" :size="18" /><span>部分账号的 RDS 托管信息获取不完整：<template v-for="a in rdsData.accounts.filter(x => x.status === 'error' || x.status === 'partial')" :key="a.account_id">{{ a.account_name }}（{{ a.error || stateLabel(a.status) }}） </template></span></div>
          <section class="metrics-grid" aria-label="RDS 托管概览"><article v-for="metric in rdsMetrics" :key="metric.label" class="metric-card"><div class="metric-top"><span>{{ metric.label }}</span><span class="metric-icon" :class="metric.color"><Icon :name="metric.icon" :size="20" /></span></div><div class="metric-number">{{ metric.value }}<small>{{ metric.suffix }}</small></div><div class="metric-foot"><span :class="['metric-dot', metric.color]"></span>{{ metric.foot }}</div></article></section>
          <section class="table-panel">
            <div class="panel-heading"><div><h2>RDS 主用户密码托管清单 <span>{{ rdsFiltered.length }}</span></h2><p>实例 / 集群 · MasterUserSecret · 轮换配置（只读元数据，不读取密码）</p></div><button class="btn small" :disabled="loading" @click="fetchRDS"><Icon name="refresh" :size="15" />刷新</button></div>
            <div class="filters"><div class="search-field"><Icon name="search" :size="18" /><input v-model="rdsQuery" aria-label="搜索实例、账号、主用户名" placeholder="搜索实例/集群、账号、主用户名…" /><button v-if="rdsQuery" aria-label="清除搜索" @click="rdsQuery = ''"><Icon name="close" :size="15" /></button></div><label class="select-filter"><span class="sr-only">AWS 账号</span><select v-model="rdsAccountFilter"><option value="">全部 AWS 账号</option><option v-for="account in rdsData.accounts" :key="account.account_id" :value="account.account_id">{{ account.account_name }}</option></select><Icon name="down" :size="13" /></label><label class="select-filter"><span class="sr-only">区域</span><select v-model="rdsRegionFilter"><option value="">全部区域</option><option v-for="region in rdsRegions" :key="region" :value="region">{{ region }}</option></select><Icon name="down" :size="13" /></label><label class="select-filter"><span class="sr-only">是否已迁移</span><select v-model="rdsMigratedFilter"><option value="">是否已迁移</option><option value="yes">已迁移</option><option value="no">未迁移</option></select><Icon name="down" :size="13" /></label><label class="select-filter"><span class="sr-only">核验结论</span><select v-model="rdsVerdictFilter"><option value="">核验结论</option><option v-for="(label, key) in verdictLabels" :key="key" :value="key">{{ label }}</option></select><Icon name="down" :size="13" /></label><button v-if="rdsActiveFilters" class="text-button" @click="clearRDSFilters">重置</button></div>
            <div v-if="!rdsFiltered.length" class="empty-state"><div class="empty-icon"><Icon :name="rdsData.items.length ? 'search' : 'key'" :size="36" /></div><h3>{{ rdsData.items.length ? '没有匹配的实例/集群' : '暂无 RDS 托管数据' }}</h3><p>{{ rdsData.items.length ? '尝试调整搜索关键词或筛选条件。' : '点击“立即全部获取”采集；采集身份需 rds:DescribeDBInstances、rds:DescribeDBClusters、secretsmanager:DescribeSecret，区域由账号配置 rds_regions 决定。' }}</p><button v-if="rdsData.items.length" class="btn" @click="clearRDSFilters">清除筛选</button></div>
            <div v-else class="table-scroll" tabindex="0" aria-label="RDS 主用户密码托管表，可横向滚动"><table><thead><tr><th v-for="col in rdsColumns" :key="col.key" :style="{ minWidth: col.width }">{{ col.label }}</th></tr></thead><tbody><tr v-for="item in rdsRows" :key="`${item.account_id}/${item.region}/${item.kind}/${item.identifier}`">
              <td v-for="col in rdsColumns" :key="col.key" :class="{ mono: ['account_id', 'region', 'master_username'].includes(col.key) }">
                <div v-if="col.key === 'identifier'" class="account-cell"><strong>{{ item.identifier }}</strong><small>{{ kindLabel(item) }}<template v-if="item.engine"> · {{ item.engine }} {{ item.engine_version }}</template></small></div>
                <span v-else-if="col.key === 'migrated'" class="tag" :class="item.migrated === 'yes' ? 'success' : 'error'" :title="item.secret_arn"><span class="tag-dot"></span>{{ rdsText(item, 'migrated') }}</span>
                <div v-else-if="col.key === 'verdict'" class="verdict-cell"><span class="tag" :class="verdictClasses[item.verdict] || 'unknown'"><span class="tag-dot"></span>{{ verdictLabels[item.verdict] || item.verdict }}</span><small>{{ item.verdict_text }}</small></div>
                <span v-else-if="col.key === 'rotation_enabled'" class="tag" :class="rotationClasses[item.rotation_enabled] || 'neutral'"><span class="tag-dot"></span>{{ rdsText(item, 'rotation_enabled') }}</span>
                <span v-else class="cell-value" :title="col.key === 'rotation_period' && item.rotation_schedule ? `${item.rotation_schedule}${item.rotation_window ? ' · 窗口 ' + item.rotation_window : ''}` : rdsText(item, col.key)">{{ rdsText(item, col.key) }}</span>
              </td></tr></tbody></table></div>
            <div v-if="rdsFiltered.length" class="pagination"><span>共 <strong>{{ rdsFiltered.length }}</strong> 个实例/集群</span><div><label>每页 <select v-model.number="rdsPageSize" aria-label="每页条数"><option :value="15">15</option><option :value="30">30</option><option :value="50">50</option></select> 条</label><button class="page-arrow" aria-label="上一页" :disabled="rdsPage === 1" @click="rdsPage--"><Icon name="chevron" :size="15" class="rotate" /></button><span class="page-number">{{ rdsPage }}</span><span class="muted">/ {{ rdsPages }}</span><button class="page-arrow" aria-label="下一页" :disabled="rdsPage >= rdsPages" @click="rdsPage++"><Icon name="chevron" :size="15" /></button></div></div>
          </section>
          <div class="evidence-note"><Icon name="help" :size="16" /><p>“已迁移”以 RDS 返回的 MasterUserSecret 为准；轮换信息来自 Secrets Manager DescribeSecret，不读取密码值。“下次轮换最晚时间”取 AWS 的 NextRotationDate（在此时间或之前轮换），AWS 未返回时按上次轮换 + 周期推算并标注。时间均为北京时间。</p></div>
        </template>

        <template v-else-if="page === 'logs'"><section class="schedule-card"><div class="schedule-card-icon"><Icon name="clock" :size="30" /></div><div><span class="eyebrow">AUTOMATIC COLLECTION</span><h2>每日北京时间 {{ data.sync.schedule || '09:00' }}</h2><p>下次计划：{{ displayDate(data.sync.next_run_at, '等待服务端计算') }} · Asia/Shanghai</p></div><span class="tag" :class="data.sync.running ? 'running' : 'success'">{{ data.sync.running ? '正在获取' : '定时计划已配置' }}</span></section><section class="table-panel logs-panel"><div class="panel-heading"><div><h2>获取记录 <span>{{ data.sync.logs?.length || 0 }}</span></h2><p>自动获取和手动获取共用同一任务锁，避免重复执行</p></div><button class="btn small" @click="fetchDashboard"><Icon name="refresh" :size="15" />刷新</button></div><div v-if="!data.sync.logs?.length" class="empty-state"><div class="empty-icon"><Icon name="clock" :size="34" /></div><h3>还没有获取记录</h3><p>首次获取后，可以在这里查看任务状态和失败原因。</p></div><div v-else class="table-scroll"><table><thead><tr><th>任务开始时间（北京时间）</th><th>触发方式</th><th>获取结果</th><th>成功 / 总账号</th><th>任务结束时间</th><th>说明</th></tr></thead><tbody><tr v-for="log in data.sync.logs" :key="log.id"><td class="mono">{{ displayDate(log.started_at) }}</td><td><span class="tag neutral">{{ log.trigger === 'scheduled' || log.trigger === 'schedule' ? '每日定时' : '手动获取' }}</span></td><td><span class="tag" :class="log.status"><span class="tag-dot"></span>{{ stateLabel(log.status) }}</span></td><td>{{ log.accounts_succeeded }} / {{ log.accounts_total }}</td><td class="mono">{{ displayDate(log.finished_at, log.status === 'running' ? '执行中' : '—') }}</td><td class="log-error">{{ log.error || '—' }}</td></tr></tbody></table></div></section></template>

        <template v-else><div class="guide-grid"><article class="guide-card"><span class="guide-number">01</span><h2>配置账号与登录信息</h2><p>在后端 <code>config.yaml</code> 配置管理员账号、密码与多个 AWS Access Key。默认管理账号为 <code>auditroot</code>，密码由服务端配置维护。修改配置后重启服务。</p><p>账号名称来自配置或 AWS 账号别名；负责人和需求检查可在用户详情中维护。</p><button class="text-button" @click="navigate('accounts')">查看已配置账号 →</button></article><article class="guide-card"><span class="guide-number">02</span><h2>每日更新，也可立即获取</h2><p>后端每日北京时间 <b>09:00</b> 执行全量采集，不依赖浏览器打开。点击右上角“立即全部获取”可立即触发一次任务。</p><p>采集失败的账号保留最近有效数据。凭证报告可能由 AWS 复用最多四小时内的报告，具体来源说明见用户详情。</p></article><article class="guide-card wide"><span class="guide-number">03</span><h2>追溯权限关系</h2><div class="relation-flow"><span><Icon name="cloud" :size="18" />AWS 主账号</span><Icon name="chevron" :size="17" /><span><Icon name="users" :size="18" />IAM 用户</span><Icon name="chevron" :size="17" /><span><Icon name="file" :size="18" />直接 / 用户组策略</span><Icon name="chevron" :size="17" /><span><Icon name="shield" :size="18" />IP 等条件</span></div><p>用户详情保留原始策略文档，以及每条 IP 条件的 Effect、运算符、条件键和 IP/CIDR 原值。权限边界单独展示，不视为权限授予。</p><div class="guide-definitions"><div><b>Deny + NotIpAddress</b><p>通常拒绝来自所列 IP 范围之外的请求；需核对其余条件。</p></div><div><b>Allow + IpAddress</b><p>仅为这条授权的 IP 条件，不能推断用户的全局白名单。</p></div><div><b>Deny + IpAddress</b><p>拒绝指定范围，是黑名单条件，不能当作允许范围。</p></div></div><p class="small-muted">本平台不模拟最终权限评估，未评估的 SCP、资源策略、会话策略及请求上下文可能影响结果。Root 不是 IAM 用户，不计入用户清单。MFA 已启用表示已绑定设备，不代表所有访问都强制 MFA。</p></article></div></template>
        <footer class="content-footer"><span>云鉴 · AWS 账号审计平台</span><span><Icon name="lock" :size="12" />凭证保留在服务端 · 所有时间均为北京时间</span></footer>
      </main>
    </div>
    <dialog ref="drawer" class="detail-drawer" @close="selected = null" @click="(event) => { if (event.target === drawer) selected = null }">
      <div v-if="selected" class="drawer-inner"><header class="drawer-header"><div><div class="eyebrow">IAM USER DETAIL</div><h2><span class="user-avatar large">{{ selected.username.slice(0, 1).toUpperCase() }}</span>{{ selected.username }}</h2><p>{{ selected.account_name }} <span class="mono">{{ selected.account_id }}</span></p></div><button class="icon-button" aria-label="关闭用户详情" @click="selected = null"><Icon name="close" :size="22" /></button></header><div class="drawer-tabs" role="tablist" aria-label="用户详情"><button v-for="tab in [{id:'overview',label:'用户概览'},{id:'policies',label:`权限策略 ${allPolicies.length}`},{id:'credentials',label:'安全凭证'},{id:'notes',label:'审计备注'}]" :key="tab.id" :class="{ active: detailTab === tab.id }" role="tab" :aria-selected="detailTab === tab.id" @click="detailTab = tab.id">{{ tab.label }}</button></div><div class="drawer-body">
        <template v-if="detailTab === 'overview'"><div class="detail-summary"><span class="tag" :class="selected.review_status">{{ stateLabel(selected.review_status) }}</span><span class="tag" :class="selected.ip_status">{{ stateLabel(selected.ip_status) }}</span><span class="tag" :class="selected.mfa_enabled">MFA {{ stateLabel(selected.mfa_enabled) }}</span></div><h3 class="detail-section-title">身份信息</h3><dl class="detail-facts"><div><dt>账号 ID</dt><dd class="mono">{{ selected.account_id }}</dd></div><div><dt>账号名称</dt><dd>{{ selected.account_name }}</dd></div><div><dt>用户名</dt><dd>{{ selected.username }}</dd></div><div><dt>负责人</dt><dd>{{ selected.owner || '未设置' }}</dd></div><div class="full"><dt>用户 ID</dt><dd class="mono">{{ selected.user_id }}<button class="copy-button" aria-label="复制用户 ID" @click="copy(selected!.user_id)"><Icon name="copy" :size="14" /></button></dd></div><div class="full"><dt>用户 ARN</dt><dd class="mono wrap-anywhere">{{ selected.arn }}</dd></div><div><dt>创建时间</dt><dd>{{ displayDate(selected.created_at, '未知') }}</dd></div><div><dt>密码最后使用时间</dt><dd>{{ displayDate(selected.password_last_used, '未使用 / 未提供') }}</dd></div><div><dt>控制台登录权限</dt><dd>{{ stateLabel(selected.console_access) }}</dd></div><div><dt>是否启用 MFA</dt><dd>{{ stateLabel(selected.mfa_enabled) }}</dd></div></dl><h3 class="detail-section-title">权限来源</h3><div class="permission-source"><div><Icon name="users" :size="18" /><span>所属用户组</span><strong>{{ selected.groups?.join('、') || '未加入用户组' }}</strong></div><div><Icon name="file" :size="18" /><span>用户直接权限</span><strong>{{ cellText(selected, 'direct') }}</strong></div><div><Icon name="shield" :size="18" /><span>用户组继承权限</span><strong>{{ cellText(selected, 'inherited') }}</strong></div></div><h3 class="detail-section-title">IP 限制证据</h3><div class="ip-evidence"><div><span class="tag" :class="selected.ip_status">{{ stateLabel(selected.ip_status) }}</span><span>条件摘要</span></div><p>{{ selected.ip_explanation || '暂无可判断的 IP 条件证据。' }}</p><div v-for="policy in ipPolicies(selected)" :key="policy.id" class="evidence-policy"><strong>{{ policy.name }}</strong><small>{{ policySource(policy) }}</small><div v-for="(condition, index) in policy.ip_conditions" :key="index"><div class="condition-meta"><span>{{ condition.effect }}</span><code>{{ condition.operator }}</code><code>{{ condition.key }}</code></div><div class="cidr-list"><code v-for="value in condition.values" :key="value">{{ value }}</code></div><p>{{ condition.interpretation }}</p></div></div><p class="small-muted">这些范围是条件原值，可能是白名单、黑名单或局部授权条件。请结合 Effect 和运算符判断。</p></div><h3 class="detail-section-title">Secrets Manager 读取权限</h3><div class="ip-evidence"><div><span class="tag" :class="secretsClass(selected)">{{ secretsLabel(selected) }}</span><span>secretsmanager:GetSecretValue</span></div><p>{{ selected.secrets_explanation || '暂无数据，请重新获取。' }}</p><div v-if="selected.secrets_evidence?.length" class="evidence-policy"><p v-for="item in selected.secrets_evidence" :key="item">{{ item }}</p></div></div><h3 class="detail-section-title">RDS 托管信息查询权限</h3><div class="ip-evidence"><div><span class="tag" :class="rdsAccessClass(selected)">{{ rdsAccessLabel(selected) }}</span><span>rds:DescribeDB* · secretsmanager:DescribeSecret</span></div><p>{{ selected.rds_secret_explanation || '暂无数据，请重新获取。' }}</p><div v-if="selected.rds_secret_evidence?.length" class="evidence-policy"><p v-for="item in selected.rds_secret_evidence" :key="item">{{ item }}</p></div></div><button class="btn full-width" @click="detailTab = 'policies'">查看完整策略与条件<Icon name="chevron" :size="16" /></button><div v-if="selected.warnings?.length" class="detail-warnings"><h4><Icon name="alert" :size="16" />数据来源与限制</h4><p v-for="warning in selected.warnings" :key="warning">{{ warning }}</p></div></template>
        <template v-else-if="detailTab === 'policies'"><div class="notice warning"><Icon name="help" :size="18" /><span>以下为策略证据，不是最终有效权限。权限边界不授予权限；IP 条件需结合完整语句判断。</span></div><div class="policy-tree-root"><Icon name="cloud" :size="17" />{{ selected.account_name }}<Icon name="chevron" :size="13" /><Icon name="users" :size="17" />{{ selected.username }}</div><div v-if="!allPolicies.length" class="empty-state compact"><Icon name="file" :size="30" /><h3>暂无策略数据</h3><p>请确认采集已完成，并查看数据来源警告。</p></div><details v-for="(policy, index) in allPolicies" :key="`${policy.source}/${policy.group_name}/${policy.id}/${index}`" class="policy-detail" :open="!!policy.ip_conditions?.length"><summary><span class="policy-tree-icon"><Icon name="file" :size="18" /></span><span><strong>{{ policy.name }}</strong><small>{{ policySource(policy) }} · {{ policyType(policy) }}</small></span><span v-if="policy.ip_conditions?.length" class="tag mini conditional">IP 条件 {{ policy.ip_conditions.length }}</span><Icon name="down" :size="16" /></summary><div class="policy-detail-content"><div v-if="policy.arn" class="policy-arn mono">{{ policy.arn }}</div><div v-if="policy.source === 'boundary'" class="notice warning"><Icon name="alert" :size="16" /><span>权限边界仅限制可授予权限的上限。</span></div><section v-for="(condition, i) in policy.ip_conditions" :key="i" class="condition-card"><div class="condition-title"><strong>{{ condition.sid || `条件 ${i + 1}` }}</strong><span class="tag mini" :class="condition.effect === 'Deny' ? 'attention' : 'conditional'">{{ condition.effect }}</span></div><dl><div><dt>运算符</dt><dd><code>{{ condition.operator }}</code></dd></div><div><dt>条件键</dt><dd><code>{{ condition.key }}</code></dd></div></dl><div class="cidr-list"><code v-for="value in condition.values" :key="value">{{ value }}</code></div><p>{{ condition.interpretation }}</p></section><p v-if="!policy.ip_conditions?.length" class="small-muted">该策略中未提取到 IP 条件；请查看原始策略中的其他条件。</p><p v-for="warning in policy.warnings" :key="warning" class="policy-warning">{{ warning }}</p><h4 class="json-title">原始策略文档 <button @click="copy(JSON.stringify(policy.document, null, 2))"><Icon name="copy" :size="13" />复制</button></h4><pre class="json-view">{{ JSON.stringify(policy.document, null, 2) }}</pre></div></details></template>
        <template v-else-if="detailTab === 'credentials'"><h3 class="detail-section-title first">控制台与 MFA</h3><dl class="detail-facts"><div><dt>控制台登录权限</dt><dd><span class="tag" :class="selected.console_access">{{ stateLabel(selected.console_access) }}</span></dd></div><div><dt>MFA 设备</dt><dd><span class="tag" :class="selected.mfa_enabled">{{ stateLabel(selected.mfa_enabled) }}</span></dd></div><div class="full"><dt>密码最后使用时间</dt><dd>{{ displayDate(selected.password_last_used, '未使用 / 未提供') }}</dd></div></dl><p class="small-muted">MFA 已启用表示已绑定 MFA 设备，不代表所有 API 调用都强制使用 MFA。</p><h3 class="detail-section-title">Access Key <span>{{ selected.access_keys?.length || 0 }}</span></h3><p v-if="!selected.access_keys?.length" class="small-muted">未采集到 Access Key；如有数据警告，请先检查采集完整性。</p><article v-for="key in selected.access_keys" :key="key.id" class="key-card"><div><Icon name="key" :size="18" /><strong class="mono">{{ key.id }}</strong><span class="tag mini" :class="key.status === 'Active' ? 'success' : 'neutral'">{{ stateLabel(key.status) }}</span></div><dl><div><dt>创建时间</dt><dd>{{ displayDate(key.created_at) }}</dd></div><div><dt>最后使用</dt><dd>{{ displayDate(key.last_used_at, '未使用 / 未提供') }}</dd></div><div><dt>最近服务</dt><dd>{{ key.last_used_service || '—' }}</dd></div><div><dt>最近区域</dt><dd>{{ key.last_used_region || '—' }}</dd></div></dl></article><div v-if="selected.warnings?.length" class="detail-warnings"><h4>来源与完整性</h4><p v-for="warning in selected.warnings" :key="warning">{{ warning }}</p></div></template>
        <template v-else><h3 class="detail-section-title first">审计备注</h3><p class="small-muted">负责人、需求检查与备注由本平台维护，数据获取时会保留。</p><form class="annotation-form" @submit.prevent="saveAnnotations"><label for="owner">负责人</label><input id="owner" v-model="annotation.owner" maxlength="200" placeholder="输入负责人或团队" /><label for="review">需求检查</label><select id="review" v-model="annotation.review_status"><option value="pending">待检查</option><option value="reviewed">已检查</option><option value="attention">需关注</option></select><label for="note">审计备注</label><textarea id="note" v-model="annotation.note" rows="7" maxlength="10000" placeholder="记录权限用途、检查结论与跟进事项…"></textarea><button class="btn primary" :disabled="saving"><Icon name="check" :size="17" />{{ saving ? '保存中…' : '保存审计备注' }}</button></form></template>
      </div><footer class="drawer-footer"><Icon name="shield" :size="14" />权限数据只读采集 · 审计备注独立保存</footer></div>
    </dialog>
    <Transition name="toast"><div v-if="toast" class="toast-message" role="status"><Icon name="check" :size="18" />{{ toast }}<button aria-label="关闭提示" @click="toast = ''"><Icon name="close" :size="16" /></button></div></Transition>
  </div>
</template>
