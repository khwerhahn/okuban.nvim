# Changelog

## [0.2.1](https://github.com/khwerhahn/okuban.nvim/compare/v0.2.0...v0.2.1) (2026-05-14)


### Bug Fixes

* **ui:** always include Unsorted column when show_unsorted=true (Fixes [#158](https://github.com/khwerhahn/okuban.nvim/issues/158)) ([#159](https://github.com/khwerhahn/okuban.nvim/issues/159)) ([85d8863](https://github.com/khwerhahn/okuban.nvim/commit/85d886335dc8d6893cc4d45db05bc382404c546f))
* **ui:** drop leaf sub-issues + auto-fetch missing parents (Fixes [#160](https://github.com/khwerhahn/okuban.nvim/issues/160)) ([#161](https://github.com/khwerhahn/okuban.nvim/issues/161)) ([a58e6e5](https://github.com/khwerhahn/okuban.nvim/commit/a58e6e5eb0191dcaa781303e83b00db3dcd496c3))

## [0.2.0](https://github.com/khwerhahn/okuban.nvim/compare/v0.1.0...v0.2.0) (2026-05-05)


### Features

* **api:** add configurable issue sorting by last updated ([#148](https://github.com/khwerhahn/okuban.nvim/issues/148)) ([222ae9a](https://github.com/khwerhahn/okuban.nvim/commit/222ae9a74df95b22d94b74bee04461bb8d29c603))
* **labels:** filter sub-issues from board in label mode (Fixes [#152](https://github.com/khwerhahn/okuban.nvim/issues/152)) ([#153](https://github.com/khwerhahn/okuban.nvim/issues/153)) ([6bfb630](https://github.com/khwerhahn/okuban.nvim/commit/6bfb630d6d883c76a777f682188b8825330f9bde))
* **tmux:** open okuban board as tmux display-popup overlay ([#151](https://github.com/khwerhahn/okuban.nvim/issues/151)) ([cecd1ff](https://github.com/khwerhahn/okuban.nvim/commit/cecd1ffb74f0bf692e36783b3cb0983ad57fec1a))


### Bug Fixes

* **tmux:** pass -d cwd to display-popup so popup nvim inherits it (Fixes [#156](https://github.com/khwerhahn/okuban.nvim/issues/156)) ([#157](https://github.com/khwerhahn/okuban.nvim/issues/157)) ([500314f](https://github.com/khwerhahn/okuban.nvim/commit/500314fa8131fdc660c76e2ab44d75f1667dcfc8))
* **ui:** eliminate sub-issue flicker on board open ([#155](https://github.com/khwerhahn/okuban.nvim/issues/155)) ([340c16b](https://github.com/khwerhahn/okuban.nvim/commit/340c16b108dac51a9c87391e9f71fe55548100a6))
