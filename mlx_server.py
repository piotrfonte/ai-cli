"""mlx_server.py — Thin wrapper that caps MLX Metal buffer cache and adds tool-call loop detection."""
import json
import logging
import mlx.core as mx

mx.set_cache_limit(2_000_000_000)  # 2 GB cap (prevents unbounded 10-15 GB growth)

MAX_TOOL_CALL_DEPTH = 25  # Max consecutive tool-call rounds before circuit breaker

logger = logging.getLogger("mlx_server")


def _patch_handler():
    """Monkey-patch mlx_lm's HTTP handler to detect tool-call loops.

    When a request contains more than MAX_TOOL_CALL_DEPTH tool messages,
    strip the tools array so the model generates a normal text response
    instead of yet another tool call.
    """
    from mlx_lm.server import APIHandler

    _original_do_POST = APIHandler.do_POST

    def _patched_do_POST(self):
        # Read and parse the request body to check for tool loops
        content_length = int(self.headers.get("Content-Length", 0))
        if content_length > 0 and self.path == "/v1/chat/completions":
            body = self.rfile.read(content_length)
            try:
                data = json.loads(body)
                messages = data.get("messages", [])
                tool_msg_count = sum(1 for m in messages if m.get("role") == "tool")

                if tool_msg_count > MAX_TOOL_CALL_DEPTH:
                    logger.warning(
                        f"Tool call loop detected: {tool_msg_count} tool messages "
                        f"(limit {MAX_TOOL_CALL_DEPTH}). Stripping tools from request."
                    )
                    # Remove tools so model can't generate more tool calls
                    data.pop("tools", None)
                    data.pop("tool_choice", None)
                    body = json.dumps(data).encode()
            except (json.JSONDecodeError, KeyError):
                pass

            # Re-inject the (possibly modified) body for the original handler
            import io
            self.rfile = io.BytesIO(body)
            self.headers.replace_header("Content-Length", str(len(body)))

        _original_do_POST(self)

    APIHandler.do_POST = _patched_do_POST


_patch_handler()

from mlx_lm.server import main
main()
