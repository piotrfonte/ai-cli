#!/usr/bin/env node
// patch-omlx-muse-toolcall.mjs — harden oMLX's Muse Glimmer output parser.
//
// Muse Glimmer's chat template frames every message as
//
//   <|start|>assistant to=<recipient><|message|>BODY(<|eom|>|<|eot|>)
//
// and renders a tool call as that header plus an XML body naming the tool a
// SECOND time:
//
//   <|start|>assistant to=bash<|message|><atem:function_calls>
//   <atem:invoke name="bash">
//   <atem:parameter name="command">git status</atem:parameter>
//   </atem:invoke>
//   </atem:function_calls><|eom|>
//
// A body whose recipient is neither `self` nor `user` is SUPPRESSED while
// streaming and parsed only at finalize. That is the whole risk in this file:
// when the parse then fails, the tokens are already gone and the client gets an
// empty answer with finish_reason=stop. opencode reads that as "no tool call"
// and leaves the agent loop, so the session dies with no error anywhere.
//
// FIVE fixes. 1 and 2 close ticket W22. 3, 4 and 5 close the silent stop
// measured on 2026-08-13, when a /init run ended at step 9 after 56 tokens that
// reached the client as nothing at all, and again that evening on a turn whose
// reasoning ended "Let's webfetch." and showed the user nothing.
//
//   1/5  INVOKE NAME, two model slips, one repair each.
//        a. The model repeats the header's `<name><|message|>` pattern inside
//           the tag: name="bash<|message|>". _INVOKE_RE captures [^"]+, so the
//           special token lands in the tool name and the client rejects the
//           call as unknown. A real tool name never holds "<", so truncating
//           there is lossless for well-formed output. NOT fixed by tightening
//           the regex to [^"<]+ — the tag would then fail to match and the call
//           would be DROPPED, which is worse than mis-naming it: the arguments
//           parse fine and the header already named the tool correctly.
//        b. The model treats the tool as a namespace, because its own template
//           teaches to=example_tool_name.example_function_name. It emits
//           name="read.filePath" — the tool paired with one of its PARAMETER
//           names. Seen live twice (read.filePath, webfetch.url), each costing
//           a turn. When the full name is unknown and the segment before the
//           first "." IS a declared tool, that segment is the tool.
//
//   2/5  STRAY <|message|> INSIDE A TOOL BODY. _MuseChannelSplitter treats
//        every <|message|> as a channel switch, including one arriving while
//        the channel is already "tool". The head buffer is empty at that point,
//        so _RECIPIENT_RE finds no `to=`, the channel falls to "text", and the
//        rest of the XML streams to the user as visible output. A well-formed
//        tool body is XML and never holds a header, and a genuine next message
//        always follows <|eom|>, <|eot|> or <|start|> — each of which closes
//        the channel first. So ignoring it there cannot swallow a real header.
//
//   3/5  THE TWO HEADER READERS DISAGREED. _MuseChannelSplitter finds the
//        recipient with _RECIPIENT_RE.search, so `to=` may sit ANYWHERE in the
//        header. _extract_tool_calls demanded `assistant\s+to=`, so `to=` had
//        to come first. A header with any token before `to=` therefore went to
//        the suppressed tool channel and then matched nothing — the whole turn
//        vanished: no text, no tool call, no error, no log line. The extractor
//        now captures the header whole and reads it with _RECIPIENT_RE, so the
//        two cannot drift apart again.
//
//   4/5  NEVER DROP A SUPPRESSED MESSAGE. The splitter keeps what it throws
//        away. When finalize parses no tool call out of a suppressed body, that
//        body is logged at WARNING — oMLX records raw model output nowhere
//        else, so such a turn was undiagnosable after the fact; the only trace
//        was an odd tok/s figure in the server log, because first_token_time
//        never got set. And when the turn would otherwise reach the client with
//        no answer at all, the body is surfaced as visible text, following the
//        rule the module already applies to an unclassified header: nothing the
//        model produced is ever dropped.
//
//        `answered` tracks the TEXT channel only, never the thinking channel.
//        Reasoning reaches the client, so counting it would have called this
//        turn healthy: opencode showed "Thought: 6.0s" and nothing else, on a
//        turn whose reasoning ended "Let's webfetch." (2026-08-13). A turn that
//        only thinks and then stops is a dead turn.
//
//   5/5  LOOSE TAGS. The model's own tool-definition prompt tells it the output
//        "is not expected to be valid XML and is parsed with regular
//        expressions". The namespace prefix and the quotes around the name are
//        therefore optional here. Widening cannot invent a call — tag, name and
//        arguments must all still be present — and these patterns only ever run
//        over tool-channel bodies.
//
// Blast radius is one model. This adapter is selected for `muse_glimmer` alone;
// GLM 4.7 Flash and Ternary Bonsai never load it.
//
// oMLX is installed editable from ~/.omlx/src, so the patched source IS what
// runs — but only from the next server start, because a live process already
// imported the old module. ai.sh appends "+musetc4" to the recorded build
// string when this succeeds, which makes the existing state-file build check
// restart a stale server on its own. The suffix carries a version number for
// exactly that reason: an older server and a newer source must not look alike.
//
// Idempotent, and it converges from any starting state. The unpatched adapter is
// stored beside the target as .orig-ai-cli and every run re-derives from it, so
// a future version of this script never has to know what this one wrote. The
// copy is refreshed whenever the target is found unpatched, which is what an
// oMLX upgrade leaves behind.
//
// Exit codes:
//   0  patched now, or already current
//   2  usage error
//   3  anchor not found, ambiguous, or an unknown patched state — the upgrade
//      moved the code. ai.sh warns; the failure mode is a lost turn, not a
//      wrong answer, so there is no rail to raise.
//
// Usage: node patch-omlx-muse-toolcall.mjs <omlx-src-dir>

import { readFileSync, writeFileSync, existsSync } from "fs";
import { join } from "path";

const SENTINEL = "__OMLX_MUSE_TOOLCALL_PATCHED__";
const VERSION = "__OMLX_MUSE_TOOLCALL_V5__";
const TARGET = join("omlx", "adapter", "muse_glimmer.py");
// The unpatched adapter, kept beside it. Every run re-derives the patched file
// from this copy, so a new version of this script never has to know what the
// previous one wrote. Refreshed whenever the target is found unpatched, which
// is what an oMLX upgrade leaves behind.
const PRISTINE = TARGET + ".orig-ai-cli";

const srcDir = process.argv[2];
if (!srcDir) {
  console.error("usage: patch-omlx-muse-toolcall.mjs <omlx-src-dir>");
  process.exit(2);
}

const path = join(srcDir, TARGET);
if (!existsSync(path)) {
  console.error(`[patch] skip (no such file): ${path}`);
  process.exit(3);
}

// ── Pristine anchors ────────────────────────────────────────────────────────

const FROM_NAME = `        for invoke in _INVOKE_RE.finditer(body):
            name = invoke.group(1)
`;

const FROM_SPLIT = `        if marker == _MUSE_MESSAGE:
            head, self._head = self._head, ""
            match = _RECIPIENT_RE.search(head)
`;

const FROM_HELPERS = `def _coerce_param_value(raw: str, schema: dict[str, Any] | None) -> Any:
`;

const FROM_TAGS = `_INVOKE_RE = re.compile(
    r'<atem:invoke\\s+name="([^"]+)"\\s*>(.*?)(?:</atem:invoke>|\\Z)',
    re.S,
)
_PARAM_RE = re.compile(
    r'<atem:parameter\\s+name="([^"]+)"\\s*>(.*?)(?:</atem:parameter>|\\Z)',
    re.S,
)
`;

const TO_TAGS = `# ${SENTINEL} (5/5) — the namespace prefix and the quotes are OPTIONAL.
#
# The model's own tool-definition prompt tells it "The output is not expected to
# be valid XML and is parsed with regular expressions", and it takes that at its
# word: it drops the \`atem:\` prefix, or quotes the name with ' instead of ".
# Every such body is suppressed as a tool channel and then matches nothing, so
# the turn reaches the client empty — the failure this file exists to stop.
#
# Widening here cannot invent a call. The tag, the name and the arguments must
# all still be present, an unknown name is still reported as unknown, and
# _extract_tool_calls runs these patterns over TOOL-channel bodies only, never
# over reasoning or over the visible answer.
_TAG_PREFIX = r"(?:[A-Za-z][\\w.-]*:)?"
_TAG_NAME = r'name\\s*=\\s*["\\']?([^"\\'>\\s]+)["\\']?\\s*>'
_INVOKE_RE = re.compile(
    r"<" + _TAG_PREFIX + r"invoke\\s+" + _TAG_NAME
    + r"(.*?)(?:</" + _TAG_PREFIX + r"invoke>|\\Z)",
    re.S,
)
_PARAM_RE = re.compile(
    r"<" + _TAG_PREFIX + r"parameter\\s+" + _TAG_NAME
    + r"(.*?)(?:</" + _TAG_PREFIX + r"parameter>|\\Z)",
    re.S,
)
`;

const FROM_SCAN = `    schemas = _tool_param_schemas(tools)
    tool_calls: list[dict[str, str]] = []

    search_text = _MUSE_START + "assistant" + raw_text
    message_re = re.compile(
        re.escape(_MUSE_START)
        + r"assistant\\s+to=([^\\s<]+)\\s*"
        + re.escape(_MUSE_MESSAGE)
        + r"(.*?)(?:"
        + re.escape(_MUSE_EOM)
        + r"|"
        + re.escape(_MUSE_EOT)
        + r"|"
        + re.escape(_MUSE_END_OF_TEXT)
        + r"|"
        + re.escape(_MUSE_START)
        + r"|\\Z)",
        re.S,
    )
    for match in message_re.finditer(search_text):
        recipient, body = match.group(1), match.group(2)
        if recipient in ("self", "user"):
            continue
`;

const FROM_STATE = `        self._think_open = False
        self.stopped = False
`;

const FROM_BODY = `        if self._channel in ("text", "thinking"):
            # Thinking flows to BOTH channels wrapped in <think> markers
            # (minimax pattern): the scheduler accumulates only
            # visible_text into request.output_text, and the API layer
            # extracts reasoning_content from the <think> block there.
            return text, text
        if self._channel == "tool":
            return "", ""
`;

const FROM_TOOL_CHANNEL = `            else:
                if self._think_open:
                    stream += "</think>"
                    visible += "</think>"
                    self._think_open = False
                self._channel = "tool"
`;

const FROM_FINALIZE = `        tool_calls = _extract_tool_calls(self._raw_text, self._tools)
        return OutputParserFinalizeResult(
`;

// ── v1 → pristine migration ─────────────────────────────────────────────────
// The exact strings v1 of this script wrote. Reversing them is deterministic
// and needs no git, so the file converges no matter which version installed it.

const V1_NAME = `        for invoke in _INVOKE_RE.finditer(body):
            # ${SENTINEL} (1/2) — the model sometimes repeats the header's
            # \`<name><|message|>\` pattern inside the tag, emitting
            # name="bash<|message|>". _INVOKE_RE captures [^"]+, so the special
            # token lands in the tool name and the client rejects the call as an
            # unknown tool. A real tool name never contains "<", so truncating
            # there is lossless for well-formed output and recovers the name
            # from malformed output. Tightening the regex instead would drop the
            # call outright. See .wayfinder/model-roster-swap ticket W22.
            name = invoke.group(1).split("<", 1)[0].strip()
`;

const V1_SPLIT = `        if marker == _MUSE_MESSAGE:
            if self._channel == "tool":
                # ${SENTINEL} (2/2) — already inside a tool body. A tool body is
                # ATEM XML and never contains a header, and a genuine next
                # message always arrives after <|eom|>, <|eot|> or <|start|>,
                # each of which closes the channel first. So a <|message|> here
                # is the model's stray token (see 1/2), not a new message.
                # Without this guard the empty head yields no \`to=\`, the channel
                # falls to "text", and the rest of the tool XML streams to the
                # user as visible output.
                return stream, visible
            head, self._head = self._head, ""
            match = _RECIPIENT_RE.search(head)
`;

// ── Replacements ────────────────────────────────────────────────────────────

const TO_NAME = `        for invoke in _INVOKE_RE.finditer(body):
            # ${SENTINEL} (1/4) — the model mis-writes the name in the tag two
            # ways, and each has its own repair.
            #
            # It repeats the header's \`<name><|message|>\` pattern inside the
            # tag, emitting name="bash<|message|>". _INVOKE_RE captures [^"]+,
            # so the special token lands in the tool name and the client rejects
            # the call as an unknown tool. A real tool name never contains "<",
            # so truncating there is lossless for well-formed output and
            # recovers the name from malformed output. Tightening the regex
            # instead would drop the call outright.
            #
            # It also treats the tool as a namespace, because its own template
            # teaches to=example_tool_name.example_function_name: it emits
            # name="read.filePath", pairing the tool with one of its PARAMETER
            # names. When the whole name is unknown but the segment before the
            # first "." is a declared tool, that segment is the tool. A
            # well-formed name never reaches the branch, and neither does a tool
            # genuinely named with a dot, because that name is known.
            # See .wayfinder/model-roster-swap ticket W22.
            name = invoke.group(1).split("<", 1)[0].strip()
            if known and name not in known and "." in name:
                head_name = name.split(".", 1)[0]
                if head_name in known:
                    name = head_name
`;

const TO_SPLIT = `        if marker == _MUSE_MESSAGE:
            if self._channel == "tool":
                # ${SENTINEL} (2/4) — already inside a tool body. A tool body is
                # ATEM XML and never contains a header, and a genuine next
                # message always arrives after <|eom|>, <|eot|> or <|start|>,
                # each of which closes the channel first. So a <|message|> here
                # is the model's stray token (see 1/4), not a new message.
                # Without this guard the empty head yields no \`to=\`, the channel
                # falls to "text", and the rest of the tool XML streams to the
                # user as visible output.
                return stream, visible
            head, self._head = self._head, ""
            match = _RECIPIENT_RE.search(head)
`;

const TO_HELPERS = `def _tool_required_params(tools: list[dict] | None) -> dict[str, set[str]]:
    """Map function name -> the parameter names its schema marks required.

    ${SENTINEL} — used to spot an invoke tag that parsed with NO arguments when
    the tool cannot work without them. That call is dead on arrival at the
    client, and nothing else in oMLX would say so.
    """
    required: dict[str, set[str]] = {}
    for tool in tools or []:
        if not isinstance(tool, dict):
            continue
        fn = tool.get("function") if isinstance(tool.get("function"), dict) else tool
        name = fn.get("name")
        parameters = fn.get("parameters")
        if not isinstance(name, str) or not isinstance(parameters, dict):
            continue
        names = parameters.get("required")
        if isinstance(names, list):
            required[name] = {n for n in names if isinstance(n, str)}
    return required


def _tool_names(tools: list[dict] | None) -> set[str]:
    """Every function name an OpenAI tools list declares.

    ${SENTINEL} — the valid-name table the invoke-name repair (1/4) tests
    against. Kept separate from _tool_param_schemas, which drops any tool whose
    \`parameters\` is missing or malformed; a tool with no parameters is still a
    tool, and repairing its name must not depend on it having a schema.
    """
    names: set[str] = set()
    for tool in tools or []:
        if not isinstance(tool, dict):
            continue
        fn = tool.get("function") if isinstance(tool.get("function"), dict) else tool
        name = fn.get("name")
        if isinstance(name, str):
            names.add(name)
    return names


def _coerce_param_value(raw: str, schema: dict[str, Any] | None) -> Any:
`;

const TO_SCAN = `    schemas = _tool_param_schemas(tools)
    known = _tool_names(tools)
    required_params = _tool_required_params(tools)
    tool_calls: list[dict[str, str]] = []

    # ${SENTINEL} (3/4) — the header is captured whole and read with
    # _RECIPIENT_RE, which is how _MuseChannelSplitter reads it. The original
    # pattern demanded \`assistant\\s+to=\`, so \`to=\` had to be the first thing in
    # the header, while the splitter searches for it ANYWHERE in the same text.
    # A header with any token before \`to=\` therefore went to the suppressed tool
    # channel there and matched nothing here, and the whole turn vanished with
    # no text, no tool call and no error. Both now read the header the same way,
    # so they cannot disagree. The header capture is bounded by every message
    # marker, so it can never run past <|eom|> into the next message.
    search_text = _MUSE_START + "assistant" + raw_text
    _header_stop = "|".join(
        re.escape(marker)
        for marker in (
            _MUSE_MESSAGE,
            _MUSE_EOM,
            _MUSE_EOT,
            _MUSE_END_OF_TEXT,
            _MUSE_START,
        )
    )
    message_re = re.compile(
        re.escape(_MUSE_START)
        + r"assistant((?:(?!"
        + _header_stop
        + r").)*?)"
        + re.escape(_MUSE_MESSAGE)
        + r"(.*?)(?:"
        + re.escape(_MUSE_EOM)
        + r"|"
        + re.escape(_MUSE_EOT)
        + r"|"
        + re.escape(_MUSE_END_OF_TEXT)
        + r"|"
        + re.escape(_MUSE_START)
        + r"|\\Z)",
        re.S,
    )
    for match in message_re.finditer(search_text):
        head, body = match.group(1), match.group(2)
        recipient_match = _RECIPIENT_RE.search(head)
        recipient = recipient_match.group(1) if recipient_match else None
        if recipient is None or recipient in ("self", "user"):
            continue
`;

const TO_STATE = `        self._think_open = False
        self.stopped = False
        # ${SENTINEL} (4/4a) — what the tool channel swallowed, and whether the
        # client ever got an ANSWER. A tool body emits nothing while streaming,
        # so a turn whose tool call fails to parse reaches the client with
        # nothing in it. finalize reads both; it cannot infer either from its
        # own return values, which hold the tail of the generation only.
        #
        # \`answered\` deliberately ignores the thinking channel. Reasoning does
        # reach the client, so counting it would call a thought-only turn
        # healthy — and that is exactly the shape the user sees as dead:
        # "Thought: 6.0s", then nothing.
        self.answered = False
        self.suppressed = ""
`;

const TO_BODY = `        if self._channel in ("text", "thinking"):
            # Thinking flows to BOTH channels wrapped in <think> markers
            # (minimax pattern): the scheduler accumulates only
            # visible_text into request.output_text, and the API layer
            # extracts reasoning_content from the <think> block there.
            if self._channel == "text":
                # ${SENTINEL} (4/4b) — an answer, not a thought.
                self.answered = True
            return text, text
        if self._channel == "tool":
            # ${SENTINEL} (4/4b) — keep what is being thrown away, so finalize
            # can report it if no tool call comes out of it.
            self.suppressed += text
            return "", ""
`;

const TO_TOOL_CHANNEL = `            else:
                if self._think_open:
                    stream += "</think>"
                    visible += "</think>"
                    self._think_open = False
                self._channel = "tool"
                # ${SENTINEL} (4/4c) — the header goes into the record too: it
                # carries the recipient, which is the one piece of evidence that
                # says WHICH tool the model was reaching for when the body
                # failed to parse.
                self.suppressed += head + _MUSE_MESSAGE
`;

const TO_FINALIZE = `        tool_calls = _extract_tool_calls(self._raw_text, self._tools)
        suppressed = self._splitter.suppressed
        if suppressed and not tool_calls:
            # ${SENTINEL} (4/4d) — a message was suppressed as a tool call and
            # no tool call came out of it. Those tokens are gone: the client
            # sees an answer that is missing them, and when there is no answer
            # at all it sees finish_reason=stop with empty content, which
            # opencode reads as "no tool call" and leaves the agent loop over.
            # Twice on 2026-08-13: a /init run that stopped at step 9, and a
            # turn whose reasoning ended "Let's webfetch." and showed nothing.
            #
            # ALWAYS log it. oMLX records model output nowhere else, so this is
            # the only way such a turn can ever be diagnosed after the fact —
            # the sole trace in the server log is an odd tok/s figure, and only
            # when nothing at all was emitted.
            logger.warning(
                "Muse Glimmer: %d chars were suppressed as a tool call and no "
                "tool call parsed out of them. The client loses those tokens%s. "
                "Suppressed model output%s:\\n%s",
                len(suppressed),
                "" if self.answered_this_turn(stream_text, visible_text) else
                " and receives an empty answer",
                " (first 4000 chars)" if len(suppressed) > 4000 else "",
                suppressed[:4000],
            )
            if not self.answered_this_turn(stream_text, visible_text):
                # Surface it rather than answer nothing, which is the rule the
                # rest of this module already follows for an unclassified
                # header: nothing the model produced is ever dropped. Ugly XML
                # beats a dead turn, and it shows what the model tried to do.
                stream_text += suppressed
                visible_text += suppressed
        return OutputParserFinalizeResult(
`;

// Small helper so the condition above reads once and cannot drift between its
// two uses.
const FROM_SESSION_CLASS = `    def finalize(self) -> OutputParserFinalizeResult:
`;

const TO_SESSION_CLASS = `    def answered_this_turn(self, stream_text: str, visible_text: str) -> bool:
        """Did the client get an ANSWER — not merely reasoning — this turn?

        ${SENTINEL} — reasoning reaches the client, so it must not count here.
        A turn that only thinks and then stops is the dead turn the user sees as
        "Thought: 6.0s" followed by nothing.
        """
        return bool(self._splitter.answered or stream_text or visible_text)

    def finalize(self) -> OutputParserFinalizeResult:
`;

// ── Apply ───────────────────────────────────────────────────────────────────

const pristinePath = join(srcDir, PRISTINE);
let src = readFileSync(path, "utf8");

if (src.includes(VERSION)) {
  process.exit(0);
}

if (!src.includes(SENTINEL)) {
  // Unpatched, so this IS the pristine adapter — including straight after an
  // oMLX upgrade, which is the moment the stored copy must be refreshed.
  writeFileSync(pristinePath, src);
} else if (existsSync(pristinePath)) {
  // Patched by an older version of this script. Re-derive from the stored base
  // rather than reverse-engineering whatever that version wrote.
  src = readFileSync(pristinePath, "utf8");
  if (src.includes(SENTINEL)) {
    console.error(`[patch] ${PRISTINE} is not a clean adapter — not patching`);
    process.exit(3);
  }
} else {
  // Patched before the base copy existed. v1 is the only such version, and its
  // two edits are known exactly, so reverse them.
  src = src.replace(V1_NAME, FROM_NAME).replace(V1_SPLIT, FROM_SPLIT);
  if (src.includes(SENTINEL)) {
    console.error(
      `[patch] ${TARGET} carries an unrecognised ${SENTINEL} edit and no ${PRISTINE} to fall back on.`,
    );
    console.error(`[patch] Restore it (git -C ${srcDir} checkout -- ${TARGET}) and re-run.`);
    process.exit(3);
  }
  writeFileSync(pristinePath, src);
}

const FIXES = [
  ["invoke-name", FROM_NAME, TO_NAME],
  ["channel-splitter", FROM_SPLIT, TO_SPLIT],
  ["tool-name-table", FROM_HELPERS, TO_HELPERS],
  ["tag-tolerance", FROM_TAGS, TO_TAGS],
  ["header-scan", FROM_SCAN, TO_SCAN],
  ["splitter-state", FROM_STATE, TO_STATE],
  ["suppressed-body", FROM_BODY, TO_BODY],
  ["suppressed-header", FROM_TOOL_CHANNEL, TO_TOOL_CHANNEL],
  ["answered-helper", FROM_SESSION_CLASS, TO_SESSION_CLASS],
  ["never-drop", FROM_FINALIZE, TO_FINALIZE],
];

// Verify every anchor before writing anything: a half-patched adapter is worse
// than an unpatched one.
for (const [label, from] of FIXES) {
  const hits = src.split(from).length - 1;
  if (hits === 0) {
    console.error(`[patch] Muse tool-call ${label} anchor not found in ${TARGET} — oMLX has moved it`);
    process.exit(3);
  }
  if (hits > 1) {
    console.error(`[patch] Muse tool-call ${label} anchor is ambiguous in ${TARGET} (${hits} matches) — not patching`);
    process.exit(3);
  }
}

for (const [, from, to] of FIXES) {
  src = src.replace(from, to);
}

// The version marker rides in the module docstring, so it survives any future
// reordering of the fixes and is the one thing the idempotency check reads.
const DOCSTRING_END = `\`\`<|eom|>\`\` ends a message with the turn continuing; \`\`<|eot|>\`\` and
\`\`<|end_of_text|>\`\` end the turn (both are eos in generation_config).
"""`;
if (!src.includes(DOCSTRING_END)) {
  console.error(`[patch] Muse tool-call docstring anchor not found in ${TARGET} — oMLX has moved it`);
  process.exit(3);
}
src = src.replace(
  DOCSTRING_END,
  `\`\`<|eom|>\`\` ends a message with the turn continuing; \`\`<|eot|>\`\` and
\`\`<|end_of_text|>\`\` end the turn (both are eos in generation_config).

Patched by ai-cli (${VERSION}): invoke-name repair, stray-<|message|> guard,
header scan aligned with the splitter, and a never-drop rail on a turn that
would otherwise reach the client empty. See scripts/patch-omlx-muse-toolcall.mjs.
"""`,
);

writeFileSync(path, src);
console.error("[patch] oMLX Muse Glimmer output parser hardened (invoke name, stray <|message|>, header scan, never-drop)");
process.exit(0);
