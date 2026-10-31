# Ideas

Welcome to the idea graveyard.

This document contains potential features, design thoughts, questions, and interesting things that might eventually make their way into `todo`.

**Nothing in this document is a commitment.**

Ideas can be added, changed, abandoned, or deleted. That's what makes this document different from `DECISIONS.md`.

---

## Language design

### Syntax and ergonomics

- Simple, readable, brace-based syntax.
- Avoid whitespace-sensitive syntax.
- Minimize unnecessary boilerplate.
- Support expressive APIs and builder patterns.
- Prefer consistency over introducing special syntax for every situation.

### Type system

- Explore static typing.
- Explicit nullable types, potentially using `String?`.
- Avoid implicit structural interface implementation.
- Explicit interface implementation, potentially using `impl Interface for Type`.
- Tagged unions and composition instead of class inheritance.
- Convenient error propagation, potentially using `?`.
- Strong compile-time guarantees without excessive complexity.

### Functions and data structures

- Structs with methods.
- Composition rather than inheritance.
- Named types that communicate their purpose.
- Explore convenient collection and iteration APIs.

---

## Modules and packages

- Packages should potentially span multiple source files.
- File and directory organization should not necessarily dictate logical namespaces.
- Explore explicit import syntax.
- Investigate package visibility conventions.
- Consider underscore-prefixed declarations as conventionally internal but still accessible.
- Eventually investigate dependency management and package distribution.

---

## Standard library

- Thoughtfully designed collection APIs.
- String manipulation and formatting.
- Filesystem and file I/O.
- JSON parsing and serialization.
- Networking.
- Useful error handling utilities.
- Date and time functionality.
- Testing utilities.

The standard library should prioritize good APIs and practical functionality over having the largest possible collection of features. One obvious way to do something makes understanding simpler.

---

## Runtime and memory management

- Explore garbage collection.
- Investigate allocator strategies.
- Consider how runtime values should be represented.
- Investigate object and value lifetime management.
- Keep runtime implementation details out of the language design where possible.

---

## Developer experience

- Helpful compiler and runtime diagnostics.
- Clear source locations in error messages.
- A pleasant command-line experience.
- Eventually provide language server support.
- Consider formatter and editor tooling.

---

## Reusable libraries

### Generic lexer library

Explore building a reusable Zig library for lexical analysis.

Potential design:

- Language-agnostic lexeme types.
- Generic words, integer literals, decimal literals, strings, and punctuation.
- Source spans and position tracking.
- Consumers translate generic lexemes into their own language-specific tokens.
- Avoid embedding language-specific keywords or grammar into the library.

Potential API concept:

```zig
const Lexeme = union(enum) {
    word: []const u8,
    integer: IntegerLiteral,
    decimal: DecimalLiteral,
    string: []const u8,
    comma,
    plus,
    left_paren,
    right_paren,
};
```

This library could initially be developed alongside `todo` and extracted into its own project if it proves reusable.

---

## Open questions

Questions worth revisiting when the relevant implementation work begins:

- Should the language eventually be statically typed?
- What should the module and package model look like?
- How should imports work?
- What should the standard library's organization be?
- Should the language support garbage collection?
- Should compilation to native code eventually be explored?
- How should dependencies be distributed?

---

## Abandoned ideas

Ideas that have been explicitly considered and discarded can go here if remembering why they were abandoned would be useful.

For now, the graveyard is empty. Let's try to keep it that way.
