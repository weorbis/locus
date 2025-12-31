# Documentation

This directory contains documentation for the Locus package.

## Contents

| File                                 | Description                                   |
| ------------------------------------ | --------------------------------------------- |
| [CONTRIBUTING.md](./CONTRIBUTING.md) | Guidelines for contributing to the project    |
| [SECURITY.md](./SECURITY.md)         | Security policy and vulnerability reporting   |
| [LICENSING.md](./LICENSING.md)       | Detailed licensing information                |
| `api/`                               | Auto-generated API documentation (gitignored) |

## API Documentation

To regenerate the API documentation:

```bash
dart doc --output doc/api
```

Then open `doc/api/index.html` in a browser.

> **Note:** The `api/` directory is gitignored as it can be regenerated.

## See Also

- **README.md** (project root) - Main package documentation
- **CHANGELOG.md** (project root) - Version history
- **example/** - Example application demonstrating usage
