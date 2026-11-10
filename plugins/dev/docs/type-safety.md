# TLDR
Python's type system is optional, but used well it catches bugs before runtime, improves IDE support, documents interfaces, and makes refactoring safer. Used poorly, type hints add noise without safety — worse than no types. This guide covers how to fix type-check errors in ways that genuinely improve code quality rather than merely silencing the checker.

> **The thesis in two lines:**
> **Fixed-key data belongs in structured types** (dataclass / TypedDict / pydantic) — reserve `dict` for maps whose keys are only known at runtime.
> **Fix type errors in ways that improve the code**, not that quiet the checker: isolate workarounds in wrappers, narrow through the class hierarchy instead of `getattr`, specify and explain every `# type: ignore`, prefer real generics over `Any`, let inference do the obvious work, and use modern `type` / `[T]` syntax.

# Glossary
<table>
<tr>
<td>**Uniform dictionary**</td>
<td>A map whose keys are determined at runtime, not known at design time. Typed as `dict[K, V]` — e.g. a cache of user IDs to users, or a word-frequency counter. The correct, legitimate use of a plain dict.</td>
</tr>
<tr>
<td>**Fixed-key dictionary**</td>
<td>Data with a specific, statically-known set of string keys, each with a known type — configuration, API responses, database records. This is structured data and should NOT be a plain dict.</td>
</tr>
<tr>
<td>**Structured type**</td>
<td>A `TypedDict`, dataclass, or pydantic model — anything that gives the type checker knowledge of the keys/fields and their types.</td>
</tr>
<tr>
<td>**Stub file** (`.pyi`)</td>
<td>A file supplying type information for a module that lacks it. Critically all-or-nothing: it completely overrides the real library's type hints for that module.</td>
</tr>
<tr>
<td>**Type workaround**</td>
<td>A `cast()` or `# type: ignore` used to get past dynamic code, poorly-typed libraries, or checker limitations. Necessary sometimes; should be isolated and minimized.</td>
</tr>
<tr>
<td>**Narrowing**</td>
<td>Convincing the type checker that a value has a more specific type than its declared one — via `isinstance()`, `assert`, or `cast()`.</td>
</tr>
</table>
# Fixed-Key Data Belongs in Structured Types
Dictionaries serve two distinct purposes in Python, and the type system treats them differently.
**Uniform dictionaries** are maps where the keys are determined at runtime, not known at design time. These are typed as `dict[K, V]`. For example, a cache mapping user IDs to user objects, or a counter tracking word frequencies in a document. The keys are truly dynamic — you don't know what they'll be until the code runs.
**Fixed-key dictionaries** have a specific set of string keys, each with a known type. These represent structured data: configuration objects, API responses, database records. The keys are static — they're part of the data's definition, not discovered at runtime.
When you use a plain `dict` for fixed-key data, you lose type safety on both keys and values. The type checker can't verify that you're accessing the right keys or using the values correctly. Autocomplete doesn't work. Refactoring becomes dangerous.
PEP 589 introduced `TypedDict` to address this, and Python also offers dataclasses and pydantic models. All three provide type safety for fixed-key data. Choose based on your needs:
- **TypedDict**: Minimal, dictionary-based, useful when interfacing with JSON or when you need dict semantics
- **Dataclass**: Python standard library, immutable via `frozen=True`, good default choice
- **Pydantic models**: Runtime validation, serialization, excellent for API boundaries and configuration
## Examples

> **Anti-pattern: Dict for fixed-key data**
> ```python
> def get_user_data(user_id: int) -> dict[str, Any]:
>     return {
>         "id": user_id,
>         "name": db.get_name(user_id),
>         "email": db.get_email(user_id),
>         "role": db.get_role(user_id)
>     }
>
> # Callers have no type safety
> user = get_user_data(123)
> print(user["name"])  # Could be a typo, checker won't catch it
> print(user["age"])   # Key doesn't exist, no error until runtime
> ```


> **Better: Dataclass**
> ```python
> @dataclass
> class UserData:
>     id: int
>     name: str
>     email: str
>     role: str
>
> def get_user_data(user_id: int) -> UserData:
>     return UserData(
>         id=user_id,
>         name=db.get_name(user_id),
>         email=db.get_email(user_id),
>         role=db.get_role(user_id)
>     )
>
> # Callers get autocomplete and type checking
> user = get_user_data(123)
> print(user.name)  # Type-safe
> print(user.age)   # Error: UserData has no attribute 'age'
> ```


> **Legitimate dict use: Runtime-determined keys**
> ```python
> # This is a uniform dictionary - keys are dynamic
> def count_words(text: str) -> dict[str, int]:
>     counts: dict[str, int] = {}
>     for word in text.split():
>         counts[word] = counts.get(word, 0) + 1
>     return counts
> ```

The distinction is simple: if you know the keys at design time, use a structured type. If the keys are determined at runtime, use a dict.
# Stub Files Are All-or-Nothing
Type stub files (`.pyi`) are a powerful mechanism for providing type information for libraries that lack it. However, they come with a critical tradeoff: **once you create a stub for a module, it completely overrides any type hints from the actual library**.
This has important implications. If a library is mostly well-typed but has a few gaps or inaccuracies, creating a stub to fix those specific issues will backfire. Your stub replaces all the library's existing type information, forcing you to duplicate the entire module's type interface in your stub just to fix one small problem.
**When to create stubs:**
- The library is genuinely untyped or poorly typed throughout
- You're willing to maintain comprehensive type definitions for the entire module
- The library is stable and its API won't change frequently
**When to avoid stubs:**
- The library is mostly well-typed with only a few problematic spots
- You only need to fix one or two specific functions
- The library is under active development with frequent API changes
**Alternatives to stubs:**
1. **Wrapper functions**: Create a typed wrapper around the problematic function, isolating the type issue to one place
2. **Local type narrowing**: Use `assert isinstance()` or `cast()` to narrow types where needed
3. **Targeted ignores**: Use `# type: ignore[specific-error]` with a comment explaining why (see below)
4. **Upstream contribution**: If the library is actively maintained, consider contributing type hints directly
## Example

> **Anti-pattern: Creating a stub for one issue**
> ```python
> # some_library.pyi - creates a stub to fix one return type
> def process(x: int) -> str: ...  # Fixed: was returning Any
>
> # Now you've overridden ALL type info from some_library
> # Any other functions, classes, or constants in some_library
> # are now completely untyped unless you duplicate them in the stub
> ```


> **Better: Use a typed wrapper**
> ```python
> # my_wrappers.py
> from some_library import process as _process
> from typing import cast
>
> def process(x: int) -> str:
>     """Typed wrapper for some_library.process."""
>     return cast(str, _process(x))
>
> # Rest of your code uses this wrapper
> # The library's other type hints remain intact
> ```

# Isolate Type Workarounds
Type casts and `# type: ignore` comments are sometimes necessary when dealing with dynamic code, poorly-typed libraries, or limitations in the type checker. Like any repeated implementation detail, these workarounds should follow the DRY principle: Don't Repeat Yourself.
When you find yourself using the same cast or ignore in multiple places, it's a sign that you should create a wrapper. This centralizes the workaround, making it easier to maintain and remove when the underlying issue is fixed.
**Benefits of isolation:**
- **Single source of truth**: When the upstream library adds proper types or you find a better solution, you only update one place
- **Clearer intent**: The wrapper's type signature documents what you expect, even if the underlying function doesn't
- **Easier auditing**: All type workarounds are in dedicated wrapper functions, not scattered through the codebase
## Example

> **Anti-pattern: Repeated casts**
> ```python
> # In file1.py
> result = cast(list[str], external_lib.get_items(user_id))
>
> # In file2.py
> items = cast(list[str], external_lib.get_items(user_id))
>
> # In file3.py
> data = cast(list[str], external_lib.get_items(user_id))
> ```


> **Better: Wrapper function**
> ```python
> # lib_wrappers.py
> from typing import cast
> import external_lib
>
> def get_items(user_id: int) -> list[str]:
>     """
>     Typed wrapper for external_lib.get_items.
>
>     The library returns list[Any], but we know it's always list[str].
>     If the library adds proper types, we can remove this wrapper.
>     """
>     return cast(list[str], external_lib.get_items(user_id))
>
> # Now all call sites are clean and type-safe
> result = get_items(user_id)
> items = get_items(user_id)
> data = get_items(user_id)
> ```

The same principle applies to `# type: ignore` comments. If you're ignoring the same error in multiple places for the same underlying reason, create a wrapper that encapsulates both the operation and the ignore.
# Narrow Through Inheritance Hierarchy
When working with poorly-typed base classes, using `getattr` or `hasattr` to access attributes is a common workaround. However, this bypasses the type system entirely and produces hard-to-read code. A cleaner approach is to narrow to a more specific subclass that has the attributes properly typed.
Many class hierarchies define attributes at different levels. The base class may be abstract or loosely typed, while concrete subclasses have specific, well-typed attributes. By checking `isinstance` against the right subclass, you get proper type safety without any workarounds.
## Example

> **Anti-pattern: Using getattr to access untyped attributes**
> ```python
> from langchain_core.prompts.message import BaseMessagePromptTemplate
>
> def extract_template(message: BaseMessagePromptTemplate) -> str | None:
>     # Hacky: getattr bypasses type system
>     prompt = getattr(message, 'prompt', None)
>     if prompt is not None:
>         template = getattr(prompt, 'template', None)
>         if isinstance(template, str):
>             return template
>     return None
> ```


> **Better: Narrow to a subclass with typed attributes**
> ```python
> from langchain_core.prompts import PromptTemplate
> from langchain_core.prompts.chat import BaseStringMessagePromptTemplate
> from langchain_core.prompts.message import BaseMessagePromptTemplate
>
> def extract_template(message: BaseMessagePromptTemplate) -> str | None:
>     # BaseStringMessagePromptTemplate has .prompt properly typed
>     if not isinstance(message, BaseStringMessagePromptTemplate):
>         return None
>
>     # Now .prompt is typed as StringPromptTemplate
>     if isinstance(message.prompt, PromptTemplate):
>         return message.prompt.template
>
>     return None
> ```

**Why this works.** In this LangChain example:
- `BaseMessagePromptTemplate` (base) — no `.prompt` attribute in its type definition
- `BaseStringMessagePromptTemplate` (subclass) — has `.prompt: StringPromptTemplate` properly typed
- `PromptTemplate` (concrete) — has `.template: str` properly typed
By narrowing to `BaseStringMessagePromptTemplate`, the type checker knows about `.prompt`. By further narrowing `.prompt` to `PromptTemplate`, we get `.template` with proper typing.
This approach is superior to `getattr` because the type checker validates your attribute access, IDE autocomplete works correctly, refactoring tools can track usages, and the code is more readable and self-documenting.
# Minimize and Specify Type Ignores
The `# type: ignore` comment is a last resort. It tells the type checker to stop checking a line, which defeats the entire purpose of type checking. However, there are legitimate cases where it's necessary: dynamic attribute access, intentional duck typing, or working around type checker limitations.
When you must use `# type: ignore`, follow these guidelines:
**1. Be specific.** Use `# type: ignore[error-code]` rather than a blanket `# type: ignore`. This ensures you're only suppressing the specific error you expect, not hiding unrelated type issues.
```python
# Bad: Suppresses all errors
result = obj.dynamic_attr  # type: ignore

# Good: Suppresses only the attr-defined error
result = obj.dynamic_attr  # type: ignore[attr-defined]
```
**2. Explain why.** Add a comment explaining why the ignore is necessary and what would need to change to remove it.
```python
# Library doesn't export this type; safe to ignore until they do
from private_lib import _InternalType  # type: ignore[attr-defined]
```
**3. Isolate to a wrapper if repeated.** If you're using the same ignore in multiple places, create a wrapper function (see previous section).
**4. Prefer alternatives.** Before reaching for `# type: ignore`, consider: can you use `cast()` to assert the type you expect? Can you use `assert isinstance()` to narrow the type? Can you restructure the code to avoid the type issue? Can you use a protocol or TypedDict to describe the interface?
# Use Generic Types
Generic types allow you to write code that works with different types while preserving type safety. When you parameterize a container or function with a type variable, the type checker can track how types flow through your code.
**Prefer specific generic types over `Any`:**
```python
# Bad: Lost type information
def process_items(items: list) -> list:
    return [item.upper() for item in items]

# Also bad: Type info is "anything"
def process_items(items: list[Any]) -> list[Any]:
    return [item.upper() for item in items]

# Good: Preserves type information
def process_items(items: list[str]) -> list[str]:
    return [item.upper() for item in items]
```
**Use type parameters for generic functions.** Use the inline type parameter syntax `[T]` directly in the function definition (Python 3.12+). This eliminates the need for separate `TypeVar` declarations:
```python
def first_or_none[T](items: list[T]) -> T | None:
    """Return first item or None if empty."""
    return items[0] if items else None

# Type checker knows the return type matches the input
numbers: list[int] = [1, 2, 3]
first_num = first_or_none(numbers)  # Type: int | None

strings: list[str] = ["a", "b"]
first_str = first_or_none(strings)  # Type: str | None
```
**Do not use the old `TypeVar` syntax:**
```python
# Bad: Old pre-3.12 syntax
from typing import TypeVar

T = TypeVar('T')

def first_or_none(items: list[T]) -> T | None:
    return items[0] if items else None
```
Using generics appropriately allows the type checker to help you catch errors like passing the wrong type to a function or accessing attributes that don't exist.
# Let Type Inference Work
Modern type checkers are sophisticated. They can infer types from context, from return values, from assignments. You don't need to annotate everything — in fact, over-annotation creates noise and maintenance burden.
**Don't annotate when the type is obvious:**
```python
# Bad: Redundant annotation
name: str = "Alice"
count: int = 42
items: list[str] = ["a", "b", "c"]

# Good: Let inference work
name = "Alice"
count = 42
items = ["a", "b", "c"]
```
**Do annotate function parameters.** Function boundaries are where type information enters your code. Parameters should always be annotated — inference doesn't cross function boundaries for parameters.
```python
# Bad: No parameter types
def process_user(user_id, name):
    return f"User {user_id}: {name}"

# Good: Parameters annotated
def process_user(user_id: int, name: str) -> str:
    return f"User {user_id}: {name}"
```
**Return type annotations are often valuable even when inferable.** While type checkers can infer return types, explicit annotations serve as documentation and as a contract. They catch errors where you intended to return one type but accidentally return another.
**Use annotations for empty collections.** When you initialize an empty collection, the type checker can't infer what you'll put in it later. Annotate these.
```python
# Bad: Checker doesn't know element type
results = []

# Good: Element type specified
results: list[Result] = []
```
The goal is to provide enough type information for the checker to help you, without cluttering your code with redundant annotations.
# Use Modern Type Alias Syntax
Python 3.12 introduced the `type` keyword for creating type aliases. This is now the preferred way to define type aliases, replacing the older approaches.
```python
# Old style (pre-3.12)
from typing import TypeAlias
UserId = int  # Ambiguous: is this a type alias or a variable?
UserDict: TypeAlias = dict[str, Any]  # Explicit but verbose

# New style (Python 3.12+)
type UserId = int
type UserDict = dict[str, Any]
type ResultList[T] = list[Result[T]]  # Generic type alias
```
The `type` keyword makes it clear this is a type alias, not a variable assignment; tools can distinguish type aliases from regular assignments; generic type aliases are supported naturally; and it's the direction Python's type system is moving. Use it for all new type aliases.
# Summary
1. **Fixed-key data belongs in structured types** — Use dataclasses, TypedDict, or pydantic models for data with known keys; reserve dicts for truly dynamic maps.
2. **Stub files are all-or-nothing** — Only create stubs for thoroughly untyped libraries; use wrappers for targeted fixes.
3. **Isolate type workarounds** — The DRY principle applies to casts and ignores; centralize workarounds in wrapper functions.
4. **Narrow through inheritance hierarchy** — Use `isinstance` to narrow to subclasses with typed attributes instead of `getattr`/`hasattr`.
5. **Minimize and specify type ignores** — Use `# type: ignore[error-code]` with explanations; prefer alternatives when possible.
6. **Use generic types** — Prefer `list[T]` over `list` or `list[Any]`; use type parameters to preserve type information.
7. **Let type inference work** — Don't annotate when types are obvious; always annotate function parameters.
8. **Use modern type alias syntax** — Prefer the `type` keyword for explicitness and better tooling support.
The goal of type checking is not to make the type checker happy — it's to catch real bugs and make your code easier to understand and maintain. When you encounter a type error, the fix should make the code genuinely better, not just quieter.
# FAQ
## When is a plain `dict` actually the right choice?
When the keys are determined at runtime and not known at design time — a uniform map like a cache of user IDs to users, or a word-frequency counter. If you know the set of keys at design time, it's fixed-key data and belongs in a structured type (dataclass, TypedDict, or pydantic model).
## TypedDict vs dataclass vs pydantic — which do I reach for?
**TypedDict** when you need dict semantics or are interfacing with JSON. **Dataclass** as a good default (standard library, immutable via `frozen=True`). **Pydantic** at API boundaries and for configuration, where you want runtime validation and serialization.
## A library has one wrong return type. Should I write a `.pyi` stub to fix it?
No. A stub is all-or-nothing — it overrides ALL of the library's type hints for that module, so you'd have to duplicate the entire interface to fix one function. Write a typed wrapper instead (or use local narrowing / a targeted `# type: ignore[error-code]`). Reserve stubs for libraries that are untyped throughout, stable, and that you're willing to fully maintain.
## Why prefer narrowing to a subclass over `getattr`/`hasattr`?
`getattr`/`hasattr` bypass the type system entirely and produce hard-to-read code. Narrowing with `isinstance` to a subclass that has the attribute properly typed gives you checker-validated attribute access, working autocomplete, refactoring support, and more self-documenting code.
## Should I annotate everything?
No. Let inference handle the obvious (`name = "Alice"`, not `name: str = "Alice"`). Always annotate function parameters — inference doesn't cross function boundaries. Annotate return types too: they're inferable but serve as documentation and a contract. And always annotate empty collections (`results: list[Result] = []`), since the checker can't infer what you'll put in them.