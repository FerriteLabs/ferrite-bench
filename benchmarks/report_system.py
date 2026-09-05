"""Host information collection for benchmark reports."""

import os
import platform
import subprocess


def _command_version(command: list[str]) -> str:
    try:
        result = subprocess.run(
            command,
            capture_output=True,
            text=True,
            timeout=5,
            check=False,
        )
    except (OSError, subprocess.SubprocessError):
        return "N/A"
    return result.stdout.strip() or "N/A"


def get_system_info() -> list[tuple[str, str]]:
    """Collect host information without making report generation fail."""
    cpu_count = os.cpu_count()
    return [
        ("OS", f"{platform.system()} {platform.release()}"),
        ("Architecture", platform.machine()),
        ("Python", platform.python_version()),
        ("Docker", _command_version(["docker", "--version"])),
        ("Docker Compose", _command_version(["docker", "compose", "version"])),
        ("Host CPUs", str(cpu_count) if cpu_count else "N/A"),
    ]
