#!/bin/bash
#SBATCH --job-name=swe-bottom350
#SBATCH --partition=GPU-shared
#SBATCH --account=cis240137p
#SBATCH --gpus=h100-80:1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=64G
#SBATCH --time=08:00:00
#SBATCH --output=logs/swe-bottom350_%j.out
#SBATCH --error=logs/swe-bottom350_%j.err

set -euo pipefail

# ── Paths & env ──────────────────────────────────────────────────────
WORKDIR=/ocean/projects/cis250260p/gzhang15/benchmarks
CACHE=/ocean/projects/cis250260p/gzhang15/cache
HF_MODEL="synthetic-code-training/qwen25-coder-7b-func-localize-claude-bottom350explore-rubric2-350i-5e-0-00005lr-bs16-bf16"

export HF_TOKEN="${HF_TOKEN:?Set HF_TOKEN in your environment}"
export HF_HOME="${CACHE}/hf"
export APPTAINER_CACHEDIR="${CACHE}/apptainer"
export APPTAINER_TMPDIR="${CACHE}/tmp"
export IMAGE_TAG_PREFIX="f848121-35d813f"
export OPENHANDS_EVAL_AGENT_SERVER_IMAGE="ghcr.io/gaokaizhang/eval-agent-server"

# ── Modules & conda ─────────────────────────────────────────────────
module load cuda/12.6.1

# Add NVIDIA library paths for PyTorch/vLLM
NVIDIA_LIBS="/jet/home/gzhang15/.local/lib/python3.12/site-packages/nvidia"
export LD_LIBRARY_PATH="$NVIDIA_LIBS/cusparselt/lib:$NVIDIA_LIBS/cufile/lib:$NVIDIA_LIBS/nvshmem/lib:$LD_LIBRARY_PATH"

source /ocean/projects/cis250260p/gzhang15/miniconda3/etc/profile.d/conda.sh
conda activate openhands

cd "${WORKDIR}"

# ── Start vLLM server ───────────────────────────────────────────────
echo "[$(date)] Starting vLLM server for ${HF_MODEL} ..."
python -m vllm.entrypoints.openai.api_server \
    --model "${HF_MODEL}" \
    --host 0.0.0.0 \
    --port 8000 \
    --dtype bfloat16 \
    --max-model-len 8192 \
    --gpu-memory-utilization 0.90 \
    --trust-remote-code &
VLLM_PID=$!

# Wait for vLLM to be ready (up to 10 min)
echo "[$(date)] Waiting for vLLM to be ready ..."
for i in $(seq 1 120); do
    if curl -s http://localhost:8000/health > /dev/null 2>&1; then
        echo "[$(date)] vLLM is ready after ~${i}x5s"
        break
    fi
    if ! kill -0 $VLLM_PID 2>/dev/null; then
        echo "[$(date)] vLLM process died!" >&2
        exit 1
    fi
    sleep 5
done

if ! curl -s http://localhost:8000/health > /dev/null 2>&1; then
    echo "[$(date)] vLLM failed to start within timeout" >&2
    kill $VLLM_PID 2>/dev/null || true
    exit 1
fi

# ── Runtime configuration — use remote docker ─────────────────────
export RUNTIME_API_KEY="${RUNTIME_API_KEY:?Set RUNTIME_API_KEY in your environment}"
export RUNTIME_API_URL="https://runtime.eval.all-hands.dev"

# ── Run swebench-infer ──────────────────────────────────────────────
echo "[$(date)] Starting swebench-infer ..."
uv run swebench-infer .llm_config/qwen25-7b-bottom350.json \
    --select selected_instances.txt \
    --workspace remote \
    --num-workers 4 \
    --max-iterations 100
EXIT_CODE=$?

# ── Cleanup ─────────────────────────────────────────────────────────
echo "[$(date)] Inference finished with exit code ${EXIT_CODE}"
kill $VLLM_PID 2>/dev/null || true
wait $VLLM_PID 2>/dev/null || true
exit $EXIT_CODE
