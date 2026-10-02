# Synthetic Desktop Gateway

This local-only fixture exercises the Dashboard and Desktop Gateway contracts
used by the Android application. All sessions, credentials, prompts, files, and
responses are synthetic.

## Run

```bash
python -m pip install -r requirements.txt
python fake_gateway.py --host 127.0.0.1 --port 18642 --api-key test-key
```

In another terminal:

```bash
python test_fake_gateway.py
```

## Deterministic disconnect scenarios

The fixture accepts the test-only `prompt.submit` parameter
`fixture_disconnect_scenario` with one of these exact values:

- `before_ack` closes the socket before the JSON-RPC result;
- `after_ack_before_first_delta` sends the accepted result, then closes before
  the first `message.delta`;
- `mid_stream_after_2_deltas` sends the accepted result and exactly two
  `message.delta` events, then closes.

These paths do not use timers. They never emit `turn.end` and never append a
user or assistant completion to session history. They model transport loss
only: they do not claim background continuation, recovery, replay,
idempotency, or server durability.

Loopback clients can inspect a resettable, prompt-free diagnostic ledger:

```text
GET  /test/disconnect-ledger
POST /test/disconnect-ledger/reset
```

The `hermes.fake_gateway.disconnect_ledger.v1` response contains one record per
scenario with `prompt_submit_count`, `disconnect_point`, `ack_seen`,
`delta_count`, `turn_end_count`, and `resubmit_count`. It never contains prompt
text, credentials, attachment bytes, or response content. Both diagnostic
routes reject non-loopback callers.

The fixture binds to loopback by default. Do not expose it as a real gateway or
reuse its synthetic credentials for any other service.
