import axios from 'axios'

export const api = axios.create({
  baseURL: import.meta.env.VITE_API_BASE || 'http://localhost:8000'
})

export function newsSocketUrl(symbol) {
  const base = import.meta.env.VITE_WS_BASE || 'ws://localhost:8000'
  return `${base}/ws/news/${symbol}`
}
