#!/usr/bin/env python3
"""Check-write-permission: Gate writes to story-driven or workflow-driven flow.

PreToolUse hook — allows writes if:
  1. File is in .craft/ or .claude/ directory
  2. File is outside the project workspace
  3. dev_mode: true in .craft/settings.yaml
  4. CRAFT_WRITE_ENABLED=true in .craft/.global-state
  5. An active workflow session exists (status: active in any session.md)

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

    # Fallback: .craft/ directory without .global-state
    d = os.getcwd()
    while d != os.path.dirname(d):
        if os.path.isdir(os.path.join(d, ".craft")):
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


def find_project_root():
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

    # Check 1: Is this a .craft/ or .craft-director/ file? Always allow
    if "/.craft/" in file_path or file_path.startswith(".craft/"):
        return
    if "/.craft-director/" in file_path or file_path.startswith(".craft-director/"):
        return

    # Check 1b: Is this Claude's own internal storage? Always allow
    if "/.claude/" in file_path:
        return

    # Resolve project root (monorepo-aware)
    project_root = find_project_root()

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

    # Check 4: CRAFT_WRITE_ENABLED in global state?
    state_file = os.path.join(project_root, ".craft", ".global-state")
    if os.path.isfile(state_file):
        state = parse_state_file(state_file)
        if state.get("CRAFT_WRITE_ENABLED") == "true":
            return

    # Check 5: Active workflow session? (status: active in any session.md)
    workflows_dir = os.path.join(project_root, ".craft", "workflows")
    if os.path.isdir(workflows_dir):
        for wf_name in os.listdir(workflows_dir):
            if wf_name.startswith("."):
                continue
            sessions_dir = os.path.join(workflows_dir, wf_name, "sessions")
            if not os.path.isdir(sessions_dir):
                continue
            for session_name in os.listdir(sessions_dir):
                session_file = os.path.join(sessions_dir, session_name, "session.md")
                if not os.path.isfile(session_file):
                    continue
                with open(session_file, "r") as f:
                    in_fm = False
                    for line in f:
                        stripped = line.strip()
                        if stripped == "---":
                            if not in_fm:
                                in_fm = True
                                continue
                            else:
                                break
                        if in_fm and stripped.startswith("status:"):
                            val = stripped.split(":", 1)[1].strip()
                            if val == "active":
                                return

    # All checks failed — block the write
    deny()


if __name__ == "__main__":
    try:
        main()
    except Exception:
        pass  # Fail open — any error allows the write
    sys.exit(0)
