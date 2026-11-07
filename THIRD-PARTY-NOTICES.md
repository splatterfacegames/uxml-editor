# Third-Party Notices

UXML Editor is Apache-2.0 licensed. The following components are
redistributed in this repository or in its builds.

## godot-uxml (Apache-2.0)

`addons/godot_uxml/` is an unmodified copy of
[jethac/godot-uxml](https://github.com/jethac/godot-uxml) at the commit in
`godot-uxml.pin`. The addon carries its own notices in
`addons/godot_uxml/THIRD-PARTY-NOTICES.md` and license texts in
`addons/godot_uxml/licenses/`:

- uxml-preview (Apache-2.0): the godot-uxml parser and cascade are ports of
  ReuHomi/uxml-preview v0.5.0.
- Inter 3.009 (SIL Open Font License 1.1): the default theme font.
- godot-rust (MPL-2.0): linked into the native core binary
  `addons/godot_uxml/bin/godot_uxml_native.windows.x86_64.dll`.

`tests/fixtures/godot-uxml-parity/` holds the UXML and USS parity cases of
the same godot-uxml commit (Apache-2.0), used as round-trip fixtures.

## Godot Engine (MIT)

Exported builds of the editor contain the Godot Engine runtime,
Copyright (c) 2014-present Godot Engine contributors, Copyright (c)
2007-2014 Juan Linietsky, Ariel Manzur. MIT license:
https://godotengine.org/license. Godot's own third-party notices apply to
the runtime: https://github.com/godotengine/godot/blob/master/COPYRIGHT.txt.

## Port of the TypeScript editor

`src/core/` ports the source-backed editing core of this repository's
previous TypeScript editor (`main` branch, same license). The span parsers
follow the grammar of godot-uxml `core/uxml_parser.gd` and
`core/uss_parser.gd`.

## Unity

Unity and UI Toolkit are trademarks of Unity Technologies. This project is
not affiliated with Unity. No Unity source, stylesheet, icon or asset is
included; the editor does not copy Unity UI Builder code or assets.
