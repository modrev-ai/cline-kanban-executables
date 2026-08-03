# YAML Syntax Validation

This document describes the YAML syntax validation setup for this repository.

## Overview

To prevent deployment issues caused by invalid YAML syntax, this repository implements YAML validation at two levels:

1. **Pre-commit hook** - Runs locally before each commit
2. **GitHub Actions workflow** - Runs in CI on push and pull requests

## Pre-commit Hook

### Location
`.git/hooks/pre-commit`

### How it works
- Runs automatically when you execute `git commit`
- Finds all `.yml` and `.yaml` files in the repository (excluding `.git` directory)
- Validates each file using Python's PyYAML library
- Rejects the commit if any YAML file has syntax errors

### Requirements
- Python 3.x
- PyYAML package (`pip install pyyaml`)

### Bypassing the hook (not recommended)
```bash
git commit --no-verify
```

## GitHub Actions Workflow

### Location
`.github/workflows/validate-yaml.yml`

### Triggers
- Push to any branch (when YAML files are modified)
- Pull requests (when YAML files are modified)

### How it works
- Checks out the repository
- Sets up Python
- Installs PyYAML
- Finds all YAML files
- Validates each file
- Fails the workflow if any file has syntax errors

## Testing the Validation

### Test locally
```bash
# Run the pre-commit hook manually
bash .git/hooks/pre-commit
```

### Test with invalid YAML
```bash
# Create a broken YAML file
echo "invalid: yaml: content: [" > test-broken.yaml
echo "  missing: colon" >> test-broken.yaml

# Run validation - should fail
bash .git/hooks/pre-commit

# Clean up
rm test-broken.yaml
```

## Common YAML Syntax Issues

| Issue | Example | Fix |
|-------|---------|-----|
| Missing closing brace | `${{ secrets.KEY }}` | `${{ secrets.KEY }}` |
| Incorrect indentation | `key:\n  value` | `key:\n  value` (consistent spaces) |
| Unclosed brackets | `list: [item1, item2` | `list: [item1, item2]` |
| Invalid characters | `key: value: extra` | `key: "value: extra"` |
| Missing quotes for special chars | `password: my@pass` | `password: "my@pass"` |

## Adding New YAML Files

When adding new YAML files to the repository:
1. The pre-commit hook will automatically validate them
2. The CI workflow will automatically validate them
3. No additional configuration needed

## Troubleshooting

### "python3 not found"
Install Python 3.x and ensure it's in your PATH.

### "PyYAML not installed"
```bash
pip install pyyaml
```

### Hook not running
Ensure the hook is executable:
```bash
chmod +x .git/hooks/pre-commit
```

### Windows line endings
If you're on Windows, ensure the hook uses LF line endings:
```bash
git config core.autocrlf false
# Re-clone or fix the hook file
```

## Files Validated

All files matching these patterns:
- `*.yml`
- `*.yaml`
- `.github/workflows/**/*.yml`
- `.github/workflows/**/*.yaml`

## Related Files

- `.git/hooks/pre-commit` - Local pre-commit hook
- `.github/workflows/validate-yaml.yml` - CI validation workflow
- `.github/workflows/deploy-oracle.yml` - Example workflow (validated)