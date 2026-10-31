# Flash Rename

Rename a Studio selection with numbered templates, a preview and sibling-name checks.

## Install

1. Download this repository as a ZIP and extract it. No package installation is needed to use the plugin.
2. Open a separate Studio test place in edit mode. Use Explorer's **Insert from File** action to insert `FlashRename.rbxmx`.
3. The imported root is a Script named `FlashRename` with four child ModuleScripts. Select that root and choose **Save as Local Plugin**.
4. Remove the imported root from the place after saving the plugin. Open **Flash Rename → Rename** on the Plugins toolbar.

Changes happen only after Preview and Apply. Selection or option edits clear the preview. Apply is refused during a play test. A successful batch uses one Studio undo recording. If a write fails, the plugin asks Studio to cancel the batch. Start on a copy of your place and verify Undo and Redo before using it on important work.

## Use it

Select objects in Explorer. Set a template, first number and minimum number of digits. Preview, review every proposed name, then apply.

| Template | Example result |
| --- | --- |
| `Tree_{n}`, start 1, digits 3 | `Tree_001`, `Tree_002` |
| `{name}_LOD` | `Rock_LOD` |
| `Prop_{n}_{name}`, start 20, digits 2 | `Prop_20_Rock` |

The order is full path, compared case-sensitively. Equal paths keep the order returned by Studio's selection snapshot; the preview shows the actual order. This is not a natural-number sort. Numbers are assigned before unchanged rows are omitted.

## Limits

- Select 1–500 objects inside services. Services themselves are refused. Descendants are not expanded.
- Only `{name}` and `{n}` are recognized. Literal braces and other tokens are refused. Old names are inserted literally, including percent signs and braces.
- Resulting names must contain non-whitespace text, be valid UTF-8, contain no control characters, and fit in 100 bytes. This is the tool's limit.
- First number: 0–1,000,000; the last number may not exceed 1,000,000. Padding: 1–6 digits (a minimum width).
- A proposed name cannot match another child's final name under the same parent. Separate parents can use the same name. The sibling scan is capped at 10,000 children across selected parents.
- Apply rechecks names, parents and sibling collisions. Renaming a parent may affect paths referenced elsewhere. **Script strings and external references are not rewritten.**

## Code

`Rules.plan(rows, siblings, options)` accepts plain object records and `{template, start, padding}`. It returns changed names or raises an error for an invalid batch. `Adapter` reads the selection and siblings, rechecks the preview, and writes the `Name` property.

## Development and tests

The source is in `src`. There are no runtime dependencies, network requests or external assets. `Ui` creates a dock panel using Studio's theme. `Transaction` handles preflight checks and undo recordings; it does not create its own undo stack. These two modules are shared with the other Flash editing plugins, with a copy in each repository so each plugin can be installed on its own.

Rebuild after changing source (Python 3.11+):

```sh
python build.py
python -m unittest discover -s tests -v
```

Rule, adapter and transaction checks use Lune 0.11.1:

```sh
lune run tests/run
```

The tests compile every source file, exercise the real planner and adapter with fake Studio objects, and check commit/cancel behavior with a fake history service. Packaging tests compare the XML plugin against its source. GitHub Actions runs both sets of checks. The CI job installs Lune on its runner, not on your computer.

**Automated tests do not verify the dock widget, plugin installation, real constraints or Studio's undo engine.** See [Studio checks](docs/STUDIO-CHECKS.md) for the manual checklist. No live Studio pass is claimed here.

See Roblox's [plugin guide](https://create.roblox.com/docs/studio/plugins) and [ChangeHistoryService reference](https://create.roblox.com/docs/reference/engine/classes/ChangeHistoryService). MIT licensed; see [LICENSE](LICENSE).
