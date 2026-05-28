import { create } from 'zustand'

export interface DevicePermissions {
  id: string
  deviceId: string
  camera: boolean
  microphone: boolean
  screenShare: boolean
  remoteControlNativeAgent: boolean
}

export interface Device {
  id: string
  displayName: string
  model?: string
  osName?: string
  osVersion?: string
  browserName?: string
  browserVersion?: string
  userAgent?: string
  screenWidth?: number
  screenHeight?: number
  language?: string
  timezone?: string
  localIp?: string
  connectionType?: string
  permissions?: DevicePermissions
  lastSeenAt?: string
  status: 'online' | 'offline' | 'busy'
  createdAt: string
  updatedAt: string
}

interface DeviceStore {
  devices: Device[]
  selectedDevice: Device | null
  loading: boolean
  error: string | null
  fetchDevices: () => Promise<void>
  getDevice: (id: string) => Promise<Device | null>
  setSelectedDevice: (device: Device | null) => void
}

export const useDeviceStore = create<DeviceStore>((set, get) => ({
  devices: [],
  selectedDevice: null,
  loading: false,
  error: null,

  fetchDevices: async () => {
    set({ loading: true, error: null })
    try {
      const response = await fetch('/api/devices')
      if (!response.ok) throw new Error('Failed to fetch devices')
      const devices = await response.json()
      set({ devices })
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Unknown error'
      set({ error: message })
    } finally {
      set({ loading: false })
    }
  },

  getDevice: async (id: string) => {
    set({ loading: true })
    try {
      const response = await fetch(`/api/devices/${id}`)
      if (!response.ok) throw new Error('Failed to fetch device')
      const device = await response.json()
      set({ selectedDevice: device })
      return device
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Unknown error'
      set({ error: message })
      return null
    } finally {
      set({ loading: false })
    }
  },

  setSelectedDevice: (device) => {
    set({ selectedDevice: device })
  }
}))
