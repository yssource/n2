# n2, an alternative ninja implementation

![CI status](https://github.com/evmar/n2/actions/workflows/ci.yml/badge.svg)

n2 (pronounced "into") implements enough of [ninja](https://ninja-build.org/)
to successfully build some projects that build with ninja.

I wrote it to explore some alternative ideas I had around how to structure
a build system.

[Here's a small demo](https://asciinema.org/a/480446) of n2 building some of
Clang.

## More reading

- [Design notes](doc/design_notes.md).
- [Development tips](doc/development.md).

## Differences from Ninja

n2 is [missing many Ninja features](doc/missing.md).

n2 does some things Ninja doesn't:

- Builds start tasks as soon as an out of date one is found, rather than
  gathering all the out of date tasks before executing.
- Fancier status output, modeled after Bazel.
- `-d trace` generates a performance trace as used by Chrome's `about:tracing`
  or alternatives (speedscope, perfetto).
