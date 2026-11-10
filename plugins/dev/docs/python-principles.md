# TLDR
Conventions for writing Python. Two rules carry the most weight and are the usual sources of avoidable CI failures or churn:

> - **Always run through the environment** — `uv run …` or the project venv, never bare `python`.
> - **`just check` is the gate** — run the full thing before pushing (it runs lint + format + `mypy` **and** `pyright` + tests), then re-check `git status` and commit any diff it left.

The package-structure and docstring rules below are strict; deviate only with explicit permission.
# Environment
- Never run python commands directly within a python project. Always use `uv run …`, or use the project virtualenv.
# Verifying before you push
`just check` is the gate CI runs (lint + format + `mypy` **and** `pyright` + unit tests). Run the full `just check` before pushing rather than piecemeal commands (`uv run mypy`, `uv run ruff …`) — piecemeal runs skip whichever check you forget, and **pyright is the usual miss**, since `mypy` alone passes code that pyright rejects.
If `just check` **auto-fixes formatting** as it runs, a pass can leave you with modified files. After it passes, check for a diff (`git status`) and commit/push it — otherwise CI, which only *checks* formatting, fails on the code you left behind.
# Package structure
For all of these: if there is a very specific reason to make an exception, you may ask the user for permission. But do **not** do this without permission.
- **Never** import and re-export in a package's `__init__.py`. Imports should come from the package where the code is originally defined.
- **Never** put code in `__init__.py` files.
- **Never** use `__all__`.
- **Never** use lazy imports.
# Docstrings
Multiline docstrings must **always** have a newline after the opening triple quotes and before the closing triple quotes:
```python
"""
This is a docstring
with multiple lines.
"""
```
Never like this:
```python
"""This is a docstring
with multiple lines."""
```