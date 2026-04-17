# Remote Docker Setup for SWE-bench Evaluation

Guide for building, pushing, and using remote Docker images with `swebench-infer`.

## Overview

Remote workspace evaluation uses pre-built agent-server images hosted on a container registry (GHCR). The runtime API provisions containers on demand, so images must exist and be publicly accessible before inference starts.

Image tags follow the format:
```
{REGISTRY}:{IMAGE_TAG_PREFIX}-{INSTANCE_TAG}-{BUILD_TARGET}
```
Example:
```
ghcr.io/gaokaizhang/eval-agent-server:f848121-35d813f-sweb.eval.x86_64.django_1776_django-11999-source-minimal
```

## 1. Build and Push Images

### Option A: CI (upstream only)

On the upstream `OpenHands/benchmarks` repo, add a label to a PR:
- `build-swebench-50` / `build-swebench-200` / `build-swebench` (all)

Images are pushed to `ghcr.io/openhands/eval-agent-server`.

### Option B: Manual Build

```bash
uv run python -m benchmarks.swebench.build_images \
  --dataset princeton-nlp/SWE-bench_Verified \
  --split test \
  --image ghcr.io/<YOUR_GHCR_USER>/eval-agent-server \
  --target source-minimal \
  --push \
  --max-workers 32
```

The build has three phases:
1. **Builder image** — shared SDK + dependencies (`eval-builder:{SDK_SHA}`)
2. **Base images** — per-instance base from official SWE-bench images (`eval-base:{hash}-{instance_tag}`)
3. **Agent images** — final assembled images (`eval-agent-server:{prefix}-{instance_tag}-{target}`)

The `{prefix}` (aka `IMAGE_TAG_PREFIX`) is `{SDK_SHORT_SHA}-{dockerfile_content_hash}` by default, derived from the `vendor/software-agent-sdk` submodule SHA and the SDK Dockerfile hash.

### Making Images Public

GHCR images default to private. To make them public:
1. Go to `https://github.com/users/<YOU>/packages/container/eval-agent-server/settings`
2. Under "Danger Zone", change visibility to **Public**

## 2. Environment Variables

### Required for Remote Inference

| Variable | Description |
|---|---|
| `RUNTIME_API_KEY` | API key for the remote runtime service (e.g., `ah-...`) |
| `RUNTIME_API_URL` | Runtime API endpoint (default: `https://runtime.eval.all-hands.dev`) |

### Image Selection

| Variable | Default | Description |
|---|---|---|
| `IMAGE_TAG_PREFIX` | `{SDK_SHA}-{dockerfile_hash}` | Override the auto-detected image tag prefix |
| `OPENHANDS_EVAL_AGENT_SERVER_IMAGE` | `ghcr.io/openhands/eval-agent-server` | Override the image registry/repo |

If you built images to a custom registry (e.g., `ghcr.io/gaokaizhang/eval-agent-server`) or with a specific SDK revision, set both variables so `swebench-infer` resolves the correct image tags.

### Example

```bash
export RUNTIME_API_KEY="ah-..."
export RUNTIME_API_URL="https://runtime.eval.all-hands.dev"
export IMAGE_TAG_PREFIX="f848121-35d813f"
export OPENHANDS_EVAL_AGENT_SERVER_IMAGE="ghcr.io/gaokaizhang/eval-agent-server"
```

## 3. Run Inference

```bash
uv run swebench-infer .llm_config/my_model.json \
    --workspace remote \
    --select selected_instances.txt \
    --num-workers 4 \
    --max-iterations 100
```

Key flags:
- `--workspace remote` — use the remote runtime (not `docker` or `apptainer`)
- `--select <file>` — text file with one instance ID per line
- `--num-workers N` — parallel instances
- `--max-iterations N` — max agent steps per instance

## 4. Troubleshooting

**"Agent server image ... does not exist in container registry"**
- The image hasn't been built/pushed, or the tag prefix doesn't match.
- Verify: `uv run python -m benchmarks.utils.image_utils <full_image_ref>`
- Check that `IMAGE_TAG_PREFIX` and `OPENHANDS_EVAL_AGENT_SERVER_IMAGE` match what was used during the build.

**"RUNTIME_API_KEY environment variable is not set"**
- Export `RUNTIME_API_KEY` before running. The code reads `RUNTIME_API_KEY`, not `ALLHANDS_API_KEY`.

**"libcusparseLt.so.0: cannot open shared object file"**
- Add NVIDIA pip package libs to `LD_LIBRARY_PATH` before starting vLLM:
  ```bash
  NVIDIA_LIBS="<site-packages>/nvidia"
  export LD_LIBRARY_PATH="$NVIDIA_LIBS/cusparselt/lib:$NVIDIA_LIBS/cufile/lib:$NVIDIA_LIBS/nvshmem/lib:$LD_LIBRARY_PATH"
  ```
- Or install: `pip install nvidia-cusparselt-cu12`
