# @macwlt/cli

TypeScript CLI for the macwlt native core.

## Install

The npm package currently supports Apple silicon Macs and requires Bun 1.2 or
newer:

```shell
pnpm add --global @macwlt/cli
macwlt help
```

The package includes `libmacwlt.dylib`, the signing-service XPC bundle, and the
signing service's native dependency. `MACWLT_LIB` can still override the bundled
library path for development.

## Publish

Build and sign the native artifacts before publishing:

```shell
make build CODESIGN_IDENTITY="Developer ID Application: Example (TEAMID)"
pnpm --filter @macwlt/cli publish --access public
```

The `prepack` lifecycle builds the TypeScript entry points and stages the native
artifacts from the repository's `build/` directory. The publish lifecycle also
runs the CLI typecheck and unit tests.
