# emacs-tree-sitter <img src="doc/static/img/emacs-tree-sitter-96x96.png" align="left">
[![Documentation](https://img.shields.io/badge/documentation-latest-blue)](https://ubolonton.github.io/emacs-tree-sitter/)
[![Build Status](https://dev.azure.com/ubolonton/emacs-tree-sitter/_apis/build/status/ci?branchName=master&label=build&api-version=6.0-preview.1)](https://dev.azure.com/ubolonton/emacs-tree-sitter/_build/latest?definitionId=2&branchName=master)

This is an Emacs Lisp binding for [tree-sitter](https://tree-sitter.github.io/tree-sitter/), an incremental parsing library. It requires Emacs 25.1 or above, built with dynamic module support.

It aims to be the foundation for a new breed of Emacs packages that understand code structurally. For example:
- Faster, fine-grained code highlighting.
- More flexible code folding.
- Structural editing (like Paredit, or even better) for non-Lisp code.
- More informative indexing for imenu.

The author of tree-sitter articulated its merits a lot better in this [Strange Loop talk](https://www.thestrangeloop.com/2018/tree-sitter---a-new-parsing-system-for-programming-tools.html).

## Installation

See the [installation section](https://ubolonton.github.io/emacs-tree-sitter/installation/) in the documentation.

If you want to hack on `emacs-tree-sitter` itself, see the next section instead.

## Setup for Development

- Clone this repo with the `--recursive` flag.
- Add 3 of its directories to `load-path`: `core/`, `lisp/` and `langs/`.
- Install [cask](https://cask.readthedocs.io).
- Run `./bin/setup` (`.\bin\setup` on Windows).
- Nix: run `nix-shell` in develop mode or`nix-shell --command "setup"` to initialize the environment

If you want to hack on the high-level features (in Lisp) only:
- Make changes to the `.el` files.
- Add tests to `tree-sitter-tests.el` and run them with `./bin/test` (`.\bin\test` on Windows).

If you want to build additional (or all) grammars from source, or work on the core dynamic module, see the next 2 sections.

### Building grammars from source

- Install [tree-sitter CLI tool](https://tree-sitter.github.io/tree-sitter/creating-parsers#installation) (if you don't use NodeJS, you can download the binary directly from [GitHub](https://github.com/tree-sitter/tree-sitter/releases)):
    ```bash
    # For yarn user
    yarn global add tree-sitter-cli

    # For npm user
    npm install -g tree-sitter-cli
    ```
- Run:
    ```bash
    # macOS/Linux: make ensure/<lang-name>
    make ensure/rust
    ```
    ```powershell
    # Windows: .\bin\ensure-lang <lang-name>
    .\bin\ensure-lang rust
    ```
- You can modify`tree-sitter-langs-repos` if the language you need is not declared there.

### Working on the dynamic module

- Install the [Rust toolchain](https://rustup.rs/).
- Install `clang`, to generate the raw Rust binding for `emacs-module.h`.
- Build:
    ```bash
    # macOS/Linux
    make build
    ```
    ```powershell
    # Windows
    .\bin\build
    ```
- Test:
    ```bash
    # macOS/Linux
    make test
    ```
    ```powershell
    # Windows
    .\bin\test
    ```
- Continuously rebuild and test on change (requires [cargo-watch](https://github.com/passcod/cargo-watch)):
    ```bash
    # macOS/Linux
    make watch
    ```
    ```powershell
    # Windows
    .\bin\test watch
    ```

To test against a different version of Emacs, set the environment variable `EMACS` (e.g. `EMACS=/snap/bin/emacs make test`).

## Overall Plan

Targeting lib authors:
- Write a guide on using the tree-sitter APIs.

Targeting end users:
- Pick a language, make a "killer" minor mode that extends its major mode in multiple ways.
- Make minor modes for most common languages.
- Extract common patterns from the language minor modes into helper language-diagnostic minor modes.
- Get a language major mode to use tree-sitter for optional features.

## Alternative

Binding through C instead of Rust: https://github.com/karlotness/tree-sitter.el

## Contribution

Contributions are welcomed. Please take a look at the [issue list](https://github.com/ubolonton/emacs-tree-sitter/issues) for ideas, or [create a new issue](https://github.com/ubolonton/emacs-tree-sitter/issues/new) to describe any idea you have for improvement.

For language-specific issues/features, please check out [tree-sitter-langs](https://github.com/ubolonton/tree-sitter-langs) instead.

Show respect and empathy towards others. Both technical empathy and general empathy are highly valued.
