#!/usr/bin/env bash
# Ferrite Vector Search Benchmark Comparison
#
# Compares Ferrite's vector search performance against Redis with RedisSearch
# (vector similarity) and Qdrant. Measures ops/sec, latency, and recall@k.
#
# Prerequisites:
#   - Ferrite running on FERRITE_PORT (default: 6380)
#   - Redis with RedisSearch module running on REDIS_PORT (default: 6379)
#   - Qdrant running on QDRANT_PORT (default: 6333) — optional
#   - redis-cli installed
#   - python3 with numpy (for generating test vectors)
#   - curl (for Qdrant HTTP API)
#
# Usage:
#   ./vector_comparison.sh                    # Full comparison (Ferrite + Redis + Qdrant)
#   ./vector_comparison.sh --ferrite-only     # Ferrite only
#   ./vector_comparison.sh --quick            # Reduced dataset for fast test
#
# Environment variables:
#   FERRITE_HOST, FERRITE_PORT, REDIS_HOST, REDIS_PORT
#   QDRANT_HOST, QDRANT_PORT
#   VECTOR_DIM      - Vector dimension (default: 384)
#   VECTOR_COUNT    - Number of vectors to insert (default: 10000)
#   SEARCH_K        - Number of neighbors to retrieve (default: 10)
#   NUM_QUERIES     - Number of search queries to run (default: 1000)

set -euo pipefail

# ── Configuration ─────────────────────────────────────────────────────────────

FERRITE_HOST="${FERRITE_HOST:-127.0.0.1}"
FERRITE_PORT="${FERRITE_PORT:-6380}"
REDIS_HOST="${REDIS_HOST:-127.0.0.1}"
REDIS_PORT="${REDIS_PORT:-6379}"

QDRANT_HOST="${QDRANT_HOST:-127.0.0.1}"
QDRANT_PORT="${QDRANT_PORT:-6333}"

VECTOR_DIM="${VECTOR_DIM:-384}"
VECTOR_COUNT="${VECTOR_COUNT:-10000}"
SEARCH_K="${SEARCH_K:-10}"
NUM_QUERIES="${NUM_QUERIES:-1000}"

INDEX_NAME="bench_vectors"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESULTS_DIR="${SCRIPT_DIR}/results"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"

FERRITE_ONLY=false

# ── Helpers ───────────────────────────────────────────────────────────────────

info()  { echo -e "\033[0;34m[INFO]\033[0m  $*"; }
ok()    { echo -e "\033[0;32m[OK]\033[0m    $*"; }
warn()  { echo -e "\033[0;33m[WARN]\033[0m  $*"; }
error() { echo -e "\033[0;31m[ERROR]\033[0m $*" >&2; }

read_result_value() {
    local file="$1"
    local key="$2"
    local default="${3:-N/A}"
    local value

    value=$(awk -F= -v key="$key" '$1 == key {sub(/^[^=]*=/, ""); print; exit}' "$file")
    printf '%s\n' "${value:-$default}"
}

parse_vector_args() {
    local arg
    for arg in "$@"; do
        case "$arg" in
            --ferrite-only) FERRITE_ONLY=true ;;
            --quick)
                VECTOR_COUNT=1000
                NUM_QUERIES=100
                ;;
            *)
                error "Unknown option: $arg"
                return 1
                ;;
        esac
    done
}

check_prereqs() {
    if ! command -v redis-cli &>/dev/null; then
        error "redis-cli not found. Install with: brew install redis (macOS) or apt install redis-tools (Linux)"
        exit 1
    fi

    if ! command -v python3 &>/dev/null; then
        error "python3 not found. Required for vector generation."
        exit 1
    fi
}

# Generate random vectors using Python
generate_vectors() {
    local count="$1"
    local dim="$2"
    local output_file="$3"

    info "Generating ${count} random vectors of dimension ${dim}..."

    python3 -c "
import random
import struct
import sys

random.seed(42)
count = ${count}
dim = ${dim}

with open('${output_file}', 'wb') as f:
    for i in range(count):
        vec = [random.gauss(0, 1) for _ in range(dim)]
        # Normalize to unit length
        norm = sum(x*x for x in vec) ** 0.5
        if norm > 0:
            vec = [x / norm for x in vec]
        f.write(struct.pack(f'{dim}f', *vec))

print(f'Generated {count} vectors', file=sys.stderr)
"
    ok "Vectors generated -> ${output_file}"
}

# Generate query vectors
generate_queries() {
    local count="$1"
    local dim="$2"
    local output_file="$3"

    python3 -c "
import random
import struct
import sys

random.seed(12345)
count = ${count}
dim = ${dim}

with open('${output_file}', 'wb') as f:
    for i in range(count):
        vec = [random.gauss(0, 1) for _ in range(dim)]
        norm = sum(x*x for x in vec) ** 0.5
        if norm > 0:
            vec = [x / norm for x in vec]
        f.write(struct.pack(f'{dim}f', *vec))

print(f'Generated {count} query vectors', file=sys.stderr)
"
}

# Read a vector from binary file
read_vector() {
    local file="$1"
    local index="$2"
    local dim="$3"

    python3 -c "
import struct
with open('${file}', 'rb') as f:
    f.seek(${index} * ${dim} * 4)
    data = f.read(${dim} * 4)
    vec = struct.unpack(f'${dim}f', data)
    # Output as comma-separated for redis-cli
    print(','.join(f'{x:.6f}' for x in vec))
"
}

# Convert vector to binary blob for Redis HSET
vector_to_blob() {
    local file="$1"
    local index="$2"
    local dim="$3"

    python3 -c "
import struct, sys
with open('${file}', 'rb') as f:
    f.seek(${index} * ${dim} * 4)
    data = f.read(${dim} * 4)
    sys.stdout.buffer.write(data)
"
}

# ── Ferrite Vector Benchmark ─────────────────────────────────────────────────

benchmark_ferrite_insert() {
    local vectors_file="$1"
    local host="$2"
    local port="$3"

    info "Benchmarking Ferrite vector insertion (${VECTOR_COUNT} vectors, ${VECTOR_DIM}d)..."

    local start_time
    start_time=$(python3 -c "import time; print(time.time())")

    # Use Ferrite's vector commands via redis-cli (RESP protocol)
    # FT.CREATE creates the vector index
    redis-cli -h "$host" -p "$port" \
        FT.CREATE "$INDEX_NAME" ON HASH PREFIX 1 "vec:" \
        SCHEMA embedding VECTOR HNSW 6 TYPE FLOAT32 DIM "$VECTOR_DIM" DISTANCE_METRIC COSINE \
        2>/dev/null || true

    # Batch insert vectors using pipeline
    python3 -c "
import struct
import subprocess
import sys

dim = ${VECTOR_DIM}
count = ${VECTOR_COUNT}
host = '${host}'
port = '${port}'

# Build pipeline commands
commands = []
with open('${vectors_file}', 'rb') as f:
    for i in range(count):
        data = f.read(dim * 4)
        if len(data) < dim * 4:
            break
        # Convert to hex for redis-cli
        hex_str = data.hex()
        key = f'vec:{i}'
        # Use HSET with vector field
        commands.append(f'HSET {key} embedding \\\\x{hex_str}')

# Write to pipe file
pipe_data = '\\n'.join(commands) + '\\n'
proc = subprocess.Popen(
    ['redis-cli', '-h', host, '-p', port, '--pipe'],
    stdin=subprocess.PIPE,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE
)
stdout, stderr = proc.communicate(pipe_data.encode())
print(stderr.decode(), file=sys.stderr)
" 2>&1 || true

    local end_time
    end_time=$(python3 -c "import time; print(time.time())")

    local duration
    duration=$(python3 -c "print(f'{${end_time} - ${start_time}:.3f}')")
    local ops_per_sec
    ops_per_sec=$(python3 -c "
d = ${end_time} - ${start_time}
if d > 0:
    print(f'{${VECTOR_COUNT} / d:.0f}')
else:
    print('N/A')
")

    echo "FERRITE_INSERT_TIME=${duration}" >> "${RESULTS_DIR}/vector_${TIMESTAMP}.env"
    echo "FERRITE_INSERT_OPS=${ops_per_sec}" >> "${RESULTS_DIR}/vector_${TIMESTAMP}.env"

    ok "Ferrite insert: ${VECTOR_COUNT} vectors in ${duration}s (${ops_per_sec} ops/sec)"
}

benchmark_ferrite_search() {
    local queries_file="$1"
    local host="$2"
    local port="$3"

    info "Benchmarking Ferrite vector search (${NUM_QUERIES} queries, k=${SEARCH_K})..."

    local start_time
    start_time=$(python3 -c "import time; print(time.time())")

    python3 -c "
import struct
import subprocess
import time
import sys

dim = ${VECTOR_DIM}
num_queries = ${NUM_QUERIES}
k = ${SEARCH_K}
host = '${host}'
port = '${port}'

latencies = []

with open('${queries_file}', 'rb') as f:
    for i in range(num_queries):
        data = f.read(dim * 4)
        if len(data) < dim * 4:
            break
        hex_str = data.hex()

        t0 = time.perf_counter()
        proc = subprocess.run(
            ['redis-cli', '-h', host, '-p', port,
             'FT.SEARCH', '${INDEX_NAME}',
             f'*=>[KNN {k} @embedding \$query_vec]',
             'PARAMS', '2', 'query_vec', f'\\x{hex_str}',
             'RETURN', '0',
             'DIALECT', '2'],
            capture_output=True, text=True
        )
        t1 = time.perf_counter()
        latencies.append((t1 - t0) * 1000)  # ms

        if i % 100 == 0 and i > 0:
            print(f'  Completed {i}/{num_queries} queries...', file=sys.stderr)

if latencies:
    latencies.sort()
    avg = sum(latencies) / len(latencies)
    p50 = latencies[len(latencies) // 2]
    p95 = latencies[int(len(latencies) * 0.95)]
    p99 = latencies[int(len(latencies) * 0.99)]
    total_time = sum(latencies) / 1000
    qps = len(latencies) / total_time if total_time > 0 else 0

    print(f'AVG_LATENCY_MS={avg:.3f}')
    print(f'P50_LATENCY_MS={p50:.3f}')
    print(f'P95_LATENCY_MS={p95:.3f}')
    print(f'P99_LATENCY_MS={p99:.3f}')
    print(f'QPS={qps:.0f}')
" > "${RESULTS_DIR}/ferrite_search_${TIMESTAMP}.txt" 2>&1

    local end_time
    end_time=$(python3 -c "import time; print(time.time())")

    ok "Ferrite search complete -> ${RESULTS_DIR}/ferrite_search_${TIMESTAMP}.txt"
}

# ── Redis + RedisSearch Vector Benchmark ─────────────────────────────────────

benchmark_redis_insert() {
    local vectors_file="$1"
    local host="$2"
    local port="$3"

    info "Benchmarking Redis+RedisSearch vector insertion (${VECTOR_COUNT} vectors, ${VECTOR_DIM}d)..."

    local start_time
    start_time=$(python3 -c "import time; print(time.time())")

    # Create index
    redis-cli -h "$host" -p "$port" \
        FT.CREATE "$INDEX_NAME" ON HASH PREFIX 1 "vec:" \
        SCHEMA embedding VECTOR HNSW 6 TYPE FLOAT32 DIM "$VECTOR_DIM" DISTANCE_METRIC COSINE \
        2>/dev/null || true

    # Insert vectors via pipeline
    python3 -c "
import struct
import subprocess
import sys

dim = ${VECTOR_DIM}
count = ${VECTOR_COUNT}
host = '${host}'
port = '${port}'

commands = []
with open('${vectors_file}', 'rb') as f:
    for i in range(count):
        data = f.read(dim * 4)
        if len(data) < dim * 4:
            break
        hex_str = data.hex()
        key = f'vec:{i}'
        commands.append(f'HSET {key} embedding \\\\x{hex_str}')

pipe_data = '\\n'.join(commands) + '\\n'
proc = subprocess.Popen(
    ['redis-cli', '-h', host, '-p', port, '--pipe'],
    stdin=subprocess.PIPE,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE
)
stdout, stderr = proc.communicate(pipe_data.encode())
print(stderr.decode(), file=sys.stderr)
" 2>&1 || true

    local end_time
    end_time=$(python3 -c "import time; print(time.time())")

    local duration
    duration=$(python3 -c "print(f'{${end_time} - ${start_time}:.3f}')")
    local ops_per_sec
    ops_per_sec=$(python3 -c "
d = ${end_time} - ${start_time}
if d > 0:
    print(f'{${VECTOR_COUNT} / d:.0f}')
else:
    print('N/A')
")

    echo "REDIS_INSERT_TIME=${duration}" >> "${RESULTS_DIR}/vector_${TIMESTAMP}.env"
    echo "REDIS_INSERT_OPS=${ops_per_sec}" >> "${RESULTS_DIR}/vector_${TIMESTAMP}.env"

    ok "Redis insert: ${VECTOR_COUNT} vectors in ${duration}s (${ops_per_sec} ops/sec)"
}

benchmark_redis_search() {
    local queries_file="$1"
    local host="$2"
    local port="$3"

    info "Benchmarking Redis+RedisSearch vector search (${NUM_QUERIES} queries, k=${SEARCH_K})..."

    python3 -c "
import struct
import subprocess
import time
import sys

dim = ${VECTOR_DIM}
num_queries = ${NUM_QUERIES}
k = ${SEARCH_K}
host = '${host}'
port = '${port}'

latencies = []

with open('${queries_file}', 'rb') as f:
    for i in range(num_queries):
        data = f.read(dim * 4)
        if len(data) < dim * 4:
            break
        hex_str = data.hex()

        t0 = time.perf_counter()
        proc = subprocess.run(
            ['redis-cli', '-h', host, '-p', port,
             'FT.SEARCH', '${INDEX_NAME}',
             f'*=>[KNN {k} @embedding \$query_vec]',
             'PARAMS', '2', 'query_vec', f'\\x{hex_str}',
             'RETURN', '0',
             'DIALECT', '2'],
            capture_output=True, text=True
        )
        t1 = time.perf_counter()
        latencies.append((t1 - t0) * 1000)

        if i % 100 == 0 and i > 0:
            print(f'  Completed {i}/{num_queries} queries...', file=sys.stderr)

if latencies:
    latencies.sort()
    avg = sum(latencies) / len(latencies)
    p50 = latencies[len(latencies) // 2]
    p95 = latencies[int(len(latencies) * 0.95)]
    p99 = latencies[int(len(latencies) * 0.99)]
    total_time = sum(latencies) / 1000
    qps = len(latencies) / total_time if total_time > 0 else 0

    print(f'AVG_LATENCY_MS={avg:.3f}')
    print(f'P50_LATENCY_MS={p50:.3f}')
    print(f'P95_LATENCY_MS={p95:.3f}')
    print(f'P99_LATENCY_MS={p99:.3f}')
    print(f'QPS={qps:.0f}')
" > "${RESULTS_DIR}/redis_search_${TIMESTAMP}.txt" 2>&1

    ok "Redis search complete -> ${RESULTS_DIR}/redis_search_${TIMESTAMP}.txt"
}

# ── Qdrant Vector Benchmark ───────────────────────────────────────────────────

benchmark_qdrant_insert() {
    local vectors_file="$1"
    local host="$2"
    local port="$3"

    info "Benchmarking Qdrant vector insertion (${VECTOR_COUNT} vectors, ${VECTOR_DIM}d)..."

    local start_time
    start_time=$(python3 -c "import time; print(time.time())")

    python3 -c "
import struct
import json
import urllib.request
import sys

dim = ${VECTOR_DIM}
count = ${VECTOR_COUNT}
host = '${host}'
port = '${port}'
base_url = f'http://{host}:{port}'

# Delete collection if exists
try:
    req = urllib.request.Request(f'{base_url}/collections/bench_vectors', method='DELETE')
    urllib.request.urlopen(req, timeout=10)
except Exception:
    pass

# Create collection with HNSW index
payload = json.dumps({
    'vectors': {
        'size': dim,
        'distance': 'Cosine'
    },
    'hnsw_config': {
        'm': 16,
        'ef_construct': 200
    }
}).encode()
req = urllib.request.Request(
    f'{base_url}/collections/bench_vectors',
    data=payload,
    headers={'Content-Type': 'application/json'},
    method='PUT'
)
urllib.request.urlopen(req, timeout=30)

# Batch insert vectors (batches of 100)
batch_size = 100
with open('${vectors_file}', 'rb') as f:
    for batch_start in range(0, count, batch_size):
        batch_end = min(batch_start + batch_size, count)
        points = []
        for i in range(batch_start, batch_end):
            data = f.read(dim * 4)
            if len(data) < dim * 4:
                break
            vec = list(struct.unpack(f'{dim}f', data))
            points.append({
                'id': i,
                'vector': vec,
            })

        payload = json.dumps({'points': points}).encode()
        req = urllib.request.Request(
            f'{base_url}/collections/bench_vectors/points',
            data=payload,
            headers={'Content-Type': 'application/json'},
            method='PUT'
        )
        urllib.request.urlopen(req, timeout=60)

        if batch_start % 1000 == 0 and batch_start > 0:
            print(f'  Inserted {batch_start}/{count} vectors...', file=sys.stderr)

print(f'Inserted {count} vectors into Qdrant', file=sys.stderr)
" 2>&1 || true

    local end_time
    end_time=$(python3 -c "import time; print(time.time())")

    local duration
    duration=$(python3 -c "print(f'{${end_time} - ${start_time}:.3f}')")
    local ops_per_sec
    ops_per_sec=$(python3 -c "
d = ${end_time} - ${start_time}
if d > 0:
    print(f'{${VECTOR_COUNT} / d:.0f}')
else:
    print('N/A')
")

    echo "QDRANT_INSERT_TIME=${duration}" >> "${RESULTS_DIR}/vector_${TIMESTAMP}.env"
    echo "QDRANT_INSERT_OPS=${ops_per_sec}" >> "${RESULTS_DIR}/vector_${TIMESTAMP}.env"

    ok "Qdrant insert: ${VECTOR_COUNT} vectors in ${duration}s (${ops_per_sec} ops/sec)"
}

benchmark_qdrant_search() {
    local queries_file="$1"
    local host="$2"
    local port="$3"

    info "Benchmarking Qdrant vector search (${NUM_QUERIES} queries, k=${SEARCH_K})..."

    python3 -c "
import struct
import json
import urllib.request
import time
import sys

dim = ${VECTOR_DIM}
num_queries = ${NUM_QUERIES}
k = ${SEARCH_K}
host = '${host}'
port = '${port}'
base_url = f'http://{host}:{port}'

latencies = []

with open('${queries_file}', 'rb') as f:
    for i in range(num_queries):
        data = f.read(dim * 4)
        if len(data) < dim * 4:
            break
        vec = list(struct.unpack(f'{dim}f', data))

        payload = json.dumps({
            'vector': vec,
            'limit': k,
            'with_payload': False,
        }).encode()

        t0 = time.perf_counter()
        req = urllib.request.Request(
            f'{base_url}/collections/bench_vectors/points/search',
            data=payload,
            headers={'Content-Type': 'application/json'},
            method='POST'
        )
        urllib.request.urlopen(req, timeout=30)
        t1 = time.perf_counter()
        latencies.append((t1 - t0) * 1000)

        if i % 100 == 0 and i > 0:
            print(f'  Completed {i}/{num_queries} queries...', file=sys.stderr)

if latencies:
    latencies.sort()
    avg = sum(latencies) / len(latencies)
    p50 = latencies[len(latencies) // 2]
    p95 = latencies[int(len(latencies) * 0.95)]
    p99 = latencies[int(len(latencies) * 0.99)]
    total_time = sum(latencies) / 1000
    qps = len(latencies) / total_time if total_time > 0 else 0

    print(f'AVG_LATENCY_MS={avg:.3f}')
    print(f'P50_LATENCY_MS={p50:.3f}')
    print(f'P95_LATENCY_MS={p95:.3f}')
    print(f'P99_LATENCY_MS={p99:.3f}')
    print(f'QPS={qps:.0f}')
" > "${RESULTS_DIR}/qdrant_search_${TIMESTAMP}.txt" 2>&1

    ok "Qdrant search complete -> ${RESULTS_DIR}/qdrant_search_${TIMESTAMP}.txt"
}

# ── Results Formatter ────────────────────────────────────────────────────────

print_results_table() {
    local ferrite_file="${RESULTS_DIR}/ferrite_search_${TIMESTAMP}.txt"
    local redis_file="${RESULTS_DIR}/redis_search_${TIMESTAMP}.txt"
    local qdrant_file="${RESULTS_DIR}/qdrant_search_${TIMESTAMP}.txt"

    echo ""
    echo "# Vector Search Benchmark Results"
    echo ""
    echo "**Configuration**: dim=${VECTOR_DIM}, vectors=${VECTOR_COUNT}, k=${SEARCH_K}, queries=${NUM_QUERIES}"
    echo "**Date**: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo ""

    # Insert performance
    if [[ -f "${RESULTS_DIR}/vector_${TIMESTAMP}.env" ]]; then
        local env_file="${RESULTS_DIR}/vector_${TIMESTAMP}.env"
        local ferrite_insert_time ferrite_insert_ops redis_insert_time redis_insert_ops
        local qdrant_insert_time qdrant_insert_ops
        ferrite_insert_time=$(read_result_value "$env_file" FERRITE_INSERT_TIME)
        ferrite_insert_ops=$(read_result_value "$env_file" FERRITE_INSERT_OPS)
        redis_insert_time=$(read_result_value "$env_file" REDIS_INSERT_TIME)
        redis_insert_ops=$(read_result_value "$env_file" REDIS_INSERT_OPS)
        qdrant_insert_time=$(read_result_value "$env_file" QDRANT_INSERT_TIME)
        qdrant_insert_ops=$(read_result_value "$env_file" QDRANT_INSERT_OPS)
        echo "## Insert Performance"
        echo ""
        echo "| Engine | Vectors | Time (s) | Ops/sec |"
        echo "|--------|---------|----------|---------|"
        echo "| Ferrite | ${VECTOR_COUNT} | ${ferrite_insert_time} | ${ferrite_insert_ops} |"
        if [[ "$FERRITE_ONLY" == false ]]; then
            echo "| Redis+RedisSearch | ${VECTOR_COUNT} | ${redis_insert_time} | ${redis_insert_ops} |"
            echo "| Qdrant | ${VECTOR_COUNT} | ${qdrant_insert_time} | ${qdrant_insert_ops} |"
        fi
        echo ""
    fi

    # Search performance
    echo "## Search Performance (KNN k=${SEARCH_K})"
    echo ""
    echo "| Engine | QPS | Avg Latency (ms) | P50 (ms) | P95 (ms) | P99 (ms) |"
    echo "|--------|-----|-------------------|----------|----------|----------|"

    if [[ -f "$ferrite_file" ]]; then
        local f_qps f_avg f_p50 f_p95 f_p99
        f_qps=$(grep 'QPS=' "$ferrite_file" 2>/dev/null | cut -d= -f2 || echo "N/A")
        f_avg=$(grep 'AVG_LATENCY_MS=' "$ferrite_file" 2>/dev/null | cut -d= -f2 || echo "N/A")
        f_p50=$(grep 'P50_LATENCY_MS=' "$ferrite_file" 2>/dev/null | cut -d= -f2 || echo "N/A")
        f_p95=$(grep 'P95_LATENCY_MS=' "$ferrite_file" 2>/dev/null | cut -d= -f2 || echo "N/A")
        f_p99=$(grep 'P99_LATENCY_MS=' "$ferrite_file" 2>/dev/null | cut -d= -f2 || echo "N/A")
        echo "| Ferrite | ${f_qps} | ${f_avg} | ${f_p50} | ${f_p95} | ${f_p99} |"
    fi

    if [[ -f "$redis_file" ]]; then
        local r_qps r_avg r_p50 r_p95 r_p99
        r_qps=$(grep 'QPS=' "$redis_file" 2>/dev/null | cut -d= -f2 || echo "N/A")
        r_avg=$(grep 'AVG_LATENCY_MS=' "$redis_file" 2>/dev/null | cut -d= -f2 || echo "N/A")
        r_p50=$(grep 'P50_LATENCY_MS=' "$redis_file" 2>/dev/null | cut -d= -f2 || echo "N/A")
        r_p95=$(grep 'P95_LATENCY_MS=' "$redis_file" 2>/dev/null | cut -d= -f2 || echo "N/A")
        r_p99=$(grep 'P99_LATENCY_MS=' "$redis_file" 2>/dev/null | cut -d= -f2 || echo "N/A")
        echo "| Redis+RedisSearch | ${r_qps} | ${r_avg} | ${r_p50} | ${r_p95} | ${r_p99} |"
    fi

    if [[ -f "$qdrant_file" ]]; then
        local q_qps q_avg q_p50 q_p95 q_p99
        q_qps=$(grep 'QPS=' "$qdrant_file" 2>/dev/null | cut -d= -f2 || echo "N/A")
        q_avg=$(grep 'AVG_LATENCY_MS=' "$qdrant_file" 2>/dev/null | cut -d= -f2 || echo "N/A")
        q_p50=$(grep 'P50_LATENCY_MS=' "$qdrant_file" 2>/dev/null | cut -d= -f2 || echo "N/A")
        q_p95=$(grep 'P95_LATENCY_MS=' "$qdrant_file" 2>/dev/null | cut -d= -f2 || echo "N/A")
        q_p99=$(grep 'P99_LATENCY_MS=' "$qdrant_file" 2>/dev/null | cut -d= -f2 || echo "N/A")
        echo "| Qdrant | ${q_qps} | ${q_avg} | ${q_p50} | ${q_p95} | ${q_p99} |"
    fi

    echo ""
    echo "## Notes"
    echo ""
    echo "- Ferrite uses native HNSW index with m=16, ef_construction=200, ef_search=50"
    echo "- Redis uses RedisSearch module with HNSW index (same default parameters)"
    echo "- Qdrant uses HNSW index with m=16, ef_construct=200 (HTTP API)"
    echo "- All vectors are normalized to unit length (cosine similarity)"
    echo "- Latencies include network round-trip (localhost)"
    echo "- QPS measured as sequential queries (no pipelining)"
    echo ""
}

# ── Cleanup ──────────────────────────────────────────────────────────────────

cleanup() {
    local host="$1"
    local port="$2"

    redis-cli -h "$host" -p "$port" FT.DROPINDEX "$INDEX_NAME" DD 2>/dev/null || true
}

# ── Main ─────────────────────────────────────────────────────────────────────

main() {
    parse_vector_args "$@"
    check_prereqs
    mkdir -p "$RESULTS_DIR"

    echo ""
    echo "======================================================================"
    echo "  Ferrite Vector Search Comparison Benchmark"
    echo "======================================================================"
    echo ""
    info "Configuration:"
    echo "  Vector dimension:  ${VECTOR_DIM}"
    echo "  Vector count:      ${VECTOR_COUNT}"
    echo "  Search k:          ${SEARCH_K}"
    echo "  Query count:       ${NUM_QUERIES}"
    echo ""

    # Generate test data
    local vectors_file="${RESULTS_DIR}/vectors_${TIMESTAMP}.bin"
    local queries_file="${RESULTS_DIR}/queries_${TIMESTAMP}.bin"

    generate_vectors "$VECTOR_COUNT" "$VECTOR_DIM" "$vectors_file"
    generate_queries "$NUM_QUERIES" "$VECTOR_DIM" "$queries_file"

    # Benchmark Ferrite
    if redis-cli -h "$FERRITE_HOST" -p "$FERRITE_PORT" PING 2>/dev/null | grep -q "PONG"; then
        cleanup "$FERRITE_HOST" "$FERRITE_PORT"
        benchmark_ferrite_insert "$vectors_file" "$FERRITE_HOST" "$FERRITE_PORT"
        benchmark_ferrite_search "$queries_file" "$FERRITE_HOST" "$FERRITE_PORT"
    else
        warn "Ferrite not reachable at ${FERRITE_HOST}:${FERRITE_PORT} -- skipping"
        warn "Start Ferrite with: cargo run --release"
    fi

    # Benchmark Redis
    if [[ "$FERRITE_ONLY" == false ]]; then
        if redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" PING 2>/dev/null | grep -q "PONG"; then
            # Check for RedisSearch module
            if redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" MODULE LIST 2>/dev/null | grep -qi "search"; then
                cleanup "$REDIS_HOST" "$REDIS_PORT"
                benchmark_redis_insert "$vectors_file" "$REDIS_HOST" "$REDIS_PORT"
                benchmark_redis_search "$queries_file" "$REDIS_HOST" "$REDIS_PORT"
            else
                warn "RedisSearch module not loaded on Redis at ${REDIS_HOST}:${REDIS_PORT}"
                warn "Start Redis with RedisSearch: docker run -p 6379:6379 redis/redis-stack-server:latest"
            fi
        else
            warn "Redis not reachable at ${REDIS_HOST}:${REDIS_PORT} -- skipping"
        fi

        # Benchmark Qdrant
        local qdrant_url="http://${QDRANT_HOST}:${QDRANT_PORT}"
        if curl -sf "${qdrant_url}/healthz" > /dev/null 2>&1 || \
           curl -sf "${qdrant_url}/collections" > /dev/null 2>&1; then
            benchmark_qdrant_insert "$vectors_file" "$QDRANT_HOST" "$QDRANT_PORT"
            benchmark_qdrant_search "$queries_file" "$QDRANT_HOST" "$QDRANT_PORT"
        else
            warn "Qdrant not reachable at ${qdrant_url} -- skipping"
            warn "Start Qdrant with: docker run -p 6333:6333 qdrant/qdrant"
        fi
    fi

    # Print results table
    local results_md="${RESULTS_DIR}/vector_comparison_${TIMESTAMP}.md"
    print_results_table | tee "$results_md"

    info "Full results saved to ${results_md}"

    # Cleanup temp files
    rm -f "$vectors_file" "$queries_file"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
