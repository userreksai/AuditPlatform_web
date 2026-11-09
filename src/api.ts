const base = (import.meta.env.VITE_API_BASE_URL || '').replace(/\/$/, '')

export class ApiError extends Error {
  constructor(message: string, public status: number) { super(message) }
}

export async function request<T>(path: string, options: RequestInit = {}): Promise<T> {
  const response = await fetch(`${base}${path}`, {
    ...options, credentials: 'include',
    headers: { 'Content-Type': 'application/json', ...options.headers },
  })
  const body = await response.json().catch(() => ({}))
  if (!response.ok) throw new ApiError(body.error || `请求失败（${response.status}）`, response.status)
  return body as T
}

export function csvCell(value: unknown): string {
  let text = String(value ?? '')
  // Spreadsheet programs can execute formulas even in quoted CSV cells.
  if (/^[\s\uFEFF]*[=+\-@\t\r\n]/.test(text)) text = `'${text}`
  return `"${text.replace(/"/g, '""')}"`
}
