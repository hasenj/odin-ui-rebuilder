// Original small default set. Other packages can return the same core glyph type.
package default_icons

import ui "../../core"

Set :: [Name]ui.Icon_Glyph

// Call once per window, during update. The tiny font is embedded so binaries do
// not depend on a working directory or an installed system icon font.
load :: proc() -> (Set, ui.Text_Error) {
	font, found := ui.find_font("Rebuilder.DefaultIcons")
	if !found {
		err: ui.Text_Error
		font, err = ui.load_font_bytes(#load("icons.ttf", []u8), "Rebuilder.DefaultIcons")
		if err != .None { return {}, err }
	}
	set: Set
	for codepoint, name in codepoints {
		glyph, err := ui.resolve_icon(font, codepoint)
		if err != .None { return {}, err }
		set[name] = glyph
	}
	return set, .None
}
