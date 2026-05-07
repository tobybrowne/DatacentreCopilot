import asyncio
import json
import os

import websockets
from fastapi import WebSocket, WebSocketDisconnect

_API_KEY = os.environ.get("OPENAI_API_KEY") or os.environ.get("OPENAI_KEY")
_MODEL = "gpt-realtime-mini-2025-12-15"
_URL = f"wss://api.openai.com/v1/realtime?model={_MODEL}"

INSTRUCTIONS = """
You are a helpful AR assistant built into a Magic Leap 2 headset.
Keep responses concise (not conversational) — the user is hands-free and working in a datacentre.

IMPORTANT:
- Don't be too wordy.
- Don't read out UUIDs.
- Use the `query_table` tool to look up any information you need.
- Just answer the question, don't say "I looked it up and the answer is..." — the user doesn't care about the lookup process, just the answer.
- Also don't keep saying "Let me know if you need anything else..." or similar sign-off phrases, just answer the question.
- If you are unsure what the user is talking about or referring to, ask a clarifying question, don't guess.

CONTEXT:
- You will be provided with context updates, explaining the user's current situation.
- Use this to inform their answers, for example:
- If the user says "What is this?" they are probably referring to something they are looking at or interacting with.
- If someone asks about the last actions on an asset, use the logs to check.


DATABASE SCHEMA — use query_table to look things up:
- users: id, contact_email, created_at
- assets: id, name, asset_type (ups/pdu/ahu/humidifier/generator/ats/switchgear/...), building_id, created_at, updated_at
- procedures: id, title, created_at
- procedure_runs: id, procedure_id, user_id, started_at, completed_at
- logs: id, procedure_run_id, step_id, user_id, site_id, created_at
- log_assets: id, log_id, asset_id  — links a log to the assets it touched
"""



async def run_proxy(godot_ws: WebSocket) -> None:
    if not _API_KEY:
        print("[copilot] ERROR: OPENAI_KEY not set")
        await godot_ws.send_text(json.dumps({"type": "error", "message": "OPENAI_KEY not set"}))
        return

    print(f"[copilot] connecting to OpenAI ({_MODEL})...")
    try:
        async with websockets.connect(
            _URL,
            additional_headers={
                "Authorization": f"Bearer {_API_KEY}",
                "OpenAI-Beta": "realtime=v1",
            },
        ) as openai_ws:
            print("[copilot] OpenAI connected")
            if INSTRUCTIONS:
                await openai_ws.send(json.dumps({
                    "type": "session.update",
                    "session": {"instructions": INSTRUCTIONS},
                }))
            t1 = asyncio.create_task(_godot_to_openai(godot_ws, openai_ws))
            t2 = asyncio.create_task(_openai_to_godot(openai_ws, godot_ws))
            _, pending = await asyncio.wait([t1, t2], return_when=asyncio.FIRST_COMPLETED)
            for task in pending:
                task.cancel()
                try:
                    await task
                except asyncio.CancelledError:
                    pass
            print("[copilot] session ended")
    except Exception as exc:
        print(f"[copilot] ERROR connecting to OpenAI: {exc}")
        try:
            await godot_ws.send_text(json.dumps({"type": "error", "message": str(exc)}))
        except Exception:
            pass


async def _godot_to_openai(
    godot_ws: WebSocket,
    openai_ws: websockets.WebSocketClientProtocol,
) -> None:
    audio_chunks = 0
    try:
        while True:
            data = await godot_ws.receive_text()
            msg = json.loads(data)
            t = msg.get("type")

            if t == "audio":
                audio_chunks += 1
                if audio_chunks % 50 == 1:
                    print(f"[copilot] godot→openai: audio chunk #{audio_chunks} ({len(msg['data'])} b64 chars)")
                await openai_ws.send(json.dumps({
                    "type": "input_audio_buffer.append",
                    "audio": msg["data"],
                }))

            elif t == "commit_audio":
                await openai_ws.send(json.dumps({"type": "input_audio_buffer.commit"}))
                await openai_ws.send(json.dumps({"type": "response.create"}))

            elif t == "session_update":
                session = msg["session"]
                session.pop("instructions", None)
                tool_names = [t["name"] for t in session.get("tools", [])]
                print(f"[copilot] godot→openai: session_update tools={tool_names}")
                await openai_ws.send(json.dumps({
                    "type": "session.update",
                    "session": session,
                }))

            elif t == "inject_context":
                print("Update Context:")
                # pretty print dict
                print(json.dumps(msg["text"], indent=2))
                
                await openai_ws.send(json.dumps({
                    "type": "conversation.item.create",
                    "item": {
                        "type": "message",
                        "role": "user",
                        "content": [{"type": "input_text", "text": msg["text"]}],
                    },
                }))

            elif t == "function_output":
                await openai_ws.send(json.dumps({
                    "type": "conversation.item.create",
                    "item": {
                        "type": "function_call_output",
                        "call_id": msg["call_id"],
                        "output": msg["output"],
                    },
                }))
                await openai_ws.send(json.dumps({"type": "response.create"}))

    except (WebSocketDisconnect, Exception) as exc:
        print(f"[copilot] godot→openai task ended: {exc}")


async def _openai_to_godot(
    openai_ws: websockets.WebSocketClientProtocol,
    godot_ws: WebSocket,
) -> None:
    try:
        async for raw in openai_ws:
            msg = json.loads(raw)
            t = msg.get("type", "")

            if t != "response.audio.delta":
                print(f"[copilot] openai→godot: {t}")

            if t == "response.audio.delta":
                await godot_ws.send_text(json.dumps({
                    "type": "audio",
                    "data": msg["delta"],
                }))

            elif t == "response.output_item.done":
                item = msg.get("item", {})
                if item.get("type") == "function_call":
                    await godot_ws.send_text(json.dumps({
                        "type": "function_call",
                        "name": item["name"],
                        "call_id": item["call_id"],
                        "args": json.loads(item.get("arguments", "{}")),
                    }))

            elif t == "response.audio_transcript.done":
                await godot_ws.send_text(json.dumps({
                    "type": "transcript",
                    "role": "assistant",
                    "text": msg.get("transcript", ""),
                }))

            elif t == "conversation.item.input_audio_transcription.completed":
                await godot_ws.send_text(json.dumps({
                    "type": "transcript",
                    "role": "user",
                    "text": msg.get("transcript", ""),
                }))

            elif t == "input_audio_buffer.speech_started":
                await godot_ws.send_text(json.dumps({"type": "status", "state": "listening"}))

            elif t == "response.created":
                await godot_ws.send_text(json.dumps({"type": "status", "state": "thinking"}))

            elif t == "response.audio.done":
                await godot_ws.send_text(json.dumps({"type": "status", "state": "idle"}))

            elif t == "error":
                await godot_ws.send_text(json.dumps({
                    "type": "error",
                    "message": msg.get("error", {}).get("message", "unknown openai error"),
                }))

    except Exception as exc:
        print(f"[copilot] openai→godot task ended: {exc}")
