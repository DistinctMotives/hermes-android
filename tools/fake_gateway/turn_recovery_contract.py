"""Deterministic source-only fixture for the accepted turn-recovery v2 wire contract.

This module is test infrastructure.  It exercises durable correlation,
pagination, server-selected snapshots, reconnects, and out-of-band faults.  It
does not activate Android recovery or claim production gateway acceptance.
"""

from __future__ import annotations

import hashlib
import json
import os
import threading
import uuid
from pathlib import Path
from typing import Any


SCHEMA_VERSION = 2
PROTOCOL_NAME = "hermes-jsonrpc"
PROTOCOL_MAJOR = 2
MAX_EVENT_BYTES = 64 * 1024
MAX_TURN_BYTES = 4 * 1024 * 1024
TERMINAL_EVENT_RESERVE_BYTES = 1024
MAX_RECONCILE_EVENTS = 256
MAX_RECONCILE_PAGE_BYTES = 512 * 1024
MAX_ATTACHMENTS = 10
MAX_PROMPT_BYTES = 64 * 1024
MAX_FILE_ATTACHMENT_BYTES = 16 * 1024 * 1024
MAX_IMAGE_ATTACHMENT_BYTES = 25 * 1024 * 1024
MAX_PDF_ATTACHMENT_BYTES = 50 * 1024 * 1024
MAX_ATTACHMENT_REGISTRY_BYTES = 64 * 1024 * 1024
EVENT_RETENTION_SECONDS = 24 * 60 * 60
TURN_RETENTION_SECONDS = 7 * 24 * 60 * 60

TERMINAL_STATUSES = {"completed", "failed", "interrupted"}
ATTACHMENT_FIELDS = {
    "attachment_id",
    "client_attachment_id",
    "sha256",
    "byte_length",
    "media_type",
}
FAULT_AFTER_COMMIT_BEFORE_ACK = "after_commit_before_ack"
FAULT_AFTER_ACK_BEFORE_FIRST_DELTA = "after_ack_before_first_delta"
FAULT_MIDSTREAM = "mid_stream_after_2_deltas"
FAULT_AFTER_COMPLETION = "after_completion_before_terminal"
FAULTS = {
    FAULT_AFTER_COMMIT_BEFORE_ACK,
    FAULT_AFTER_ACK_BEFORE_FIRST_DELTA,
    FAULT_MIDSTREAM,
    FAULT_AFTER_COMPLETION,
}

_LEDGER_SCHEMA = "hermes.fake_gateway.turn_recovery.v2"
_PROMPT_REQUIRED_FIELDS = {"session_id", "version", "client_turn_id", "text"}
_PROMPT_ALLOWED_FIELDS = _PROMPT_REQUIRED_FIELDS | {"attachments"}
_FIXTURE_RECONCILE_PAGE_EVENTS = 2


def _compact_json(value: object) -> str:
    return json.dumps(
        value,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
    )


def _rpc_result(request_id: object, result: dict[str, object]) -> str:
    return json.dumps(
        {"jsonrpc": "2.0", "id": request_id, "result": result},
        ensure_ascii=False,
    )


def _rpc_error(
    request_id: object,
    message: str,
    code: int,
    reason: str,
) -> str:
    return json.dumps(
        {
            "jsonrpc": "2.0",
            "id": request_id,
            "error": {
                "code": code,
                "message": message,
                "data": {"reason": reason, "safe_to_resubmit": False},
            },
        },
        ensure_ascii=False,
    )


def _canonical_uuid(value: object) -> str | None:
    if not isinstance(value, str) or value != value.strip() or value.lower() != value:
        return None
    try:
        parsed = uuid.UUID(value)
    except (ValueError, AttributeError):
        return None
    if parsed.int == 0 or str(parsed) != value:
        return None
    return value


def _canonical_attachments(raw: object) -> list[dict[str, object]] | None:
    if raw is None:
        return []
    if not isinstance(raw, list) or len(raw) > MAX_ATTACHMENTS:
        return None
    result: list[dict[str, object]] = []
    for item in raw:
        if not isinstance(item, dict) or not set(item).issubset(ATTACHMENT_FIELDS):
            return None
        safe: dict[str, object] = {}
        for key in ("attachment_id", "client_attachment_id", "sha256", "media_type"):
            if key in item and item[key] is not None:
                value = item[key]
                if (
                    not isinstance(value, str)
                    or not value
                    or value != value.strip()
                    or len(value) > 256
                    or any(ord(character) < 32 for character in value)
                ):
                    return None
                safe[key] = value
        if "byte_length" in item:
            byte_length = item["byte_length"]
            if (
                isinstance(byte_length, bool)
                or not isinstance(byte_length, int)
                or byte_length < 0
            ):
                return None
            safe["byte_length"] = byte_length
        if not safe.get("attachment_id") and not safe.get("client_attachment_id"):
            return None
        result.append(safe)
    return result


def _request_digest(text: str, attachments: list[dict[str, object]]) -> str:
    return hashlib.sha256(
        _compact_json({"text": text, "attachments": attachments}).encode("utf-8")
    ).hexdigest()


def _attachment_digest(attachments: list[dict[str, object]]) -> str:
    return hashlib.sha256(_compact_json(attachments).encode("utf-8")).hexdigest()


class TurnRecoveryContractLedger:
    """Small persistent fake ledger plus per-process runtime bindings."""

    def __init__(
        self,
        ledger_path: Path | None = None,
        *,
        server_profile: str = "fixture-recovery-a",
    ) -> None:
        if not server_profile or server_profile != server_profile.strip():
            raise ValueError("server_profile is invalid")
        self._ledger_path = ledger_path
        self._server_profile = server_profile
        self._lock = threading.RLock()
        self._durable = self._load()
        self._durable["process_generation"] += 1
        self._runtime_counter = 0
        self._runtime_bindings: dict[str, dict[str, object]] = {}
        self._connection_runtime: dict[str, str] = {}
        self._next_fault: dict[str, str] = {}
        self._subscribers: dict[str, set[Any]] = {}
        self._save()

    @staticmethod
    def ready_frame() -> dict[str, object]:
        return {
            "jsonrpc": "2.0",
            "method": "event",
            "params": {
                "type": "gateway.ready",
                "payload": {
                    "skin": {},
                    "protocol": {
                        "name": PROTOCOL_NAME,
                        "major": PROTOCOL_MAJOR,
                        "minor": 0,
                    },
                    "capabilities": {
                        "turn_recovery": {
                            "version": SCHEMA_VERSION,
                            "shadow_only": False,
                            "methods": [
                                "session.open",
                                "turn.reconcile",
                                "turn.interrupt",
                                "attachment.detach@2",
                            ],
                            "prompt_submit_version": 2,
                            "applies_to": [
                                "session.open",
                                "prompt.submit@2",
                                "turn.reconcile",
                                "turn.interrupt",
                                "attachment.detach@2",
                            ],
                            "automatic_resubmit": False,
                            "execution_route": "single_process_in_process",
                            "event_retention_seconds": EVENT_RETENTION_SECONDS,
                            "turn_retention_seconds": TURN_RETENTION_SECONDS,
                            "max_event_bytes": MAX_EVENT_BYTES,
                            "max_turn_bytes": MAX_TURN_BYTES,
                            "terminal_event_reserve_bytes": TERMINAL_EVENT_RESERVE_BYTES,
                            "max_prompt_bytes": MAX_PROMPT_BYTES,
                            "mobile_session_id_format": "canonical_lowercase_uuid",
                            "client_turn_id_format": "canonical_lowercase_uuid",
                            "reconcile_max_events": MAX_RECONCILE_EVENTS,
                            "reconcile_max_page_bytes": MAX_RECONCILE_PAGE_BYTES,
                            "max_attachments": MAX_ATTACHMENTS,
                            "max_file_attachment_bytes": MAX_FILE_ATTACHMENT_BYTES,
                            "max_image_attachment_bytes": MAX_IMAGE_ATTACHMENT_BYTES,
                            "max_pdf_attachment_bytes": MAX_PDF_ATTACHMENT_BYTES,
                            "max_attachment_registry_bytes": (
                                MAX_ATTACHMENT_REGISTRY_BYTES
                            ),
                        }
                    },
                },
            },
        }

    @staticmethod
    def handles(payload: dict[str, object]) -> bool:
        method = payload.get("method")
        params = payload.get("params")
        params = params if isinstance(params, dict) else {}
        if method == "prompt.submit":
            return params.get("version") == 2 or "client_turn_id" in params
        return method in {
            "session.open",
            "turn.reconcile",
            "turn.interrupt",
            "fixture.turn.inspect",
            "fixture.turn.next_fault",
            "fixture.turn.prune",
            "fixture.turn.restart",
        }

    def detach(self, ws: Any, connection_id: str) -> None:
        for subscribers in self._subscribers.values():
            subscribers.discard(ws)
        self._connection_runtime.pop(connection_id, None)
        self._next_fault.pop(connection_id, None)

    async def handle(
        self,
        ws: Any,
        payload: dict[str, object],
        connection_id: str,
    ) -> None:
        request_id = payload.get("id")
        method = payload.get("method")
        raw_params = payload.get("params")
        params = raw_params if isinstance(raw_params, dict) else {}
        if method == "session.open":
            await self._session_open(ws, request_id, params, connection_id)
        elif method == "prompt.submit":
            await self._prompt_submit(ws, request_id, params, connection_id)
        elif method == "turn.reconcile":
            await self._reconcile(ws, request_id, params, connection_id)
        elif method == "turn.interrupt":
            await self._interrupt(ws, request_id, params, connection_id)
        elif method == "fixture.turn.next_fault":
            await self._configure_fault(ws, request_id, params, connection_id)
        elif method == "fixture.turn.prune":
            await self._prune(ws, request_id, params, connection_id)
        elif method == "fixture.turn.restart":
            await self._restart(ws, request_id)
        elif method == "fixture.turn.inspect":
            await ws.send_str(_rpc_result(request_id, self.inspection()))

    def inspection(self) -> dict[str, object]:
        with self._lock:
            turns = self._durable["turns"]
            return {
                "schema": _LEDGER_SCHEMA,
                "binding_count": len(self._durable["bindings"]),
                "turn_count": len(turns),
                "submit_attempt_count": int(self._durable["submit_attempt_count"]),
                "execution_count": int(self._durable["execution_count"]),
                "turns": [
                    {
                        "turn_id": turn["turn_id"],
                        "client_turn_id": turn["client_turn_id"],
                        "status": turn["status"],
                        "last_seq": turn["last_seq"],
                        "execution_count": turn["execution_count"],
                    }
                    for turn in turns.values()
                ],
            }

    def _load(self) -> dict[str, Any]:
        empty: dict[str, Any] = {
            "schema": _LEDGER_SCHEMA,
            "binding_counter": 0,
            "turn_counter": 0,
            "submit_attempt_count": 0,
            "execution_count": 0,
            "process_generation": 0,
            "bindings": {},
            "turns": {},
            "turn_by_client": {},
        }
        if self._ledger_path is None or not self._ledger_path.exists():
            return empty
        decoded = json.loads(self._ledger_path.read_text(encoding="utf-8"))
        if not isinstance(decoded, dict) or decoded.get("schema") != _LEDGER_SCHEMA:
            raise RuntimeError("turn recovery fixture ledger is invalid")
        if set(decoded) != set(empty):
            raise RuntimeError("turn recovery fixture ledger schema drift")
        self._validate_loaded_ledger(decoded)
        return decoded

    def _validate_loaded_ledger(self, decoded: dict[str, Any]) -> None:
        counter_names = {
            "binding_counter",
            "turn_counter",
            "submit_attempt_count",
            "execution_count",
            "process_generation",
        }
        if any(
            type(decoded.get(name)) is not int or decoded[name] < 0
            for name in counter_names
        ):
            raise RuntimeError("turn recovery fixture ledger counter drift")
        bindings = decoded.get("bindings")
        turns = decoded.get("turns")
        turn_by_client = decoded.get("turn_by_client")
        if not all(isinstance(value, dict) for value in (bindings, turns, turn_by_client)):
            raise RuntimeError("turn recovery fixture ledger collection drift")

        binding_fields = {
            "profile",
            "mobile_session_id",
            "stored_session_id",
            "binding_version",
        }
        stored_ids: set[str] = set()
        for binding_key, binding in bindings.items():
            if not isinstance(binding_key, str) or not isinstance(binding, dict):
                raise RuntimeError("turn recovery fixture binding drift")
            if set(binding) != binding_fields:
                raise RuntimeError("turn recovery fixture binding schema drift")
            profile = binding.get("profile")
            mobile_session_id = _canonical_uuid(binding.get("mobile_session_id"))
            stored_session_id = binding.get("stored_session_id")
            binding_version = binding.get("binding_version")
            if (
                profile != self._server_profile
                or mobile_session_id is None
                or not isinstance(stored_session_id, str)
                or not stored_session_id
                or type(binding_version) is not int
                or binding_version <= 0
                or binding_key != f"{profile}\u001f{mobile_session_id}"
                or stored_session_id in stored_ids
            ):
                raise RuntimeError("turn recovery fixture binding is invalid")
            stored_ids.add(stored_session_id)

        turn_fields = {
            "turn_id",
            "stored_session_id",
            "profile",
            "client_turn_id",
            "request_digest",
            "attachment_manifest_digest",
            "status",
            "last_seq",
            "first_retained_seq",
            "events",
            "message_id",
            "assistant_text",
            "final_message_ref",
            "execution_count",
        }
        expected_turn_by_client: dict[str, str] = {}
        execution_total = 0
        for turn_id, turn in turns.items():
            if not isinstance(turn_id, str) or not isinstance(turn, dict):
                raise RuntimeError("turn recovery fixture turn drift")
            if set(turn) != turn_fields:
                raise RuntimeError("turn recovery fixture turn schema drift")
            client_turn_id = _canonical_uuid(turn.get("client_turn_id"))
            stored_session_id = turn.get("stored_session_id")
            status = turn.get("status")
            last_seq = turn.get("last_seq")
            first_retained_seq = turn.get("first_retained_seq")
            events = turn.get("events")
            execution_count = turn.get("execution_count")
            if (
                turn.get("turn_id") != turn_id
                or stored_session_id not in stored_ids
                or turn.get("profile") != self._server_profile
                or client_turn_id is None
                or status
                not in {
                    "accepted",
                    "running",
                    "waiting_input",
                    "completed",
                    "failed",
                    "interrupted",
                }
                or type(last_seq) is not int
                or last_seq < 0
                or type(first_retained_seq) is not int
                or first_retained_seq <= 0
                or first_retained_seq > last_seq + 1
                or not isinstance(events, list)
                or type(execution_count) is not int
                or execution_count != 1
            ):
                raise RuntimeError("turn recovery fixture turn is invalid")
            for digest_name in ("request_digest", "attachment_manifest_digest"):
                digest = turn.get(digest_name)
                if (
                    not isinstance(digest, str)
                    or len(digest) != 64
                    or any(character not in "0123456789abcdef" for character in digest)
                ):
                    raise RuntimeError("turn recovery fixture digest is invalid")
            for scalar_name in ("message_id", "assistant_text"):
                if not isinstance(turn.get(scalar_name), str):
                    raise RuntimeError("turn recovery fixture message drift")
            if type(turn.get("final_message_ref")) is not int:
                raise RuntimeError("turn recovery fixture message ref drift")
            previous_seq = first_retained_seq - 1
            for event in events:
                if (
                    not isinstance(event, dict)
                    or set(event) != {"turn_id", "seq", "message_id", "type", "payload"}
                    or event.get("turn_id") != turn_id
                    or event.get("message_id") != turn.get("message_id")
                    or type(event.get("seq")) is not int
                    or event["seq"] != previous_seq + 1
                    or not isinstance(event.get("type"), str)
                    or not isinstance(event.get("payload"), dict)
                ):
                    raise RuntimeError("turn recovery fixture event drift")
                previous_seq = event["seq"]
            if events and previous_seq != last_seq:
                raise RuntimeError("turn recovery fixture cursor drift")
            client_key = f"{stored_session_id}\u001f{client_turn_id}"
            if client_key in expected_turn_by_client:
                raise RuntimeError("turn recovery fixture client turn duplicate")
            expected_turn_by_client[client_key] = turn_id
            execution_total += execution_count

        if turn_by_client != expected_turn_by_client:
            raise RuntimeError("turn recovery fixture client index drift")
        if decoded["execution_count"] != execution_total:
            raise RuntimeError("turn recovery fixture execution counter drift")
        if decoded["binding_counter"] < len(bindings) or decoded["turn_counter"] < len(turns):
            raise RuntimeError("turn recovery fixture allocation counter drift")

    def _save(self) -> None:
        if self._ledger_path is None:
            return
        self._ledger_path.parent.mkdir(parents=True, exist_ok=True)
        temporary = self._ledger_path.with_suffix(self._ledger_path.suffix + ".tmp")
        temporary.write_text(_compact_json(self._durable), encoding="utf-8")
        os.replace(temporary, self._ledger_path)

    async def _session_open(
        self,
        ws: Any,
        request_id: object,
        params: dict[str, object],
        connection_id: str,
    ) -> None:
        if "session_id" in params or "stored_session_id" in params:
            await ws.send_str(
                _rpc_error(
                    request_id,
                    "client session target is forbidden",
                    4401,
                    "client_session_authority_forbidden",
                )
            )
            return
        mobile_session_id = _canonical_uuid(params.get("mobile_session_id"))
        if mobile_session_id is None:
            await ws.send_str(
                _rpc_error(
                    request_id,
                    "mobile_session_id must be a canonical UUID",
                    4401,
                    "invalid_mobile_session_id",
                )
            )
            return
        profile_selector = params.get("profile")
        if profile_selector is not None and profile_selector != self._server_profile:
            await ws.send_str(
                _rpc_error(
                    request_id,
                    "server profile scope is unavailable",
                    4406,
                    "profile_unavailable",
                )
            )
            return
        profile = self._server_profile
        binding_key = f"{profile}\u001f{mobile_session_id}"
        with self._lock:
            binding = self._durable["bindings"].get(binding_key)
            if binding is None:
                self._durable["binding_counter"] += 1
                binding = {
                    "profile": profile,
                    "mobile_session_id": mobile_session_id,
                    "stored_session_id": (
                        f"stored-recovery-{self._durable['binding_counter']}"
                    ),
                    "binding_version": 0,
                }
                self._durable["bindings"][binding_key] = binding
            binding["binding_version"] = int(binding["binding_version"]) + 1
            self._runtime_counter += 1
            runtime_session_id = (
                f"runtime-recovery-{self._durable['process_generation']}-"
                f"{self._runtime_counter}"
            )
            runtime = {
                **binding,
                "runtime_session_id": runtime_session_id,
                "binding_key": binding_key,
            }
            self._runtime_bindings[runtime_session_id] = runtime
            self._connection_runtime[connection_id] = runtime_session_id
            self._save()
        await ws.send_str(
            _rpc_result(
                request_id,
                {
                    "runtime_session_id": runtime_session_id,
                    "stored_session_id": binding["stored_session_id"],
                    "mobile_session_id": mobile_session_id,
                    "binding_version": binding["binding_version"],
                    "turn_recovery": True,
                    "automatic_resubmit": False,
                    "capabilities": self.ready_frame()["params"]["payload"][
                        "capabilities"
                    ],
                },
            )
        )

    def _scoped_runtime(
        self, params: dict[str, object], connection_id: str
    ) -> dict[str, object] | None:
        runtime_id = params.get("session_id")
        if not isinstance(runtime_id, str):
            return None
        if self._connection_runtime.get(connection_id) != runtime_id:
            return None
        return self._runtime_bindings.get(runtime_id)

    async def _prompt_submit(
        self,
        ws: Any,
        request_id: object,
        params: dict[str, object],
        connection_id: str,
    ) -> None:
        prompt_fields = set(params)
        if (
            params.get("version") != 2
            or not _PROMPT_REQUIRED_FIELDS.issubset(prompt_fields)
            or not prompt_fields.issubset(_PROMPT_ALLOWED_FIELDS)
        ):
            await ws.send_str(
                _rpc_error(
                    request_id,
                    "prompt.submit@2 has a closed schema",
                    4401,
                    "closed_prompt_schema",
                )
            )
            return
        runtime = self._scoped_runtime(params, connection_id)
        client_turn_id = _canonical_uuid(params.get("client_turn_id"))
        text = params.get("text")
        attachments = _canonical_attachments(params.get("attachments", []))
        if (
            runtime is None
            or client_turn_id is None
            or not isinstance(text, str)
            or len(text.encode("utf-8")) > MAX_PROMPT_BYTES
            or attachments is None
        ):
            await ws.send_str(
                _rpc_error(request_id, "invalid v2 turn", 4401, "invalid_turn_request")
            )
            return
        request_digest = _request_digest(text, attachments)
        stored_session_id = str(runtime["stored_session_id"])
        client_key = f"{stored_session_id}\u001f{client_turn_id}"
        with self._lock:
            self._durable["submit_attempt_count"] += 1
            existing_id = self._durable["turn_by_client"].get(client_key)
            if existing_id is not None:
                turn = self._durable["turns"][existing_id]
                if turn["request_digest"] != request_digest:
                    self._save()
                    await ws.send_str(
                        _rpc_error(
                            request_id,
                            "client_turn_id conflicts with durable intent",
                            4409,
                            "client_turn_conflict",
                        )
                    )
                    return
                self._save()
                await ws.send_str(_rpc_result(request_id, self._ack(turn, False)))
                return

            self._durable["turn_counter"] += 1
            self._durable["execution_count"] += 1
            counter = int(self._durable["turn_counter"])
            turn_id = f"turn-recovery-{counter}"
            turn: dict[str, Any] = {
                "turn_id": turn_id,
                "stored_session_id": stored_session_id,
                "profile": runtime["profile"],
                "client_turn_id": client_turn_id,
                "request_digest": request_digest,
                "attachment_manifest_digest": _attachment_digest(attachments),
                "status": "accepted",
                "last_seq": 0,
                "first_retained_seq": 1,
                "events": [],
                "message_id": f"message-recovery-{counter}",
                "assistant_text": "",
                "final_message_ref": counter,
                "execution_count": 1,
            }
            self._durable["turns"][turn_id] = turn
            self._durable["turn_by_client"][client_key] = turn_id
            self._append_event(turn, "turn.status", {"status": "accepted"})
            self._save()

        fault = self._next_fault.pop(connection_id, "")
        self._subscribe(turn_id, ws)
        if fault == FAULT_AFTER_COMMIT_BEFORE_ACK:
            self._finish_turn(turn, emit=False)
            await ws.close(code=1001, message=b"fixture committed before ack")
            return

        await ws.send_str(_rpc_result(request_id, self._ack(turn, True)))
        if fault == FAULT_AFTER_ACK_BEFORE_FIRST_DELTA:
            self._finish_turn(turn, emit=False)
            await ws.close(code=1001, message=b"fixture ack before delta")
            return
        await self._finish_turn_async(
            ws,
            turn,
            fault,
            str(runtime["runtime_session_id"]),
        )

    @staticmethod
    def _ack(turn: dict[str, Any], created: bool) -> dict[str, object]:
        return {
            "accepted": True,
            "client_turn_id": turn["client_turn_id"],
            "turn_id": turn["turn_id"],
            "status": turn["status"],
            "last_seq": turn["last_seq"],
            "created": created,
            "automatic_resubmit": False,
        }

    def _append_event(
        self,
        turn: dict[str, Any],
        event_type: str,
        payload: dict[str, object],
    ) -> dict[str, object]:
        turn["last_seq"] += 1
        event: dict[str, object] = {
            "turn_id": turn["turn_id"],
            "seq": turn["last_seq"],
            "message_id": turn["message_id"],
            "type": event_type,
            "payload": payload,
        }
        turn["events"].append(event)
        return event

    def _finish_turn(self, turn: dict[str, Any], *, emit: bool) -> None:
        del emit
        if turn["status"] in TERMINAL_STATUSES:
            return
        self._append_event(turn, "turn.status", {"status": "running"})
        turn["status"] = "running"
        self._append_event(turn, "message.start", {})
        for piece in ("Durable ", "recovery ", "completed."):
            self._append_event(turn, "message.delta", {"text": piece})
        turn["assistant_text"] = "Durable recovery completed."
        self._append_event(
            turn,
            "message.complete",
            {"text": turn["assistant_text"], "status": "completed"},
        )
        turn["status"] = "completed"
        self._save()

    async def _finish_turn_async(
        self,
        ws: Any,
        turn: dict[str, Any],
        fault: str,
        runtime_session_id: str,
    ) -> None:
        if turn["status"] in TERMINAL_STATUSES:
            return
        event_specs = [
            ("turn.status", {"status": "running"}),
            ("message.start", {}),
            ("message.delta", {"text": "Durable "}),
            ("message.delta", {"text": "recovery "}),
            ("message.delta", {"text": "completed."}),
            (
                "message.complete",
                {"text": "Durable recovery completed.", "status": "completed"},
            ),
        ]
        delta_count = 0
        connected = True
        for event_type, event_payload in event_specs:
            event = self._append_event(turn, event_type, event_payload)
            if event_type == "turn.status":
                turn["status"] = str(event_payload["status"])
            if event_type == "message.complete":
                turn["assistant_text"] = str(event_payload["text"])
                turn["status"] = str(event_payload["status"])
            self._save()
            if connected:
                await self._emit(ws, turn, event, runtime_session_id)
            if event_type == "message.delta":
                delta_count += 1
                if fault == FAULT_MIDSTREAM and delta_count == 2:
                    connected = False
                    await ws.close(code=1001, message=b"fixture midstream disconnect")
            if event_type == "message.complete" and fault == FAULT_AFTER_COMPLETION:
                connected = False
                await ws.close(code=1001, message=b"fixture completion disconnect")

    async def _emit(
        self,
        ws: Any,
        turn: dict[str, Any],
        event: dict[str, object],
        runtime_session_id: str,
    ) -> None:
        await ws.send_str(
            json.dumps(
                {
                    "jsonrpc": "2.0",
                    "method": "event",
                    "params": {
                        "session_id": runtime_session_id,
                        **event,
                    },
                },
                ensure_ascii=False,
            )
        )

    def _subscribe(self, turn_id: str, ws: Any) -> None:
        self._subscribers.setdefault(turn_id, set()).add(ws)

    def _find_turn(
        self, params: dict[str, object], runtime: dict[str, object]
    ) -> dict[str, Any] | None:
        turn_id = params.get("turn_id")
        if isinstance(turn_id, str) and turn_id:
            turn = self._durable["turns"].get(turn_id)
        else:
            client_turn_id = _canonical_uuid(params.get("client_turn_id"))
            if client_turn_id is None:
                return None
            client_key = f"{runtime['stored_session_id']}\u001f{client_turn_id}"
            resolved = self._durable["turn_by_client"].get(client_key)
            turn = self._durable["turns"].get(resolved) if resolved else None
        if turn is None:
            return None
        if (
            turn["stored_session_id"] != runtime["stored_session_id"]
            or turn["profile"] != runtime["profile"]
        ):
            return None
        return turn

    async def _reconcile(
        self,
        ws: Any,
        request_id: object,
        params: dict[str, object],
        connection_id: str,
    ) -> None:
        runtime = self._scoped_runtime(params, connection_id)
        turn = self._find_turn(params, runtime) if runtime is not None else None
        after_seq = params.get("after_seq", 0)
        if runtime is None or turn is None:
            await ws.send_str(
                _rpc_error(request_id, "turn not found", 4404, "turn_unknown")
            )
            return
        if isinstance(after_seq, bool) or not isinstance(after_seq, int) or after_seq < 0:
            await ws.send_str(
                _rpc_error(request_id, "invalid after_seq", 4401, "invalid_after_seq")
            )
            return
        earliest_seq = int(turn["first_retained_seq"])
        if after_seq < earliest_seq - 1:
            if turn["status"] not in TERMINAL_STATUSES or not turn["assistant_text"]:
                await ws.send_str(
                    _rpc_error(
                        request_id,
                        "turn replay was pruned",
                        4410,
                        "turn_replay_pruned",
                    )
                )
                return
            result = {
                "mode": "snapshot",
                "snapshot": self._snapshot(turn),
                "earliest_seq": earliest_seq,
                "last_seq": turn["last_seq"],
                "has_more": False,
                "next_after_seq": turn["last_seq"],
                "automatic_resubmit": False,
            }
            await ws.send_str(_rpc_result(request_id, result))
            return
        events = [
            dict(event)
            for event in turn["events"]
            if int(event["seq"]) > after_seq
        ][:_FIXTURE_RECONCILE_PAGE_EVENTS]
        next_after_seq = int(events[-1]["seq"]) if events else after_seq
        result = {
            "mode": "events",
            "turn_id": turn["turn_id"],
            "status": turn["status"],
            "earliest_seq": earliest_seq,
            "last_seq": turn["last_seq"],
            "events": events,
            "has_more": next_after_seq < int(turn["last_seq"]),
            "next_after_seq": next_after_seq,
            "automatic_resubmit": False,
        }
        self._subscribe(str(turn["turn_id"]), ws)
        await ws.send_str(_rpc_result(request_id, result))

    @staticmethod
    def _snapshot(turn: dict[str, Any]) -> dict[str, object]:
        return {
            "turn_id": turn["turn_id"],
            "client_turn_id": turn["client_turn_id"],
            "status": turn["status"],
            "last_seq": turn["last_seq"],
            "assistant": {
                "message_id": turn["message_id"],
                "text": turn["assistant_text"],
                "complete": True,
            },
            "attachment_manifest_digest": turn["attachment_manifest_digest"],
            "final_message_ref": turn["final_message_ref"],
        }

    async def _interrupt(
        self,
        ws: Any,
        request_id: object,
        params: dict[str, object],
        connection_id: str,
    ) -> None:
        runtime = self._scoped_runtime(params, connection_id)
        turn = self._find_turn(params, runtime) if runtime is not None else None
        if turn is None:
            await ws.send_str(
                _rpc_error(request_id, "turn not found", 4404, "turn_unknown")
            )
            return
        if turn["status"] not in TERMINAL_STATUSES:
            turn["status"] = "interrupted"
            self._append_event(turn, "turn.status", {"status": "interrupted"})
            self._save()
        await ws.send_str(
            _rpc_result(
                request_id,
                {
                    "turn_id": turn["turn_id"],
                    "status": turn["status"],
                    "last_seq": turn["last_seq"],
                    "automatic_resubmit": False,
                },
            )
        )

    async def _configure_fault(
        self,
        ws: Any,
        request_id: object,
        params: dict[str, object],
        connection_id: str,
    ) -> None:
        runtime = self._scoped_runtime(params, connection_id)
        fault = params.get("fault")
        if runtime is None or fault not in FAULTS:
            await ws.send_str(
                _rpc_error(request_id, "invalid fixture fault", 4490, "fixture_only")
            )
            return
        self._next_fault[connection_id] = str(fault)
        await ws.send_str(_rpc_result(request_id, {"configured": True, "fault": fault}))

    async def _prune(
        self,
        ws: Any,
        request_id: object,
        params: dict[str, object],
        connection_id: str,
    ) -> None:
        runtime = self._scoped_runtime(params, connection_id)
        turn = self._find_turn(params, runtime) if runtime is not None else None
        if turn is None:
            await ws.send_str(
                _rpc_error(request_id, "turn not found", 4404, "turn_unknown")
            )
            return
        turn["first_retained_seq"] = int(turn["last_seq"]) + 1
        turn["events"] = []
        self._save()
        await ws.send_str(
            _rpc_result(
                request_id,
                {
                    "turn_id": turn["turn_id"],
                    "earliest_seq": turn["first_retained_seq"],
                },
            )
        )

    async def _restart(self, ws: Any, request_id: object) -> None:
        self._runtime_bindings.clear()
        self._connection_runtime.clear()
        self._next_fault.clear()
        await ws.send_str(
            _rpc_result(
                request_id,
                {"restarted": True, "durable_turns": len(self._durable["turns"])},
            )
        )
