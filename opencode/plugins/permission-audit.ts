import type { Plugin } from "@opencode-ai/plugin"
import { appendFile, mkdir } from "node:fs/promises"
import os from "node:os"
import path from "node:path"

type AuditKind = "tool.before" | "tool.after" | "permission.asked" | "permission.replied"

type AuditEntry = {
  ts: string
  kind: AuditKind
  sessionID: string | null
  callID: string | null
  requestID: string | null
  id: string | null
  tool: string | null
  agent: string | null
  argsSummary: string | null
  patterns: string[] | null
  permission: string | null
  reply: string | null
  status: string | null
  error: boolean | null
  deny: boolean | null
}

type RequestContext = {
  callID: string | null
  tool: string | null
  argsSummary: string | null
  permission: string | null
  patterns: string[] | null
}

const LOG_FILE = path.join(os.homedir(), ".local", "share", "opencode", "permission-audit.jsonl")
const LOG_DIR = path.dirname(LOG_FILE)
const MAX_SUMMARY = 500
const MAX_TRACKED = 5000
const SINGLETON_REGISTRY_KEY = "__opencode_permission_audit_plugin_instances__"

let ensureDirectoryPromise: Promise<void> | null = null

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null
}

function asString(value: unknown): string | null {
  if (typeof value !== "string") {
    return null
  }
  const trimmed = value.trim()
  return trimmed.length > 0 ? trimmed : null
}

function truncate(text: string, max = MAX_SUMMARY): string {
  if (text.length <= max) {
    return text
  }
  return `${text.slice(0, max - 3)}...`
}

function safeStringify(value: unknown): string {
  const seen = new WeakSet<object>()
  return JSON.stringify(value, (_key, currentValue) => {
    if (typeof currentValue === "bigint") {
      return currentValue.toString()
    }
    if (currentValue instanceof Error) {
      return {
        name: currentValue.name,
        message: currentValue.message,
        stack: currentValue.stack,
      }
    }
    if (typeof currentValue === "object" && currentValue !== null) {
      if (seen.has(currentValue)) {
        return "[Circular]"
      }
      seen.add(currentValue)
    }
    return currentValue
  })
}

function normalizePatterns(value: unknown): string[] | null {
  if (Array.isArray(value)) {
    const patterns = value
      .map((item) => asString(item))
      .filter((item): item is string => item !== null)
    return patterns.length > 0 ? patterns : null
  }

  const single = asString(value)
  if (single) {
    return [single]
  }

  return null
}

function summarizeArgs(tool: string | null, args: unknown): string | null {
  if (args === undefined) {
    return null
  }

  if (tool === "bash") {
    if (typeof args === "string") {
      return truncate(args)
    }
    if (isRecord(args)) {
      const command = asString(args.command)
      if (command) {
        return truncate(command)
      }
    }
  }

  try {
    return truncate(safeStringify(args))
  } catch {
    try {
      return truncate(String(args))
    } catch {
      return null
    }
  }
}

function inferToolAfterError(output: unknown): boolean | null {
  if (!isRecord(output)) {
    return null
  }

  const metadata = isRecord(output.metadata) ? output.metadata : null
  if (!metadata) {
    return null
  }

  const status = asString(metadata.status)
  if (status && /^(error|failed|failure)$/i.test(status)) {
    return true
  }

  const exit = metadata.exit
  if (typeof exit === "number") {
    return exit !== 0
  }

  const exitCode = metadata.exitCode
  if (typeof exitCode === "number") {
    return exitCode !== 0
  }

  if (metadata.error !== undefined && metadata.error !== null) {
    return true
  }

  return null
}

function callKey(sessionID: string, callID: string): string {
  return `${sessionID}:${callID}`
}

function requestKey(sessionID: string, requestID: string): string {
  return `${sessionID}:${requestID}`
}

function mapSetWithCap<K, V>(map: Map<K, V>, key: K, value: V): void {
  if (map.has(key)) {
    map.delete(key)
  }
  map.set(key, value)

  while (map.size > MAX_TRACKED) {
    const oldestKey = map.keys().next().value as K | undefined
    if (oldestKey === undefined) {
      break
    }
    map.delete(oldestKey)
  }
}

function setAddWithCap<T>(set: Set<T>, value: T): void {
  if (set.has(value)) {
    set.delete(value)
  }
  set.add(value)

  while (set.size > MAX_TRACKED) {
    const oldest = set.values().next().value as T | undefined
    if (oldest === undefined) {
      break
    }
    set.delete(oldest)
  }
}

function readResultData(result: unknown): unknown {
  if (!isRecord(result)) {
    return undefined
  }
  return result.data
}

function extractAgentFromMessageInfo(info: unknown): string | null {
  if (!isRecord(info)) {
    return null
  }
  return asString(info.agent)
}

function extractAgentFromMessageEnvelope(envelope: unknown): string | null {
  if (!isRecord(envelope)) {
    return null
  }

  const infoAgent = extractAgentFromMessageInfo(envelope.info)
  if (infoAgent) {
    return infoAgent
  }

  const parts = envelope.parts
  if (!Array.isArray(parts)) {
    return null
  }

  for (let index = parts.length - 1; index >= 0; index -= 1) {
    const part = parts[index]
    if (!isRecord(part)) {
      continue
    }

    const type = asString(part.type)
    if (type === "agent") {
      const name = asString(part.name)
      if (name) {
        return name
      }
    }

    if (type === "subtask") {
      const agent = asString(part.agent)
      if (agent) {
        return agent
      }
    }
  }

  return null
}

function extractAgentCandidate(...sources: unknown[]): string | null {
  for (const source of sources) {
    if (!isRecord(source)) {
      continue
    }

    const direct = asString(source.agent)
    if (direct) {
      return direct
    }

    const info = isRecord(source.info) ? source.info : null
    const infoAgent = info ? asString(info.agent) : null
    if (infoAgent) {
      return infoAgent
    }

    const metadata = isRecord(source.metadata) ? source.metadata : null
    const metadataAgent = metadata ? asString(metadata.agent) : null
    if (metadataAgent) {
      return metadataAgent
    }
  }

  return null
}

function extractToolFromMetadata(metadata: unknown): string | null {
  if (!isRecord(metadata)) {
    return null
  }

  return asString(metadata.tool) ?? asString(metadata.name)
}

function summarizePermissionMetadataArgs(metadata: unknown): string | null {
  if (!isRecord(metadata)) {
    return null
  }

  const command = asString(metadata.command)
  if (command) {
    return truncate(command)
  }

  if (isRecord(metadata.args)) {
    const tool = asString(metadata.tool)
    return summarizeArgs(tool, metadata.args)
  }

  return summarizeArgs(null, metadata)
}

async function ensureLogDirectory(): Promise<void> {
  if (!ensureDirectoryPromise) {
    ensureDirectoryPromise = mkdir(LOG_DIR, { recursive: true }).then(() => undefined)
  }

  try {
    await ensureDirectoryPromise
  } catch (error) {
    ensureDirectoryPromise = null
    throw error
  }
}

async function appendAudit(entry: AuditEntry): Promise<void> {
  await ensureLogDirectory()
  await appendFile(LOG_FILE, `${safeStringify(entry)}\n`, "utf8")
}

export default (async ({ client, directory, worktree }) => {
  const pluginGlobal = globalThis as Record<string, unknown>
  let registry = pluginGlobal[SINGLETON_REGISTRY_KEY]
  if (!(registry instanceof Set)) {
    registry = new Set<string>()
    pluginGlobal[SINGLETON_REGISTRY_KEY] = registry
  }
  const instanceRegistry = registry as Set<string>

  const instanceKey = `${directory}::${worktree}`
  if (instanceRegistry.has(instanceKey)) {
    return {}
  }
  instanceRegistry.add(instanceKey)

  const sessionAgentCache = new Map<string, string>()
  const agentLookupInFlight = new Set<string>()
  const callToolByKey = new Map<string, string>()
  const callArgsByKey = new Map<string, string | null>()
  const requestContextByKey = new Map<string, RequestContext>()
  const askedLoggedByKey = new Set<string>()

  const cacheSessionAgent = (sessionID: string | null, agent: string | null): void => {
    if (!sessionID || !agent) {
      return
    }
    mapSetWithCap(sessionAgentCache, sessionID, agent)
  }

  const getSessionAgent = (sessionID: string | null): string | null => {
    if (!sessionID) {
      return null
    }
    return sessionAgentCache.get(sessionID) ?? null
  }

  const warmAgentCache = (sessionID: string | null, messageID?: string): void => {
    if (!sessionID) {
      return
    }
    if (sessionAgentCache.has(sessionID) || agentLookupInFlight.has(sessionID)) {
      return
    }

    setAddWithCap(agentLookupInFlight, sessionID)

    void (async () => {
      try {
        try {
          const sessionResult = await client.session.get({
            path: {
              id: sessionID,
            },
          })
          const sessionData = readResultData(sessionResult)
          cacheSessionAgent(sessionID, extractAgentCandidate(sessionData))
        } catch {
          // best effort only
        }

        if (!sessionAgentCache.has(sessionID) && messageID) {
          try {
            const messageResult = await client.session.message({
              path: {
                id: sessionID,
                messageID,
              },
            })
            const messageAgent = extractAgentFromMessageEnvelope(readResultData(messageResult))
            cacheSessionAgent(sessionID, messageAgent)
          } catch {
            // best effort only
          }
        }

        if (!sessionAgentCache.has(sessionID)) {
          try {
            const messagesResult = await client.session.messages({
              path: {
                id: sessionID,
              },
              query: {
                limit: 30,
              },
            })

            const messagesData = readResultData(messagesResult)
            if (Array.isArray(messagesData)) {
              for (let index = messagesData.length - 1; index >= 0; index -= 1) {
                const candidate = extractAgentFromMessageEnvelope(messagesData[index])
                if (candidate) {
                  cacheSessionAgent(sessionID, candidate)
                  break
                }
              }
            }
          } catch {
            // best effort only
          }
        }
      } finally {
        agentLookupInFlight.delete(sessionID)
      }
    })()
  }

  const writeAuditSafe = async (entry: Omit<AuditEntry, "ts">): Promise<void> => {
    try {
      await appendAudit({
        ...entry,
        ts: new Date().toISOString(),
      })
    } catch {
      // logging must never break the host
    }
  }

  const cleanupCallTracking = (sessionID: string | null, callID: string | null): void => {
    if (!sessionID || !callID) {
      return
    }
    const key = callKey(sessionID, callID)
    callToolByKey.delete(key)
    callArgsByKey.delete(key)
  }

  return {
    dispose: async () => {
      instanceRegistry.delete(instanceKey)
    },

    "tool.execute.before": async (input, output) => {
      try {
        const sessionID = asString(input.sessionID)
        const callID = asString(input.callID)
        const tool = asString(input.tool)
        const argsSummary = summarizeArgs(tool, output.args)

        if (sessionID && callID && tool) {
          mapSetWithCap(callToolByKey, callKey(sessionID, callID), tool)
          mapSetWithCap(callArgsByKey, callKey(sessionID, callID), argsSummary)
        }

        let agent = extractAgentCandidate(input, output)
        if (sessionID && agent) {
          cacheSessionAgent(sessionID, agent)
        }
        if (!agent) {
          agent = getSessionAgent(sessionID)
        }
        if (!agent) {
          warmAgentCache(sessionID)
        }

        await writeAuditSafe({
          kind: "tool.before",
          sessionID,
          callID,
          requestID: null,
          id: null,
          tool,
          agent,
          argsSummary,
          patterns: null,
          permission: null,
          reply: null,
          status: null,
          error: null,
          deny: null,
        })
      } catch {
        // logging must never break the host
      }
    },

    "tool.execute.after": async (input, output) => {
      try {
        const sessionID = asString(input.sessionID)
        const callID = asString(input.callID)
        const tool = asString(input.tool)
        const argsSummary = summarizeArgs(tool, input.args)
        const error = inferToolAfterError(output)

        let agent = extractAgentCandidate(input, output)
        if (sessionID && agent) {
          cacheSessionAgent(sessionID, agent)
        }
        if (!agent) {
          agent = getSessionAgent(sessionID)
        }
        if (!agent) {
          warmAgentCache(sessionID)
        }

        await writeAuditSafe({
          kind: "tool.after",
          sessionID,
          callID,
          requestID: null,
          id: null,
          tool,
          agent,
          argsSummary,
          patterns: null,
          permission: null,
          reply: null,
          status: null,
          error,
          deny: null,
        })

        cleanupCallTracking(sessionID, callID)
      } catch {
        // logging must never break the host
      }
    },

    "permission.ask": async (input, output) => {
      try {
        const sessionID = asString(input.sessionID)
        const callID = asString(input.callID)
        const requestID = asString(input.id)
        const permission = asString(input.type)
        const patterns = normalizePatterns(input.pattern)
        const messageID = asString(input.messageID)
        const key = sessionID && callID ? callKey(sessionID, callID) : null
        const tool = (key ? callToolByKey.get(key) : null) ?? extractToolFromMetadata(input.metadata)
        const argsSummary =
          (key ? callArgsByKey.get(key) ?? null : null) ?? summarizePermissionMetadataArgs(input.metadata)

        let agent = extractAgentCandidate(input, input.metadata, output)
        if (sessionID && agent) {
          cacheSessionAgent(sessionID, agent)
        }
        if (!agent) {
          agent = getSessionAgent(sessionID)
        }
        if (!agent) {
          warmAgentCache(sessionID, messageID ?? undefined)
        }

        if (sessionID && requestID) {
          setAddWithCap(askedLoggedByKey, requestKey(sessionID, requestID))
          mapSetWithCap(requestContextByKey, requestKey(sessionID, requestID), {
            callID,
            tool,
            argsSummary,
            permission,
            patterns,
          })
        }

        await writeAuditSafe({
          kind: "permission.asked",
          sessionID,
          callID,
          requestID,
          id: requestID,
          tool,
          agent,
          argsSummary,
          patterns,
          permission,
          reply: null,
          status: asString(output.status),
          error: null,
          deny: null,
        })
      } catch {
        // logging must never break the host
      }
    },

    event: async ({ event }) => {
      try {
        const rawEvent = event as unknown
        if (!isRecord(rawEvent)) {
          return
        }

        const type = asString(rawEvent.type)
        if (!type) {
          return
        }

        const properties = isRecord(rawEvent.properties) ? rawEvent.properties : null

        if (properties) {
          const eventSessionID = asString(properties.sessionID)
          const eventAgent =
            asString(properties.agent) ??
            (isRecord(properties.info) ? asString(properties.info.agent) : null) ??
            (isRecord(properties.metadata) ? asString(properties.metadata.agent) : null)

          cacheSessionAgent(eventSessionID, eventAgent)
        }

        if (type === "permission.asked" || type === "permission.updated") {
          if (!properties) {
            return
          }

          const sessionID = asString(properties.sessionID)
          const requestID = asString(properties.id)
          const permission =
            type === "permission.asked" ? asString(properties.permission) : asString(properties.type)
          const patterns =
            type === "permission.asked"
              ? normalizePatterns(properties.patterns)
              : normalizePatterns(properties.pattern)
          const toolInfo = isRecord(properties.tool) ? properties.tool : null
          const callID = asString(toolInfo?.callID) ?? asString(properties.callID)
          const messageID = asString(toolInfo?.messageID) ?? asString(properties.messageID)
          const metadata = isRecord(properties.metadata) ? properties.metadata : null
          const key = sessionID && callID ? callKey(sessionID, callID) : null
          const tool = (key ? callToolByKey.get(key) : null) ?? extractToolFromMetadata(metadata)
          const argsSummary =
            (key ? callArgsByKey.get(key) ?? null : null) ?? summarizePermissionMetadataArgs(metadata)

          const askKey = sessionID && requestID ? requestKey(sessionID, requestID) : null
          if (askKey && askedLoggedByKey.has(askKey)) {
            return
          }

          let agent = extractAgentCandidate(properties, metadata, toolInfo)
          if (sessionID && agent) {
            cacheSessionAgent(sessionID, agent)
          }
          if (!agent) {
            agent = getSessionAgent(sessionID)
          }
          if (!agent) {
            warmAgentCache(sessionID, messageID ?? undefined)
          }

          if (sessionID && requestID) {
            setAddWithCap(askedLoggedByKey, requestKey(sessionID, requestID))
            mapSetWithCap(requestContextByKey, requestKey(sessionID, requestID), {
              callID,
              tool,
              argsSummary,
              permission,
              patterns,
            })
          }

          await writeAuditSafe({
            kind: "permission.asked",
            sessionID,
            callID,
            requestID,
            id: requestID,
            tool,
            agent,
            argsSummary,
            patterns,
            permission,
            reply: null,
            status: null,
            error: null,
            deny: null,
          })

          return
        }

        if (type === "permission.replied") {
          if (!properties) {
            return
          }

          const sessionID = asString(properties.sessionID)
          const requestID = asString(properties.requestID) ?? asString(properties.permissionID)
          const reply = asString(properties.reply) ?? asString(properties.response)
          const context =
            sessionID && requestID ? requestContextByKey.get(requestKey(sessionID, requestID)) ?? null : null

          const callID = context?.callID ?? asString(properties.callID) ?? null
          const tool = context?.tool ?? null
          const permission = context?.permission ?? null
          const patterns = context?.patterns ?? null
          const argsSummary = context?.argsSummary ?? null

          let agent = extractAgentCandidate(properties)
          if (sessionID && agent) {
            cacheSessionAgent(sessionID, agent)
          }
          if (!agent) {
            agent = getSessionAgent(sessionID)
          }
          if (!agent) {
            warmAgentCache(sessionID)
          }

          await writeAuditSafe({
            kind: "permission.replied",
            sessionID,
            callID,
            requestID,
            id: null,
            tool,
            agent,
            argsSummary,
            patterns,
            permission,
            reply,
            status: null,
            error: null,
            deny: null,
          })

          if (sessionID && requestID) {
            requestContextByKey.delete(requestKey(sessionID, requestID))
            askedLoggedByKey.delete(requestKey(sessionID, requestID))
          }

          cleanupCallTracking(sessionID, callID)
        }
      } catch {
        // logging must never break the host
      }
    },
  }
}) satisfies Plugin
