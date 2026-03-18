#!/bin/sh
set -e

MODEL_DIR=/models
MODEL_FILE="${MODEL_DIR}/${HF_FILE}"

if [ ! -f "$MODEL_FILE" ]; then
    echo "Downloading ${HF_FILE} from ${HF_REPO}..."
    mkdir -p "$MODEL_DIR"
    curl -fSL \
        "https://huggingface.co/${HF_REPO}/resolve/main/${HF_FILE}" \
        -o "$MODEL_FILE"
    echo "Download complete."
fi

exec llama-server \
    --model "$MODEL_FILE" \
    --host "${HOST}" \
    --port "${PORT}" \
    --ctx-size "${CTX_SIZE}" \
    --n-gpu-layers "${N_GPU_LAYERS}"
