const base = import.meta.env.VITE_ADMIN_API_BASE ?? ''

export function setToken(value: string | null) {
  if (value) sessionStorage.setItem('honghuang_admin_token', value)
  else sessionStorage.removeItem('honghuang_admin_token')
}

export function getToken() {
  return sessionStorage.getItem('honghuang_admin_token') ?? ''
}

export async function api<T>(path: string, init: RequestInit = {}): Promise<T> {
  const headers = new Headers(init.headers)
  headers.set('Accept', 'application/json')
  if (init.body) headers.set('Content-Type', 'application/json')
  const token = getToken()
  if (token) headers.set('Authorization', `Bearer ${token}`)
  const response = await fetch(`${base}${path}`, { ...init, headers })
  if (!response.ok) {
    const message = (await response.text()).trim()
    throw new Error(message || `HTTP ${response.status}`)
  }
  if (response.status === 204) return undefined as T
  return await response.json() as T
}
