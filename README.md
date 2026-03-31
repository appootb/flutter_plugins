# flutter_plugins

A curated collection of modular Flutter plugins and UI components managed as a monorepo.

This repository uses [Melos](https://melos.invertase.dev/) to link local packages, run scripts across workspaces, and keep versioning consistent.

## Prerequisites

- [Flutter](https://docs.flutter.dev/get-started/install) (includes Dart)
- [Melos](https://melos.invertase.dev/getting-started):  
  `dart pub global activate melos`

Ensure `melos` is on your `PATH` (for example, add Pub’s `bin` directory to `PATH`).

## Quick start

From the repository root:

```sh
melos bootstrap
```

Bootstrap resolves dependencies for every package under `packages/` and wires local path dependencies via pubspec overrides.

Common commands:

```sh
melos list
melos exec -- dart analyze
```

## Layout

- `packages/` — individual Flutter/Dart packages (plugins, UI libraries, tools).

Add new packages under `packages/<your_package>/` with their own `pubspec.yaml`; Melos will pick them up automatically.

## License

See [LICENSE](LICENSE).
