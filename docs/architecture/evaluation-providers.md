# Evaluation Providers

## Decision

Teststrip treats photo evaluation as a provider-backed worker capability. Local providers are enabled by default. Local HTTP or cloud-shaped model providers are opt-in configuration, not a visible default workflow.

## Current Behavior

- `local-image-metrics` reads cached previews and emits exposure, color-palette, focus, motion-blur, framing, and aesthetics signals. Framing and aesthetics are conservative preview heuristics with local provenance, not a claim of model-grade taste.
- `apple-vision` reads cached previews and emits face-quality, OCR, and object-label signals through Apple's Vision APIs.
- `local-http-model` is registered only when the worker receives `--local-http-model-endpoint` and `--local-http-model`.
- App launch can pass those worker flags from `TESTSTRIP_LOCAL_HTTP_MODEL_ENDPOINT`, `TESTSTRIP_LOCAL_HTTP_MODEL`, and `TESTSTRIP_LOCAL_HTTP_MODEL_TIMEOUT`.
- HTTP model requests use an OpenAI-compatible chat-completions shape and embed the cached preview as an `image_url` data URL. Providers must not depend on a local filesystem path being visible to the model server.
- HTTP model responses may contain raw JSON or a fenced/prose-wrapped JSON object; the provider extracts the returned JSON object before decoding typed signals.
- HTTP model requests retry transient transport failures and retryable response statuses, including `408`, `429`, and `5xx`, up to three attempts before surfacing the last failure.
- All imported model output is stored as typed `EvaluationSignal` rows with provider, model, version, and settings provenance.
- `TeststripBench local-http-smoke <endpoint> <model> <image> [timeout]` exercises an OpenAI-compatible local model endpoint such as LM Studio or Ollama against one preview image and reports returned signal kinds.

## Next Work

- Add cancellation-aware async provider execution so slow model calls can be interrupted without killing unrelated worker state.
- Add configurable backoff and jitter for configured HTTP model providers.
- Promote provider selection into UI only after real model behavior is good enough to be useful.
