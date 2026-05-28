import { create } from 'zustand'

export interface Session {
  id: string
  pairingKey: string
  qrToken: string
  qrCode: string
  status: 'created' | 'waiting_device' | 'pending_approval' | 'connected' | 'screen_active' | 'closed' | 'expired'
  expiresAt: string
  joinUrl: string
  deviceId?: string
  createdAt: string
}

interface SessionStore {
  currentSession: Session | null
  sessions: Session[]
  loading: boolean
  error: string | null
  createSession: () => Promise<Session | null>
  setCurrentSession: (session: Session | null) => void
  fetchSessions: () => Promise<void>
}

export const useSessionStore = create<SessionStore>((set, get) => ({
  currentSession: null,
  sessions: [],
  loading: false,
  error: null,

  createSession: async () => {
    set({ loading: true, error: null })
    try {
      const response = await fetch('/api/sessions', {
        method: 'POST'
      })

      if (!response.ok) throw new Error('Failed to create session')

      const session = await response.json()
      set({ currentSession: session })
      return session
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Unknown error'
      set({ error: message })
      return null
    } finally {
      set({ loading: false })
    }
  },

  setCurrentSession: (session) => {
    set({ currentSession: session })
  },

  fetchSessions: async () => {
    set({ loading: true })
    try {
      const response = await fetch('/api/sessions')
      if (!response.ok) throw new Error('Failed to fetch sessions')
      // TODO: Implement sessions list
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Unknown error'
      set({ error: message })
    } finally {
      set({ loading: false })
    }
  }
}))
