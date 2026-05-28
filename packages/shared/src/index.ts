import { z } from 'zod'

// Device schemas
export const DevicePermissionsSchema = z.object({
  id: z.string(),
  deviceId: z.string(),
  camera: z.boolean().default(false),
  microphone: z.boolean().default(false),
  screenShare: z.boolean().default(false),
  remoteControlNativeAgent: z.boolean().default(false),
})

export const DeviceSchema = z.object({
  id: z.string(),
  displayName: z.string(),
  model: z.string().nullable(),
  osName: z.string().nullable(),
  osVersion: z.string().nullable(),
  browserName: z.string().nullable(),
  browserVersion: z.string().nullable(),
  userAgent: z.string().nullable(),
  screenWidth: z.number().nullable(),
  screenHeight: z.number().nullable(),
  language: z.string().nullable(),
  timezone: z.string().nullable(),
  localIp: z.string().nullable(),
  connectionType: z.string().nullable(),
  permissions: DevicePermissionsSchema.optional(),
  lastSeenAt: z.string().nullable(),
  status: z.enum(['online', 'offline', 'busy']),
  createdAt: z.string(),
  updatedAt: z.string(),
})

// Session schemas
export const DeviceSessionSchema = z.object({
  id: z.string(),
  pairingKey: z.string(),
  qrToken: z.string(),
  status: z.enum(['created', 'waiting_device', 'pending_approval', 'connected', 'screen_active', 'closed', 'expired']),
  createdAt: z.string(),
  expiresAt: z.string(),
  operatorId: z.string().nullable(),
  deviceId: z.string().nullable(),
  device: DeviceSchema.optional(),
})

// Network settings
export const NetworkSettingsSchema = z.object({
  id: z.string(),
  lanOnly: z.boolean().default(true),
  localServerUrl: z.string().nullable(),
  stunServers: z.string().nullable(),
  turnServerUrl: z.string().nullable(),
  turnUsername: z.string().nullable(),
  turnPassword: z.string().nullable(),
  diagnosticProxyUrl: z.string().nullable(),
  diagnosticProxyEnabled: z.boolean().default(false),
})

// API Response schemas
export const CreateSessionResponseSchema = z.object({
  sessionId: z.string(),
  pairingKey: z.string(),
  qrToken: z.string(),
  qrCode: z.string(),
  expiresAt: z.string(),
  joinUrl: z.string(),
})

// WebRTC signaling
export const WebRTCOfferSchema = z.object({
  sessionId: z.string(),
  offer: z.any(),
})

export const WebRTCAnswerSchema = z.object({
  sessionId: z.string(),
  to: z.string(),
  answer: z.any(),
})

export const WebRTCIceCandidateSchema = z.object({
  sessionId: z.string(),
  to: z.string(),
  candidate: z.any(),
})

// Socket.IO events
export const DeviceJoinByTokenSchema = z.object({
  qrToken: z.string(),
  deviceInfo: z.object({
    model: z.string().nullable(),
    osName: z.string().nullable(),
    osVersion: z.string().nullable(),
    browserName: z.string().nullable(),
    browserVersion: z.string().nullable(),
    userAgent: z.string(),
    screenWidth: z.number().nullable(),
    screenHeight: z.number().nullable(),
    language: z.string().nullable(),
    timezone: z.string().nullable(),
    localIp: z.string().nullable(),
    connectionType: z.string().nullable(),
  })
})

export const DeviceApproveSessionSchema = z.object({
  sessionId: z.string(),
  deviceInfo: z.record(z.any()),
})

// Type exports
export type Device = z.infer<typeof DeviceSchema>
export type DevicePermissions = z.infer<typeof DevicePermissionsSchema>
export type DeviceSession = z.infer<typeof DeviceSessionSchema>
export type NetworkSettings = z.infer<typeof NetworkSettingsSchema>
export type CreateSessionResponse = z.infer<typeof CreateSessionResponseSchema>
