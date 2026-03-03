#!/usr/bin/env bash
# system_info.sh — Capture hardware/OS details for benchmark reproducibility
# Output: JSON to stdout (redirect to file as needed)
set -euo pipefail

get_cpu_model() {
  if [[ "$(uname)" == "Darwin" ]]; then
    sysctl -n machdep.cpu.brand_string 2>/dev/null || echo "unknown"
  else
    grep -m1 'model name' /proc/cpuinfo 2>/dev/null | cut -d: -f2 | xargs || echo "unknown"
  fi
}

get_cpu_cores() {
  if [[ "$(uname)" == "Darwin" ]]; then
    sysctl -n hw.ncpu 2>/dev/null || echo "0"
  else
    nproc 2>/dev/null || echo "0"
  fi
}

get_total_ram_gb() {
  if [[ "$(uname)" == "Darwin" ]]; then
    echo "scale=1; $(sysctl -n hw.memsize 2>/dev/null || echo 0) / 1073741824" | bc
  else
    echo "scale=1; $(grep MemTotal /proc/meminfo 2>/dev/null | awk '{print $2}') / 1048576" | bc
  fi
}

get_kernel() {
  uname -r
}

get_io_uring_support() {
  if [[ "$(uname)" == "Linux" ]] && [[ -e /proc/sys/kernel/io_uring_disabled ]]; then
    local disabled
    disabled=$(cat /proc/sys/kernel/io_uring_disabled 2>/dev/null || echo "1")
    [[ "$disabled" == "0" ]] && echo "true" || echo "false"
  elif [[ "$(uname)" == "Linux" ]]; then
    # Older kernels without the sysctl — check kernel version >= 5.1
    local major minor
    major=$(uname -r | cut -d. -f1)
    minor=$(uname -r | cut -d. -f2)
    [[ "$major" -gt 5 || ("$major" -eq 5 && "$minor" -ge 1) ]] && echo "true" || echo "false"
  else
    echo "false"
  fi
}

cat <<EOF
{
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "os": "$(uname -s)",
  "arch": "$(uname -m)",
  "kernel": "$(get_kernel)",
  "cpu_model": "$(get_cpu_model)",
  "cpu_cores": $(get_cpu_cores),
  "ram_gb": $(get_total_ram_gb),
  "io_uring": $(get_io_uring_support),
  "hostname": "$(hostname -s 2>/dev/null || echo unknown)",
  "ferrite_version": "$(ferrite --version 2>/dev/null | head -1 || echo unknown)",
  "redis_version": "$(redis-server --version 2>/dev/null | awk '{print $3}' | cut -d= -f2 || echo unknown)",
  "memtier_version": "$(memtier_benchmark --version 2>/dev/null | head -1 || echo unknown)"
}
EOF
