#!/usr/bin/env python3
"""Setup script for the auth feature.

Run this after adding the auth feature to configure dependencies,
settings, and environment variables.

Usage:
    python features/auth/setup.py
"""

import ast
import subprocess
import sys
from pathlib import Path


def get_project_root() -> Path:
    """Find the project root by looking for main.py."""
    current = Path(__file__).resolve().parent
    while current != current.parent:
        if (current / "main.py").exists():
            return current
        current = current.parent
    print("Error: Could not find project root (main.py not found)")
    sys.exit(1)


def add_dependencies(project_root: Path) -> bool:
    """Add auth dependencies to pyproject.toml."""
    import tomllib

    import tomli_w

    pyproject_path = project_root / "pyproject.toml"
    if not pyproject_path.exists():
        print("Warning: pyproject.toml not found")
        return False

    deps_to_add = [
        "boto3>=1.35.0",
        "python-jose[cryptography]>=3.3.0",
        "httpx>=0.27.0",
        "email-validator>=2.3.0",
    ]

    with open(pyproject_path, "rb") as f:
        pyproject = tomllib.load(f)

    current = pyproject.get("project", {}).get("dependencies", [])

    added = []
    for dep in deps_to_add:
        dep_name = dep.split(">=")[0].split("==")[0].split("<")[0].split("[")[0].strip()
        existing_names = [
            d.split(">=")[0].split("==")[0].split("<")[0].split("[")[0].strip()
            for d in current
        ]
        if dep_name not in existing_names:
            current.append(dep)
            added.append(dep)

    if added:
        pyproject["project"]["dependencies"] = current
        with open(pyproject_path, "wb") as f:
            tomli_w.dump(pyproject, f)
        print(f"  Added to pyproject.toml: {', '.join(added)}")
        return True
    else:
        print("  Dependencies already in pyproject.toml")
        return False


def run_uv_sync(project_root: Path) -> None:
    """Run uv sync to install dependencies."""
    print("  Running uv sync...")
    result = subprocess.run(
        ["uv", "sync"],
        cwd=project_root,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        print(f"  Warning: uv sync failed: {result.stderr}")
    else:
        print("  Dependencies installed")


def update_settings(project_root: Path) -> None:
    """Add Cognito settings to settings.py."""
    settings_path = project_root / "settings.py"
    if not settings_path.exists():
        print("  Warning: settings.py not found")
        return

    content = settings_path.read_text()
    tree = ast.parse(content)

    # Find the Settings class
    settings_class = None
    for node in ast.walk(tree):
        if isinstance(node, ast.ClassDef) and node.name == "Settings":
            settings_class = node
            break

    if not settings_class:
        print("  Warning: Settings class not found in settings.py")
        return

    # Get existing field names
    existing_fields = set()
    for item in settings_class.body:
        if isinstance(item, ast.AnnAssign) and isinstance(item.target, ast.Name):
            existing_fields.add(item.target.id.lower())

    # Settings to add
    cognito_settings = {
        "cognito_user_pool_id": ("str", None),
        "cognito_client_id": ("str", None),
        "cognito_client_secret": ("str", None),
        "cognito_region": ("str", '"us-east-1"'),
    }

    new_fields = []
    for field_name, (field_type, default) in cognito_settings.items():
        if field_name not in existing_fields:
            if default:
                new_fields.append(f"    {field_name}: {field_type} = {default}")
            else:
                new_fields.append(f"    {field_name}: {field_type}")

    if not new_fields:
        print("  Cognito settings already in settings.py")
        return

    # Find the insertion point
    lines = content.split("\n")
    class_start = None
    for i, line in enumerate(lines):
        if "class Settings" in line:
            class_start = i
            break

    if class_start is None:
        print("  Warning: Could not find Settings class")
        return

    # Find the first method or end of fields
    insert_line = None
    for i in range(class_start + 1, len(lines)):
        line = lines[i].strip()
        if line.startswith("@") or line.startswith("def "):
            insert_line = i
            break
        if line and not line.startswith("#") and not lines[i].startswith(" "):
            insert_line = i
            break

    if insert_line is None:
        insert_line = len(lines)

    # Insert new fields
    new_content = "\n".join(new_fields)
    comment = "\n    # Cognito Auth"
    lines.insert(insert_line, "")
    lines.insert(insert_line, new_content)
    lines.insert(insert_line, comment)

    settings_path.write_text("\n".join(lines))
    print("  Updated settings.py with Cognito settings")


def update_env_file(project_root: Path, filename: str) -> None:
    """Add Cognito env vars to .env or .env.example."""
    env_path = project_root / filename
    if not env_path.exists():
        return

    content = env_path.read_text()

    env_vars = {
        "COGNITO_USER_POOL_ID": "us-east-1_XXXXXXXXX",
        "COGNITO_CLIENT_ID": "your-client-id",
        "COGNITO_CLIENT_SECRET": "your-client-secret",
        "COGNITO_REGION": "us-east-1",
    }

    new_vars = []
    for var_name, default_value in env_vars.items():
        if f"{var_name}=" not in content:
            new_vars.append(f"{var_name}={default_value}")

    if not new_vars:
        return

    if not content.endswith("\n"):
        content += "\n"

    content += "\n# Cognito Auth\n"
    content += "\n".join(new_vars) + "\n"

    env_path.write_text(content)
    print(f"  Updated {filename}")


def main() -> None:
    """Run the auth feature setup."""
    print("Setting up auth feature...")
    print()

    project_root = get_project_root()

    print("[1/4] Adding dependencies to pyproject.toml")
    deps_added = add_dependencies(project_root)

    print("[2/4] Installing dependencies")
    if deps_added:
        run_uv_sync(project_root)
    else:
        print("  Skipped (no new dependencies)")

    print("[3/4] Updating settings.py")
    update_settings(project_root)

    print("[4/4] Updating environment files")
    update_env_file(project_root, ".env")
    update_env_file(project_root, ".env.example")

    print()
    print("Auth feature setup complete!")
    print()
    print("Next steps:")
    print("  1. Configure your AWS Cognito credentials in .env")
    print("  2. See SETUP.md for AWS Cognito configuration guide")


if __name__ == "__main__":
    main()
