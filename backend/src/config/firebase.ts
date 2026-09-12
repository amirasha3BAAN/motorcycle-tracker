import * as fs from 'fs';
import * as path from 'path';
import { WebSocketServer, WebSocket } from 'ws';

// Persistent local JSON file path
const DB_FILE_PATH = path.resolve(process.env.LOCAL_DB_PATH || './database_store.json');

// Global in-memory database store initialized from the JSON file
let localDatabaseStore: Record<string, any> = {};

// Load existing database store if it exists
try {
  if (fs.existsSync(DB_FILE_PATH)) {
    const data = fs.readFileSync(DB_FILE_PATH, 'utf8');
    localDatabaseStore = JSON.parse(data);
    console.log(`[Local DB] Successfully loaded persistent database from ${DB_FILE_PATH}`);
  } else {
    localDatabaseStore = {};
    fs.writeFileSync(DB_FILE_PATH, JSON.stringify(localDatabaseStore, null, 2), 'utf8');
    console.log(`[Local DB] Initialized new persistent database file at ${DB_FILE_PATH}`);
  }
} catch (error) {
  console.error('[Local DB Error] Failed to load/create persistent database file:', error);
  localDatabaseStore = {};
}

// Save database state helper
function saveDatabase() {
  try {
    fs.writeFileSync(DB_FILE_PATH, JSON.stringify(localDatabaseStore, null, 2), 'utf8');
  } catch (error) {
    console.error('[Local DB Error] Failed to persist database state:', error);
  }
}

// Path navigation helpers
function getValueByPath(obj: any, pathStr: string): any {
  const parts = pathStr.split('/').filter(p => p !== '');
  let current = obj;
  for (const part of parts) {
    if (current && typeof current === 'object' && part in current) {
      current = current[part];
    } else {
      return undefined;
    }
  }
  return current;
}

function setValueByPath(obj: any, pathStr: string, value: any): void {
  const parts = pathStr.split('/').filter(p => p !== '');
  let current = obj;
  for (let i = 0; i < parts.length; i++) {
    const part = parts[i];
    if (i === parts.length - 1) {
      current[part] = value;
    } else {
      if (!current[part] || typeof current[part] !== 'object') {
        current[part] = {};
      }
      current = current[part];
    }
  }
}

function updateValueByPath(obj: any, pathStr: string, value: any): void {
  const parts = pathStr.split('/').filter(p => p !== '');
  let current = obj;
  for (let i = 0; i < parts.length; i++) {
    const part = parts[i];
    if (i === parts.length - 1) {
      current[part] = { ...(current[part] || {}), ...value };
    } else {
      if (!current[part] || typeof current[part] !== 'object') {
        current[part] = {};
      }
      current = current[part];
    }
  }
}

// WebSocket setup
let wss: WebSocketServer | null = null;
const connectedClients = new Set<WebSocket>();

export function initializeWebSockets(server: any) {
  wss = new WebSocketServer({ server });
  console.log('[WebSocket Server] Initialized and listening on Express HTTP port.');

  wss.on('connection', (ws) => {
    connectedClients.add(ws);
    console.log(`[WebSocket] Client connected. Active clients: ${connectedClients.size}`);

    // If client sends a subscription or ping
    ws.on('message', (message) => {
      try {
        const parsed = JSON.parse(message.toString());
        if (parsed.type === 'ping') {
          ws.send(JSON.stringify({ type: 'pong' }));
        }
      } catch (err) {
        // Silently ignore malformed messages
      }
    });

    ws.on('close', () => {
      connectedClients.delete(ws);
      console.log(`[WebSocket] Client disconnected. Active clients: ${connectedClients.size}`);
    });

    ws.on('error', (err) => {
      console.error('[WebSocket Client Error]', err);
    });
  });
}

// Broadcast updates to all connected clients
export function broadcast(pathStr: string, data: any) {
  const messageStr = JSON.stringify({ path: pathStr, data });
  for (const client of connectedClients) {
    if (client.readyState === WebSocket.OPEN) {
      client.send(messageStr);
    }
  }
}

// Mock database interface to mirror Firebase Admin database calls
export const getDatabase = () => {
  return {
    ref: (nodePath: string) => {
      return {
        set: async (value: any) => {
          setValueByPath(localDatabaseStore, nodePath, value);
          saveDatabase();
          broadcast(nodePath, value);
          return Promise.resolve();
        },
        update: async (value: any) => {
          updateValueByPath(localDatabaseStore, nodePath, value);
          saveDatabase();
          // After update, retrieve the full merged node and broadcast it
          const fullNode = getValueByPath(localDatabaseStore, nodePath);
          broadcast(nodePath, fullNode);
          return Promise.resolve();
        },
        push: () => {
          const newKey = `history_key_${Date.now()}_${Math.random().toString(36).substring(2, 7)}`;
          const fullPath = `${nodePath}/${newKey}`;
          return {
            key: newKey,
            set: async (value: any) => {
              setValueByPath(localDatabaseStore, fullPath, value);
              saveDatabase();
              broadcast(fullPath, value);
              return Promise.resolve();
            }
          };
        },
        once: async (event: string) => {
          const val = getValueByPath(localDatabaseStore, nodePath);
          return {
            val: () => val,
            exists: () => val !== undefined && val !== null
          };
        }
      };
    }
  } as any;
};

// Mock messaging interface to mirror FCM calls, broadcasting notifications over WS
export const sendPushNotification = async (payload: { title: string; body: string; topic: string }) => {
  console.log(`[Local DB Notification] Dispatching alert over WebSockets: "${payload.title}" - "${payload.body}"`);
  broadcast('alerts/notifications', payload);
  return 'local_msg_id_' + Date.now();
};

export const isFirebaseMock = () => false;
