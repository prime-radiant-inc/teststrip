# Evaluation Providers

## Decision

Teststrip treats photo evaluation as a provider-backed worker capability. Local providers are enabled by default. Local HTTP or cloud-shaped model providers are opt-in configuration, not a visible default workflow.

## Current Behavior

- `local-image-metrics` reads cached previews and emits exposure and color-palette signals.
- `apple-vision` reads cached previews and emits face-quality, OCR, and object-label signals through Apple's Vision APIs.
- `local-http-model` is registered only when the worker receives `--local-http-model-endpoint` and `--local-http-model`.
- App launch can pass those worker flags from `TESTSTRIP_LOCAL_HTTP_MODEL_ENDPOINT`, `TESTSTRIP_LOCAL_HTTP_MODEL`, and `TESTSTRIP_LOCAL_HTTP_MODEL_TIMEOUT`.
- HTTP model requests use an OpenAI-compatible chat-completions shape and embed the cached preview as an `image_url` data URL. Providers must not depend on a local filesystem path being visible to the model server.
- All imported model output is stored as typed `EvaluationSignal` rows with provider, model, version, and settings provenance.

## Next Work

- Add cancellation-aware async provider execution so slow model calls can be interrupted without killing unrelated worker state.
- Add retry/backoff policy for configured HTTP model providers.
- Add a hidden or developer-only smoke command that exercises a real LM Studio or Ollama endpoint against one selected preview.
- Promote provider selection into UI only after real model behavior is good enough to be useful.
