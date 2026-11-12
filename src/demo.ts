import type { Dashboard, Policy, AuditUser, RDSSecretsView } from './types'

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
    ip_ranges: id % 3 === 0 ? ['203.0.113.10/32', '198.51.100.24/32'] : [],
    secrets_access: id % 3 === 0 ? 'limited' : 'none',
    secrets_explanation: id % 3 === 0 ? '演示：可读取 Secret 的值，但受带条件的拒绝语句（来源 IP）约束。' : '演示：未发现授予 secretsmanager:GetSecretValue 的允许语句。',
    secrets_evidence: id % 3 === 0 ? ['拒绝（部分 Secret 或带条件，如来源 IP）: sp7969 / DenyOutsideAllowedIPs'] : [],
    rds_secret_access: id % 3 === 0 ? 'full' : 'rds_only',
    rds_secret_explanation: id % 3 === 0 ? '演示：可查询全部 RDS 的托管状态及对应 Secret 的轮换配置（不含 Secret 值）。' : '演示：可查看 RDS 是否托管，但缺少 secretsmanager:DescribeSecret，看不到轮换详情。',
    rds_secret_evidence: id % 3 === 0 ? ['rds:DescribeDBInstances · 允许（全部 RDS 实例）: SecurityAudit'] : [], warnings: [],
  }
}
export function demoDashboard(): Dashboard {
  const users = ['s7969', 'deployment-bot', 'security-auditor', 'developer-readonly', 'ops-admin', 'ci-runner'].map((name, id) => user(name, id, Math.floor(id / 2)))
  return {
    accounts: ['生产环境 · Production', '开发环境 · Development', '共享服务 · Shared'].map((name, i) => ({ id: ['123456789012', '234567890123', '345678901234'][i]!, name, alias: ['production', 'development', 'shared-services'][i]!, owner: ['基础设施团队', '研发团队', '安全团队'][i]!, status: 'success', last_synced_at: '2026-11-09T01:00:00Z', error: '', user_count: 2 })), users,
    sync: { running: false, started_at: '', last_finished_at: '2026-11-09T01:00:00Z', next_run_at: '2026-11-10T01:00:00Z', timezone: 'Asia/Shanghai', schedule: '09:00', last_result: 'success', logs: [{ id: 1, started_at: '2026-11-09T01:00:00Z', finished_at: '2026-11-09T01:00:12Z', trigger: 'scheduled', status: 'success', accounts_total: 3, accounts_succeeded: 3, error: '' }] },
  }
}
export function demoRDS(): RDSSecretsView {
  const base = { account_name: '生产环境 · Production', account_id: '123456789012', kms_key_id: '', rotation_schedule: '', rotation_window: '', warnings: [] as string[] }
  return {
    accounts: [{ account_id: '123456789012', account_name: '生产环境 · Production', status: 'success', error: '', synced_at: '2026-11-09T01:00:00Z', regions: ['ap-southeast-1'], count: 3 }],
    items: [
      { ...base, region: 'ap-southeast-1', kind: 'cluster', identifier: 'prod-aurora', engine: 'aurora-mysql', engine_version: '8.0', master_username: 'admin', migrated: 'yes', secret_arn: 'arn:aws:secretsmanager:ap-southeast-1:123456789012:secret:rds!cluster-demo', secret_status: 'active', verdict: 'pass', verdict_text: '已迁移，核验通过：Secret 状态 active，由 RDS 托管，自动轮换已开启。', rotation_enabled: 'enabled', rotation_period: '每 7 天', last_rotated_at: '2026-11-08T02:00:00Z', next_rotation_at: '2026-11-15T05:00:00Z', next_rotation_source: 'aws' },
      { ...base, region: 'ap-southeast-1', kind: 'instance', identifier: 'report-pg', engine: 'postgres', engine_version: '16.4', master_username: 'postgres', migrated: 'yes', secret_arn: 'arn:aws:secretsmanager:ap-southeast-1:123456789012:secret:rds!db-demo', secret_status: 'active', verdict: 'warn', verdict_text: '已迁移，需关注：自动轮换未开启。', rotation_enabled: 'disabled', rotation_period: '每 7 天', last_rotated_at: '2026-09-01T02:00:00Z', next_rotation_at: '', next_rotation_source: '' },
      { ...base, region: 'ap-southeast-1', kind: 'instance', identifier: 'legacy-mysql', engine: 'mysql', engine_version: '5.7', master_username: 'root', migrated: 'no', secret_arn: '', secret_status: '', verdict: 'not_migrated', verdict_text: '未迁移：主用户密码未由 Secrets Manager 托管（未启用 ManageMasterUserPassword），仍为 RDS 本地密码。', rotation_enabled: '', rotation_period: '', last_rotated_at: '', next_rotation_at: '', next_rotation_source: '' },
    ],
  }
}
