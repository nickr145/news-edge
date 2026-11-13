import { localApi } from './local/client'

// Every call is answered in the browser (Yahoo/Nasdaq/Google via /api/proxy); there is no backend.
export const api = localApi
