import axios from 'axios'
import { localApi } from './local/client'

// VITE_BACKENDLESS=1 answers every call on the device (Yahoo/Nasdaq/Google via /api/proxy);
// otherwise the app talks to the FastAPI backend exactly as before.
export const backendless = import.meta.env.VITE_BACKENDLESS === '1'

const apiBase = import.meta.env.VITE_API_BASE || 'http://localhost:8000'

export const api = backendless ? localApi : axios.create({ baseURL: apiBase })

export function newsSocketUrl(symbol) {
  const wsBase = apiBase.replace(/^http/, 'ws')
  return `${wsBase}/ws/news/${symbol}`
}
