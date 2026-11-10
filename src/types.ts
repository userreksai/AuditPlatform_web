export interface IPCondition {
  sid: string; effect: string; operator: string; key: string; values: string[]; interpretation: string
}
export interface Policy {
  id: string; name: string; arn: string; type: string; source: string; group_name: string
  document: unknown; ip_conditions: IPCondition[]; warnings: string[]
}
export interface AccessKey {
  id: string; status: string; created_at: string; last_used_at: string; last_used_service: string; last_used_region: string
}
export interface AuditUser {
  account_id: string; account_name: string; user_id: string; username: string; arn: string; path: string
  owner: string; review_status: string; note: string; console_access: string; mfa_enabled: string
  created_at: string; password_last_used: string; groups: string[]; access_keys: AccessKey[]
  policies: Policy[]; permissions_boundary?: Policy; ip_status: string; ip_explanation: string
  ip_ranges: string[]; secrets_access?: string; secrets_explanation?: string; secrets_evidence?: string[]
  warnings: string[]
}
export interface Account {
  id: string; name: string; alias: string; owner: string; status: string; last_synced_at: string
  error: string; user_count: number
}
export interface SyncLog {
  id: number; started_at: string; finished_at: string; trigger: string; status: string
  accounts_total: number; accounts_succeeded: number; error: string
}
export interface SyncStatus {
  running: boolean; started_at: string; last_finished_at: string; next_run_at: string
  timezone: string; schedule: string; last_result: string; logs: SyncLog[]
}
export interface Dashboard { accounts: Account[]; users: AuditUser[]; sync: SyncStatus }
