# 3md for VS Code

Syntax highlighting for the [3md](https://github.com/CorvidLabs/3md) format:
Markdown extended along a single free Z axis, where a document is a stack of
**planes** and each plane is ordinary Markdown.

This extension is **highlighting only**. It does not bundle a preview/webview
or a language server.

## What it highlights

- **Frontmatter block** - the opening and closing `---` fences, `key: value`
  pairs (with `3md`, `axis`, and `title` recognized as control keys), values,
  and `#` comment lines inside the block.
- **`@plane` directives** - the `@plane` keyword, attribute names
  (`z`, `x`, `y`, `label`, and any custom `key=`), the `=` separator, quoted
  string values, and numeric values for `z`/`x`/`y`.
- **Cross-plane links** - `[[z=N]]` and `[[z=N|text]]`, including the `z=`
  target, the number, the optional `|`, and the link text.
- **Plane bodies** - rendered with the bundled Markdown grammar, so headings,
  lists, emphasis, inline code, and fenced code blocks all highlight for free.

## Install from a `.vsix`

Build the prepared 2.0.0 package (see below), then:

```sh
code --install-extension threemd-2.0.0.vsix
```

This version alignment does not add binary/composition editing, a preview or a
language server. No Marketplace publication or prebuilt 2.0.0 VSIX is claimed.
See the [release guide](../../docs/RELEASE-2.0.0.md).

## Development

This extension uses [Bun](https://bun.sh) for tooling.

```sh
bun install        # install dev dependencies
bun run test       # run the headless TextMate grammar tests
bun run package    # build a .vsix with @vscode/vsce
```

The grammar tests use `vscode-tmgrammar-test` with scope assertions in
`tests/*.3md`. They run headlessly and require no editor.

## License

MIT
