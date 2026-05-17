import axios from 'axios'

const apiBase = import.meta.env.VITE_API_BASE || 'http://localhost:8000'

export const api = axios.create({ baseURL: apiBase })

export function newsSocketUrl(symbol) {
  const wsBase = apiBase.replace(/^http/, 'ws')
  return `${wsBase}/ws/news/${symbol}`
}
