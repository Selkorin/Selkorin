import express, { Express, Request, Response } from 'express';
import { createServer } from 'http';
import { Server as SocketIOServer, Socket } from 'socket.io';
import helmet from 'helmet';
import cors from 'cors';
import rateLimit from 'express-rate-limit';
import { PrismaClient } from '@prisma/client';
import { config } from 'dotenv';
import pino from 'pino';
import QRCode from 'qrcode';
import { nanoid } from 'nanoid';

config();

const app: Express = express();
const server = createServer(app);
const io = new SocketIOServer(server, {
  cors: {
    origin: process.env.CORS_ORIGIN || 'http://localhost:5173',
    methods: ['GET', 'POST']
  }
});

const prisma = new PrismaClient();
const logger = pino();

const PORT = parseInt(process.env.PORT || '3000', 10);
const NODE_ENV = process.env.NODE_ENV || 'development';

// Middleware
app.use(helmet());
app.use(cors({
  origin: process.env.CORS_ORIGIN || 'http://localhost:5173'
}));
app.use(express.json());

const limiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 100
});
app.use(limiter);

// Routes

// Health check
app.get('/health', (req: Request, res: Response) => {
  res.json({ status: 'ok', timestamp: new Date().toISOString() });
});

// Create pairing session
app.post('/api/sessions', async (req: Request, res: Response) => {
  try {
    const pairingKey = nanoid(32);
    const qrToken = nanoid(16);
    const expiresAt = new Date(Date.now() + 5 * 60 * 1000); // 5 minutes

    const session = await prisma.deviceSession.create({
      data: {
        pairingKey,
        qrToken,
        status: 'created',
        expiresAt,
        operatorId: 'operator-1' // TODO: Get from auth
      }
    });

    const qrUrl = `${process.env.APP_URL || 'http://localhost:5173'}/join/${qrToken}`;
    const qrCode = await QRCode.toDataURL(qrUrl);

    logger.info({ sessionId: session.id }, 'Session created');

    res.json({
      sessionId: session.id,
      pairingKey: session.pairingKey,
      qrToken: session.qrToken,
      qrCode,
      expiresAt: session.expiresAt,
      joinUrl: qrUrl
    });
  } catch (error) {
    logger.error(error, 'Failed to create session');
    res.status(500).json({ error: 'Failed to create session' });
  }
});

// Get session
app.get('/api/sessions/:id', async (req: Request, res: Response) => {
  try {
    const session = await prisma.deviceSession.findUnique({
      where: { id: req.params.id },
      include: { device: true }
    });

    if (!session) {
      return res.status(404).json({ error: 'Session not found' });
    }

    res.json(session);
  } catch (error) {
    logger.error(error, 'Failed to get session');
    res.status(500).json({ error: 'Failed to get session' });
  }
});

// Get devices
app.get('/api/devices', async (req: Request, res: Response) => {
  try {
    const devices = await prisma.device.findMany({
      include: { permissions: true },
      orderBy: { lastSeenAt: 'desc' }
    });

    res.json(devices);
  } catch (error) {
    logger.error(error, 'Failed to get devices');
    res.status(500).json({ error: 'Failed to get devices' });
  }
});

// Get device
app.get('/api/devices/:id', async (req: Request, res: Response) => {
  try {
    const device = await prisma.device.findUnique({
      where: { id: req.params.id },
      include: { permissions: true }
    });

    if (!device) {
      return res.status(404).json({ error: 'Device not found' });
    }

    res.json(device);
  } catch (error) {
    logger.error(error, 'Failed to get device');
    res.status(500).json({ error: 'Failed to get device' });
  }
});

// Get audit logs
app.get('/api/audit', async (req: Request, res: Response) => {
  try {
    const logs = await prisma.auditLog.findMany({
      orderBy: { createdAt: 'desc' },
      take: 100
    });

    res.json(logs);
  } catch (error) {
    logger.error(error, 'Failed to get audit logs');
    res.status(500).json({ error: 'Failed to get audit logs' });
  }
});

// Socket.IO

io.on('connection', (socket: Socket) => {
  logger.info({ socketId: socket.id }, 'Client connected');

  // Device joins by token
  socket.on('device:join-by-token', async (data: { qrToken: string; deviceInfo: any }, callback) => {
    try {
      const session = await prisma.deviceSession.findUnique({
        where: { qrToken: data.qrToken }
      });

      if (!session || new Date() > session.expiresAt) {
        logger.warn({ qrToken: data.qrToken }, 'Invalid or expired QR token');
        return callback({ error: 'Invalid or expired token' });
      }

      socket.data.sessionId = session.id;
      socket.data.deviceInfo = data.deviceInfo;

      await prisma.deviceSession.update({
        where: { id: session.id },
        data: { status: 'waiting_device' }
      });

      io.to(`session:${session.id}`).emit('session:waiting-device', {
        sessionId: session.id,
        deviceInfo: data.deviceInfo
      });

      logger.info({ sessionId: session.id }, 'Device joined by token');
      callback({ success: true, sessionId: session.id });
    } catch (error) {
      logger.error(error, 'Device join failed');
      callback({ error: 'Failed to join' });
    }
  });

  // Device approves session
  socket.on('device:approve-session', async (data: { sessionId: string; deviceInfo: any }, callback) => {
    try {
      let device = await prisma.device.findFirst({
        where: { userAgent: data.deviceInfo.userAgent }
      });

      if (!device) {
        device = await prisma.device.create({
          data: {
            displayName: data.deviceInfo.model || 'Unknown Device',
            model: data.deviceInfo.model,
            osName: data.deviceInfo.osName,
            osVersion: data.deviceInfo.osVersion,
            browserName: data.deviceInfo.browserName,
            browserVersion: data.deviceInfo.browserVersion,
            userAgent: data.deviceInfo.userAgent,
            screenWidth: data.deviceInfo.screenWidth,
            screenHeight: data.deviceInfo.screenHeight,
            language: data.deviceInfo.language,
            timezone: data.deviceInfo.timezone,
            localIp: data.deviceInfo.localIp,
            connectionType: data.deviceInfo.connectionType,
            status: 'online',
            lastSeenAt: new Date(),
            permissions: {
              create: {}
            }
          },
          include: { permissions: true }
        });
      } else {
        device = await prisma.device.update({
          where: { id: device.id },
          data: {
            status: 'online',
            lastSeenAt: new Date()
          },
          include: { permissions: true }
        });
      }

      await prisma.deviceSession.update({
        where: { id: data.sessionId },
        data: {
          status: 'connected',
          deviceId: device.id
        }
      });

      socket.data.deviceId = device.id;
      socket.join(`session:${data.sessionId}`);
      socket.join(`device:${device.id}`);

      io.to(`session:${data.sessionId}`).emit('session:connected', {
        sessionId: data.sessionId,
        device
      });

      await logAuditEvent('device_approved', 'Device approved session', {
        sessionId: data.sessionId,
        deviceId: device.id
      });

      logger.info({ sessionId: data.sessionId, deviceId: device.id }, 'Device approved session');
      callback({ success: true, deviceId: device.id });
    } catch (error) {
      logger.error(error, 'Device approval failed');
      callback({ error: 'Failed to approve' });
    }
  });

  // Request screen
  socket.on('operator:request-screen', async (data: { sessionId: string }, callback) => {
    try {
      io.to(`session:${data.sessionId}`).emit('session:screen-requested', {
        sessionId: data.sessionId
      });

      logger.info({ sessionId: data.sessionId }, 'Screen requested');
      callback({ success: true });
    } catch (error) {
      logger.error(error, 'Screen request failed');
      callback({ error: 'Failed to request screen' });
    }
  });

  // Device approves screen
  socket.on('device:approve-screen', async (data: { sessionId: string }, callback) => {
    try {
      const session = await prisma.deviceSession.update({
        where: { id: data.sessionId },
        data: { status: 'screen_active' }
      });

      socket.join(`screen:${data.sessionId}`);
      io.to(`session:${data.sessionId}`).emit('session:screen-active', {
        sessionId: data.sessionId
      });

      await logAuditEvent('screen_approved', 'Device approved screen sharing', {
        sessionId: data.sessionId
      });

      logger.info({ sessionId: data.sessionId }, 'Screen approved');
      callback({ success: true });
    } catch (error) {
      logger.error(error, 'Screen approval failed');
      callback({ error: 'Failed to approve screen' });
    }
  });

  // WebRTC signaling
  socket.on('webrtc:offer', (data: { sessionId: string; offer: any }, callback) => {
    io.to(`screen:${data.sessionId}`).emit('webrtc:offer', {
      from: socket.id,
      offer: data.offer
    });
    callback({ success: true });
  });

  socket.on('webrtc:answer', (data: { sessionId: string; to: string; answer: any }, callback) => {
    io.to(data.to).emit('webrtc:answer', {
      from: socket.id,
      answer: data.answer
    });
    callback({ success: true });
  });

  socket.on('webrtc:ice-candidate', (data: { sessionId: string; to: string; candidate: any }, callback) => {
    io.to(data.to).emit('webrtc:ice-candidate', {
      from: socket.id,
      candidate: data.candidate
    });
    callback({ success: true });
  });

  // Disconnect
  socket.on('disconnect', async () => {
    if (socket.data.deviceId) {
      await prisma.device.update({
        where: { id: socket.data.deviceId },
        data: { status: 'offline' }
      });
    }

    logger.info({ socketId: socket.id }, 'Client disconnected');
  });
});

// Utility functions
async function logAuditEvent(
  action: string,
  description: string,
  metadata: any = {}
) {
  try {
    await prisma.auditLog.create({
      data: {
        action,
        description,
        metadata: JSON.stringify(metadata)
      }
    });
  } catch (error) {
    logger.error(error, 'Failed to log audit event');
  }
}

// Start server
server.listen(PORT, () => {
  logger.info({ port: PORT, env: NODE_ENV }, 'Server running');
});

// Graceful shutdown
process.on('SIGTERM', async () => {
  await prisma.$disconnect();
  process.exit(0);
});
