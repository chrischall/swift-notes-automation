# Changelog

## [1.3.1](https://github.com/chrischall/swift-notes-automation/compare/v1.3.0...v1.3.1) (2026-07-19)


### Documentation

* replace duplicated fleet policy with a pointer ([#40](https://github.com/chrischall/swift-notes-automation/issues/40)) ([978e0fb](https://github.com/chrischall/swift-notes-automation/commit/978e0fb44abe7853065f4a377fa9639896502ad9))

## [1.3.0](https://github.com/chrischall/swift-notes-automation/compare/v1.2.5...v1.3.0) (2026-07-13)


### Features

* add full-body get, update, folder listing, and pagination ([#38](https://github.com/chrischall/swift-notes-automation/issues/38)) ([0832139](https://github.com/chrischall/swift-notes-automation/commit/0832139910e44fc99a50107310da4b3bf3ca2358))

## [1.2.5](https://github.com/chrischall/swift-notes-automation/compare/v1.2.4...v1.2.5) (2026-07-13)


### Documentation

* fix stale AppleScript-escaping docs after backslash fix ([#36](https://github.com/chrischall/swift-notes-automation/issues/36)) ([a5088fd](https://github.com/chrischall/swift-notes-automation/commit/a5088fd8efb2ff7486be5c0b6b0e1f7cf843d2bc))

## [1.2.4](https://github.com/chrischall/swift-notes-automation/compare/v1.2.3...v1.2.4) (2026-07-08)


### Bug Fixes

* **security:** escape backslashes in AppleScript to prevent injection ([#31](https://github.com/chrischall/swift-notes-automation/issues/31)) ([390aba6](https://github.com/chrischall/swift-notes-automation/commit/390aba6d91fc69d9161a5eb9a0e5803f442fd1cf))

## [1.2.3](https://github.com/chrischall/swift-notes-automation/compare/v1.2.2...v1.2.3) (2026-06-15)


### Documentation

* correct release flow and add auto-review follow-up convention ([#29](https://github.com/chrischall/swift-notes-automation/issues/29)) ([d5b3a61](https://github.com/chrischall/swift-notes-automation/commit/d5b3a610bd121daf3a877a19f85ed8990bdaa319))
* require Conventional Commit PR titles; correct squash-merge guidance ([#27](https://github.com/chrischall/swift-notes-automation/issues/27)) ([0727e4b](https://github.com/chrischall/swift-notes-automation/commit/0727e4b9c87e1a578d7cd4d2cb5391d33a5ede09))

## [1.2.2](https://github.com/chrischall/swift-notes-automation/compare/v1.2.1...v1.2.2) (2026-06-13)


### Documentation

* add license badge to README ([#21](https://github.com/chrischall/swift-notes-automation/issues/21)) ([8863d17](https://github.com/chrischall/swift-notes-automation/commit/8863d17247026c4b98ced9f0876f30fad95c0f6f))

## [1.2.1](https://github.com/chrischall/swift-notes-automation/compare/v1.2.0...v1.2.1) (2026-05-29)


### Bug Fixes

* **ci:** auto-merge arm guards ([#19](https://github.com/chrischall/swift-notes-automation/issues/19)) ([83fd35d](https://github.com/chrischall/swift-notes-automation/commit/83fd35d36b722eaa18ee0e91f2a9c4966669cd96))
* **ci:** switch auto-merge to squash and label-gated design ([#14](https://github.com/chrischall/swift-notes-automation/issues/14)) ([fb2d222](https://github.com/chrischall/swift-notes-automation/commit/fb2d222603bb9e7fcc24d26c9c4aa02bbf44f7c7))

## [1.2.0](https://github.com/chrischall/swift-notes-automation/compare/v1.1.3...v1.2.0) (2026-05-25)


### Features

* add delete(id:) to NoteService ([008bc08](https://github.com/chrischall/swift-notes-automation/commit/008bc0871d1368b4edaa358f86d4f2bbdf6ef68a))
* NoteStoreReader — fast read-only SQLite path alongside AppleScript ([04d7cef](https://github.com/chrischall/swift-notes-automation/commit/04d7cef747f162f99a9da1df64571276537e6d5d))


### Bug Fixes

* **ci:** prevent labeled event from cancelling auto-review ([#15](https://github.com/chrischall/swift-notes-automation/issues/15)) ([493de93](https://github.com/chrischall/swift-notes-automation/commit/493de9388c049042684a7cad7de3677234a51b92))
* **reader:** open a fresh SQLite handle per query ([0ee83b1](https://github.com/chrischall/swift-notes-automation/commit/0ee83b1d3854a93e48c836b810dd32184cc26e50))
* **reader:** refresh snapshots between queries + exclude trash folder ([c8b1640](https://github.com/chrischall/swift-notes-automation/commit/c8b1640a3f0b0959304444fb81d1304dd0489ca8))


### Documentation

* ensure CLAUDE.md is current and complete ([9c31156](https://github.com/chrischall/swift-notes-automation/commit/9c31156ad1a744ef14684868b3ca1761391c209c))
* ensure CLAUDE.md is current and complete ([da409c0](https://github.com/chrischall/swift-notes-automation/commit/da409c0319d7b4348f86db3d2c9c800c43d73cad))
