import type { Dashboard, Policy, AuditUser } from './types'

const security: Policy = {
  id: 'security-audit', name: 'SecurityAudit', arn: 'arn:aws:iam::aws:policy/SecurityAudit',
  type: 'aws_managed', source: 'direct', group_name: '',
  document: { Version: '2012-10-17', Statement: [{ Effect: 'Allow', Action: ['iam:Get*', 'iam:List*'], Resource: '*' }] },
  ip_conditions: [], warnings: ['演示策略仅包含节选，用于展示界面。'],
}
const restricted: Policy = {
  id: 'sp7969', name: 'sp7969', arn: 'arn:aws:iam::123456789012:policy/sp7969', type: 'customer_managed', source: 'direct', group_name: '',
  document: { Version: '2012-10-17', Statement: [{ Sid: 'DenyOutsideAllowedIPs', Effect: 'Deny', Action: '*', Resource: '*', Condition: { NotIpAddress: { 'aws:SourceIp': ['203.0.113.10/32', '198.51.100.24/32'] } } }] },
  ip_conditions: [{ sid: 'DenyOutsideAllowedIPs', effect: 'Deny', operator: 'NotIpAddress', key: 'aws:SourceIp', values: ['203.0.113.10/32', '198.51.100.24/32'], interpretation: '来源 IP 不在列出的范围内时拒绝。仍需结合该语句其他条件与请求上下文。' }], warnings: [],
}
function user(name: string, id: number, account: number): AuditUser {
  const account_id = ['123456789012', '234567890123', '345678901234'][account]!
  const names = ['生产环境 · Production', '开发环境 · Development', '共享服务 · Shared']
  return {
    account_id, account_name: names[account]!, user_id: `AIDAEXAMPLE${id.toString().padStart(10, '0')}`, username: name,
    arn: `arn:aws:iam::${account_id}:user/${name}`, path: '/', owner: ['运维团队', '安全团队', '研发团队'][id % 3]!,
    review_status: id % 4 === 0 ? 'attention' : id % 2 === 0 ? 'reviewed' : 'pending', note: '',
    console_access: id % 3 === 0 ? 'disabled' : 'enabled', mfa_enabled: id % 3 === 0 ? 'disabled' : 'enabled',
    created_at: '2025-10-31T03:36:00Z', password_last_used: id % 3 === 0 ? '' : '2026-11-08T06:41:00Z',
    groups: id % 2 === 0 ? ['SecurityTeam'] : [],
    access_keys: id % 3 === 1 ? [] : [{ id: `AKIAEXAMPLE${id.toString().padStart(9, '0')}`, status: id % 3 === 0 ? 'Active' : 'Inactive', created_at: '2026-08-21T04:20:00Z', last_used_at: '2026-11-08T10:20:00Z', last_used_service: 's3', last_used_region: 'ap-southeast-1' }],
    policies: id % 3 === 0 ? [security, restricted] : id % 2 === 0 ? [{ ...security, source: 'group', group_name: 'SecurityTeam' }] : [security],
    ip_status: id % 3 === 0 ? 'restricted' : id % 2 === 0 ? 'conditional' : 'unrestricted',
    ip_explanation: id % 3 === 0 ? '在 sp7969 中发现 Deny + NotIpAddress 条件；需要结合完整条件判断。' : '未发现明确覆盖全部请求的 IP 拒绝条件；不代表实际可从任意地址访问。',
    ip_ranges: id % 3 === 0 ? ['203.0.113.10/32', '198.51.100.24/32'] : [], warnings: [],
  }
}
export function demoDashboard(): Dashboard {
  const users = ['s7969', 'deployment-bot', 'security-auditor', 'developer-readonly', 'ops-admin', 'ci-runner'].map((name, id) => user(name, id, Math.floor(id / 2)))
  return {
    accounts: ['生产环境 · Production', '开发环境 · Development', '共享服务 · Shared'].map((name, i) => ({ id: ['123456789012', '234567890123', '345678901234'][i]!, name, alias: ['production', 'development', 'shared-services'][i]!, owner: ['基础设施团队', '研发团队', '安全团队'][i]!, status: 'success', last_synced_at: '2026-11-09T01:00:00Z', error: '', user_count: 2 })), users,
    sync: { running: false, started_at: '', last_finished_at: '2026-11-09T01:00:00Z', next_run_at: '2026-11-10T01:00:00Z', timezone: 'Asia/Shanghai', schedule: '09:00', last_result: 'success', logs: [{ id: 1, started_at: '2026-11-09T01:00:00Z', finished_at: '2026-11-09T01:00:12Z', trigger: 'scheduled', status: 'success', accounts_total: 3, accounts_succeeded: 3, error: '' }] },
  }
}
