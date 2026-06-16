// advisor-egress-log.js — OpenCode plugin: audit every byte sent to the cloud advisor.
//
// WHY: the `-hybrid` mode adds a read-only cloud-Claude advisor subagent (see
// agents/advisor.md). It's manual-only and prompt-only — it sees nothing but the
// text you hand it — but "what left the box" is exactly the kind of thing a
// privacy-gated setup must be able to prove after the fact. This plugin writes an
// append-only, structured record of every advisor invocation so the egress is
// auditable, not just trusted.
//
// HOW (verified against @opencode-ai/plugin 1.17.x + observed dispatch): the
// advisor can be reached two ways, and they surface on different hooks:
//   1. the local primary delegates via the `task` tool (subagent_type:"advisor")
//      → caught by `tool.execute.before` (input.tool === "task"),
//   2. you @mention it / it runs as its own session
//      → caught by `chat.message`, whose input carries the session `agent`.
// We register BOTH so no egress path is missed (under-logging is the one
// unacceptable failure for an audit log), and dedup by prompt within a short
// window so a single consultation that trips both hooks is recorded once. The
// plugin is a pure observer: it never mutates args/messages and never throws.
//
// LOG LOCATION: $ADVISOR_EGRESS_LOG (ai.sh sets this to <repo>/logs/
// advisor-egress.jsonl). Named .jsonl, not .log, on purpose: ai.sh prunes
// logs/*.log older than 14 days, and an audit trail must outlive that.

import { appendFileSync, mkdirSync } from "node:fs";
import { dirname } from "node:path";

const ADVISOR_AGENT = "advisor";
const DEDUP_WINDOW_MS = 10_000; // the two hooks for ONE call fire ~instantly; real
//                                 repeat consultations are seconds apart, so a short
//                                 window dedups double-fires without dropping genuine
//                                 re-asks (under-logging an audit trail is the one
//                                 thing we must not do).

// Resolve the log path from the env ai.sh exports; fall back to a sensible local
// path so a non-ai.sh launch still records rather than silently dropping egress.
const LOG_PATH =
  process.env.ADVISOR_EGRESS_LOG && process.env.ADVISOR_EGRESS_LOG.trim()
    ? process.env.ADVISOR_EGRESS_LOG.trim()
    : `${process.env.HOME || "."}/.ai/advisor-egress.jsonl`;

// Module-level dedup state (lives for the opencode session).
const recent = new Map(); // prompt → last-logged epoch ms

const pick = (obj, keys) => {
  for (const k of keys) {
    if (obj && typeof obj[k] === "string" && obj[k] !== "") return obj[k];
  }
  return "";
};

// Append one egress record unless an identical prompt was just logged (the same
// consultation arriving on the other hook). Never throws.
const logEgress = (record) => {
  try {
    const prompt = record.prompt;
    if (!prompt || !prompt.trim()) return;

    const now = Date.now();
    const last = recent.get(prompt);
    if (last !== undefined && now - last < DEDUP_WINDOW_MS) return; // dedup double-fire
    recent.set(prompt, now);
    if (recent.size > 64) {
      // bound the map: drop the oldest few entries
      for (const k of recent.keys()) {
        if (recent.size <= 48) break;
        recent.delete(k);
      }
    }

    mkdirSync(dirname(LOG_PATH), { recursive: true });
    appendFileSync(LOG_PATH, JSON.stringify({ ts: new Date(now).toISOString(), ...record }) + "\n");
  } catch {
    // An audit logger must never break the agent loop — swallow everything.
  }
};

export const AdvisorEgressLog = async () => {
  return {
    // Path 1: the local primary delegates to the advisor via the `task` tool.
    "tool.execute.before": async (input, output) => {
      try {
        if (!input || input.tool !== "task") return;
        const args = (output && output.args) || (input && input.args) || {};
        const agent = pick(args, ["subagent_type", "subagentType", "agent", "agentName", "subagent"]);
        if (agent !== ADVISOR_AGENT) return;
        logEgress({
          via: "task",
          agent,
          sessionID: (input && input.sessionID) || null,
          callID: (input && input.callID) || null,
          prompt: pick(args, ["prompt", "description", "message"]),
        });
      } catch {
        /* never break the loop */
      }
    },

    // Path 2: a message lands in the advisor's own session (@mention / direct run).
    "chat.message": async (input, output) => {
      try {
        if (!input || input.agent !== ADVISOR_AGENT) return;
        const parts = (output && Array.isArray(output.parts) && output.parts) || [];
        const prompt = parts
          .filter((p) => p && p.type === "text" && typeof p.text === "string")
          .map((p) => p.text)
          .join("\n");
        logEgress({
          via: "chat.message",
          agent: input.agent,
          sessionID: input.sessionID || null,
          messageID: input.messageID || null,
          model: input.model || null, // confirms it went to the anthropic provider
          prompt,
        });
      } catch {
        /* never break the loop */
      }
    },
  };
};
