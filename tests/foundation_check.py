"""Static, standard-library checks. Not a substitute for a full secret scanner or recovery test."""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
required = [
    "README.md", "LICENSE", ".gitignore", "diagrams/architecture.mmd",
    "infrastructure/docker/compose.yaml", "sample-data/schema.sql",
    "sample-data/seed.sql", "docs/ARCHITECTURE.md", "docs/SECURITY.md",
    "docs/THREAT-MODEL.md", "docs/RECOVERY-RUNBOOK.md",
    "docs/RECOVERY-VALIDATION.md", "docs/RPO-RTO.md",
    ".github/workflows/ci.yml", ".github/workflows/security.yml",
]
missing = [name for name in required if not (ROOT / name).is_file()]
assert not missing, f"Missing foundation files: {missing}"

# Literal tokens/URLs are not permitted in public lab source. This scanner is intentionally
# conservative and must be supplemented with Gitleaks and manual staged-diff review.
for file in ROOT.rglob("*"):
    if not file.is_file() or ".git" in file.parts or "__pycache__" in file.parts:
        continue
    if file.suffix not in {".md", ".mmd", ".sql", ".yaml", ".yml", ".py", ".example"}:
        continue
    content = file.read_text(encoding="utf-8")
    for pattern in [
        r"-----BEGIN (?:RSA |OPENSSH |EC )?PRIVATE KEY-----",
        r"postgres(?:ql)?://[^\s]+@",
        r"AKIA[0-9A-Z]{16}",
        r"(?i)\b(?:sk_live|ghp_|github_pat_)\w{12,}",
    ]:
        assert not re.search(pattern, content), f"Potential credential in {file.relative_to(ROOT)}"

compose = (ROOT / "infrastructure/docker/compose.yaml").read_text()
assert "ports:" not in compose, "Database ports must not be published"
assert "internal: true" in compose, "Network must be isolated"
assert "postgres:17-bookworm" in compose
schema = (ROOT / "sample-data/schema.sql").read_text()
assert schema.count("ENABLE ROW LEVEL SECURITY") == 3
assert schema.count("FORCE ROW LEVEL SECURITY") == 3
for workflow in (ROOT / ".github/workflows").glob("*.yml"):
    content = workflow.read_text()
    assert "contents: read" in content
    for ref in re.findall(r"uses:\s*([^\s]+)", content):
        assert re.fullmatch(r"[\w.-]+/[\w.-]+@[a-f0-9]{40}", ref), f"Unpinned action {ref}"
print("PASS: foundation files, basic confidentiality patterns, RLS declarations, Compose isolation, and action pin syntax")
