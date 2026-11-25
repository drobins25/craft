#!/usr/bin/env python3
"""Check-write-permission: Gate writes to story-driven or workflow-driven flow.

PreToolUse hook — allows writes if:
  1. File is in .craft/ or .claude/ directory
  2. File is outside the project workspace
  3. dev_mode: true in .craft/settings.yaml
  4. The writing session holds a gate file, .craft/.gate/<session_id>
     (a workflow session's writes pass here too, on the gate of the session
     running it; an active session.md alone allows nothing)

Otherwise blocks with guidance to use craft workflow.

Fail open on ANY unexpected error — never crash a write gate.
"""
import json
import os
import re
import subprocess
import sys


def parse_state_file(path):
    """Parse a shell-style key=value state file into a dict."""
    data = {}
    if not os.path.isfile(path):
        return data
    with open(path, "r") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            if "=" in line:
                key, _, value = line.partition("=")
                data[key.strip()] = value.strip().strip('"')
    return data


def _git_repo_root():
    """Get the git repo root, or None."""
    try:
        result = subprocess.run(
            ["git", "rev-parse", "--show-toplevel"],
            capture_output=True, text=True, timeout=5
        )
        if result.returncode == 0:
            return result.stdout.strip()
    except Exception:
        pass
    return None


def _find_nearest_craft():
    """Walk up from cwd looking for .craft/.global-state or .craft/ directory."""
    # Prefer .craft/.global-state (fully initialized project)
    d = os.getcwd()
    while d != os.path.dirname(d):
        if os.path.isfile(os.path.join(d, ".craft", ".global-state")):
            return d.rstrip("/") + "/"
        d = os.path.dirname(d)

    # Fallback: .craft/ with project.md but no .global-state (mirrors
    # find-workshop.sh). A bare .craft/ — e.g. only mockups/ in a
    # never-inited project — is not a project root; treating it as one
    # would arm the write gate against every source edit there.
    d = os.getcwd()
    while d != os.path.dirname(d):
        if os.path.isdir(os.path.join(d, ".craft")) and os.path.isfile(
            os.path.join(d, ".craft", "project.md")
        ):
            return d.rstrip("/") + "/"
        d = os.path.dirname(d)

    return None


def _has_sub_projects(repo_root):
    """Check if repo root has registered sub-projects with their own .craft/."""
    projects_dir = os.path.join(repo_root, ".craft", "projects")
    if not os.path.isdir(projects_dir):
        return False

    count = 0
    for f in os.listdir(projects_dir):
        if not f.endswith(".md"):
            continue
        fpath = os.path.join(projects_dir, f)
        # Extract path: from YAML frontmatter
        path_val = _extract_frontmatter_field(fpath, "path")
        if path_val and os.path.isdir(os.path.join(repo_root, path_val, ".craft")):
            count += 1

    return count > 0


def _extract_frontmatter_field(filepath, field):
    """Extract a field value from YAML frontmatter (simple line parsing)."""
    in_frontmatter = False
    with open(filepath, "r") as f:
        for line in f:
            stripped = line.strip()
            if stripped == "---":
                if not in_frontmatter:
                    in_frontmatter = True
                    continue
                else:
                    break  # End of frontmatter
            if in_frontmatter and stripped.startswith(field + ":"):
                value = stripped[len(field) + 1:].strip().strip('"').strip("'")
                return value
    return None


def _find_active_sub_project(repo_root):
    """Find the single active sub-project (has ACTIVE_CYCLE set)."""
    projects_dir = os.path.join(repo_root, ".craft", "projects")
    if not os.path.isdir(projects_dir):
        return None

    active_path = None
    active_name = None
    active_count = 0

    for f in os.listdir(projects_dir):
        if not f.endswith(".md"):
            continue
        fpath = os.path.join(projects_dir, f)
        name = _extract_frontmatter_field(fpath, "name")
        path_val = _extract_frontmatter_field(fpath, "path")
        if not name or not path_val:
            continue

        abs_path = os.path.join(repo_root, path_val)
        gs = os.path.join(abs_path, ".craft", ".global-state")
        if os.path.isfile(gs):
            state = parse_state_file(gs)
            if state.get("ACTIVE_CYCLE", ""):
                active_path = abs_path.rstrip("/") + "/"
                active_name = name
                active_count += 1

    if active_count == 1:
        return active_path
    return None


def find_workshop():
    """Resolve the active Craft project root (monorepo-aware).

    Resolution order:
      1. CRAFT_PROJECT_ROOT env var (set by session-start or /craft:project)
      2. Walk up from cwd looking for .craft/.global-state or .craft/
      3. If landed on monorepo root with sub-projects, check .pinned-project
      4. If no pin, auto-select the single active sub-project
    """
    # 1. Check env var
    env_root = os.environ.get("CRAFT_PROJECT_ROOT", "")
    if env_root:
        root = env_root.rstrip("/") + "/"
        if os.path.isdir(os.path.join(root, ".craft")):
            return root

    # 2. Walk up from cwd
    nearest = _find_nearest_craft()
    if not nearest:
        return None

    # Check: did we land on the monorepo root which has sub-projects?
    repo_root = _git_repo_root()
    nearest_dir = nearest.rstrip("/")

    if repo_root and nearest_dir == repo_root and _has_sub_projects(repo_root):
        # Check for persistent project pin
        pin_file = os.path.join(nearest, ".craft", ".pinned-project")
        if os.path.isfile(pin_file):
            with open(pin_file, "r") as f:
                lines = f.read().strip().splitlines()
            if lines:
                pinned_root = lines[0].strip()
                if pinned_root and os.path.isdir(os.path.join(pinned_root.rstrip("/"), ".craft")):
                    return pinned_root.rstrip("/") + "/"

        # No pin — try to auto-select the single active sub-project
        active = _find_active_sub_project(repo_root)
        if active:
            return active

        # Multiple active or none — return monorepo root
        return nearest

    # Found a non-root .craft/ — use it directly
    return nearest


SESSION_ID_RE = re.compile(r"^[A-Za-z0-9_-]{1,128}$")


def _is_craft_project(folder):
    craft = os.path.join(folder, ".craft")
    return os.path.isfile(os.path.join(craft, ".global-state")) or os.path.isfile(
        os.path.join(craft, "project.md")
    )


def session_holds_gate(session_id, project_root, file_path, cwd):
    """True when .craft/.gate/<session_id> is a file under the resolved root or
    under any Craft project that encloses the written file."""
    if not isinstance(session_id, str) or not SESSION_ID_RE.match(session_id):
        return False

    roots = [project_root]
    absolute = file_path if file_path.startswith("/") else os.path.join(cwd, file_path)
    d = os.path.dirname(os.path.normpath(absolute))
    while True:
        if _is_craft_project(d):
            roots.append(d)
        parent = os.path.dirname(d)
        if parent == d:
            break
        d = parent

    for root in roots:
        if os.path.isfile(os.path.join(root, ".craft", ".gate", session_id)):
            return True
    return False


def deny():
    """Output deny decision in hookSpecificOutput format."""
    result = {
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": (
                "BLOCKED: No active story or workflow session. "
                "For workflow sessions, run start-workflow-session.sh to activate the session first. "
                "For small targeted changes to existing behavior or appearance - a bug with a "
                "known root cause OR a small enhancement to something already built (different "
                "icon, wording, spacing) - use Skill(craft:adhoc). "
                "For new features or complex changes, use Skill(craft:craft-story-new) or "
                "Skill(craft:craft-story-implement)."
            ),
        }
    }
    print(json.dumps(result, indent=2))


def main():
    # Read hook input from stdin
    input_data = json.load(sys.stdin)
    tool_input = input_data.get("tool_input", {})

    # Extract file path
    file_path = (
        tool_input.get("file_path", "")
        or tool_input.get("filePath", "")
        or ""
    )

    # If we can't determine file path, allow (fail open)
    if not file_path:
        return

    # Get the working directory from input
    cwd = input_data.get("cwd", ".")

    # Check 0: an EXISTING .craft/design/tokens.yaml is a merge target - the Write
    # tool regenerates whole files, which destroys every key and comment it didn't
    # think about (live-run incident 2026-07-11). Deny Write (not Edit) and carry the
    # correct action in the message. Creation (file absent) stays allowed - the
    # mockup cold path depends on it.
    tool_name = input_data.get("tool_name", "")
    if tool_name == "Write" and (
        file_path.endswith("/.craft/design/tokens.yaml")
        or file_path == ".craft/design/tokens.yaml"
    ):
        resolved_tokens = file_path if file_path.startswith("/") else os.path.join(cwd, file_path)
        if os.path.isfile(resolved_tokens):
            result = {
                "hookSpecificOutput": {
                    "hookEventName": "PreToolUse",
                    "permissionDecision": "deny",
                    "permissionDecisionReason": (
                        "BLOCKED: .craft/design/tokens.yaml already exists - it is a "
                        "merge target, never regenerated. For a keyed merge "
                        "(init extraction or inspiration Lock): run "
                        "python3 ${CLAUDE_PLUGIN_ROOT}/hooks/scripts/merge-tokens.py "
                        "merge .craft/design/tokens.yaml --template "
                        "${CLAUDE_PLUGIN_ROOT}/templates/craft/design/tokens.yaml "
                        "with values on stdin as section.key=value|comment lines "
                        "(--precedence incoming for inspiration; --resolve only for "
                        "user-chosen conflict keys). For a single accepted-value "
                        "update (tweak reconcile, lock-decision): use the Edit tool "
                        "on the specific key's line."
                    ),
                }
            }
            print(json.dumps(result, indent=2))
            return

    # Check 1: Is this a .craft/ or .craft-director/ file? Always allow
    if "/.craft/" in file_path or file_path.startswith(".craft/"):
        return
    if "/.craft-director/" in file_path or file_path.startswith(".craft-director/"):
        return

    # Check 1b: Is this Claude's own internal storage? Always allow
    if "/.claude/" in file_path:
        return

    # Resolve project root (monorepo-aware)
    project_root = find_workshop()

    # If no .craft directory found, allow (not a craft project)
    if not project_root or not os.path.isdir(os.path.join(project_root, ".craft")):
        return

    # Check 2: Is the file outside the project? Always allow
    if file_path.startswith("/"):
        # Absolute path — check if inside project
        if not file_path.startswith(project_root):
            return
    else:
        # Relative path — resolve against cwd
        resolved = os.path.join(cwd, file_path)
        if not resolved.startswith(project_root):
            return

    # Check 3: dev_mode enabled?
    settings_file = os.path.join(project_root, ".craft", "settings.yaml")
    if os.path.isfile(settings_file):
        with open(settings_file, "r") as f:
            for line in f:
                stripped = line.strip()
                if stripped.startswith("dev_mode:"):
                    value = stripped.split(":", 1)[1].strip()
                    if value == "true":
                        return

    # Check 4: does the writing session hold a gate file? The file's name is the
    # session id the hook input carries; its content is never read. An opener
    # resolves its root through CRAFT_PROJECT_ROOT, which hooks never receive, so
    # the file is also looked for under every Craft project enclosing the file.
    if session_holds_gate(input_data.get("session_id"), project_root, file_path, cwd):
        return

    # All checks failed — block the write
    deny()


if __name__ == "__main__":
    try:
        main()
    except Exception:
        pass  # Fail open — any error allows the write
    sys.exit(0)
