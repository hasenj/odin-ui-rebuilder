// SheenBidi 3.0.0 C ABI. Build the vendored source with scripts/build-text-deps.sh.
package native

foreign import sheenbidi "system:sheenbidi"

SB_Algorithm :: distinct rawptr
SB_Paragraph :: distinct rawptr
SB_Line :: distinct rawptr
SB_Script_Locator :: distinct rawptr
SB_Sequence :: struct {encoding: u32, buffer: rawptr, length: uintptr}
SB_Run :: struct {offset, length: uintptr, level: u8}
SB_Script_Agent :: struct {offset, length: uintptr, script: u8}

@(default_calling_convention="c")
foreign sheenbidi {
	SBAlgorithmCreate :: proc(sequence: ^SB_Sequence) -> SB_Algorithm ---
	SBAlgorithmRelease :: proc(algorithm: SB_Algorithm) ---
	SBAlgorithmCreateParagraph :: proc(algorithm: SB_Algorithm, offset, length: uintptr, level: u8) -> SB_Paragraph ---
	SBParagraphRelease :: proc(paragraph: SB_Paragraph) ---
	SBParagraphGetLength :: proc(paragraph: SB_Paragraph) -> uintptr ---
	SBParagraphCreateLine :: proc(paragraph: SB_Paragraph, offset, length: uintptr) -> SB_Line ---
	SBLineRelease :: proc(line: SB_Line) ---
	SBLineGetRunCount :: proc(line: SB_Line) -> uintptr ---
	SBLineGetRunsPtr :: proc(line: SB_Line) -> [^]SB_Run ---
	SBScriptLocatorCreate :: proc() -> SB_Script_Locator ---
	SBScriptLocatorRelease :: proc(locator: SB_Script_Locator) ---
	SBScriptLocatorLoadCodepoints :: proc(locator: SB_Script_Locator, sequence: ^SB_Sequence) ---
	SBScriptLocatorMoveNext :: proc(locator: SB_Script_Locator) -> u8 ---
	SBScriptLocatorGetAgent :: proc(locator: SB_Script_Locator) -> ^SB_Script_Agent ---
	SBScriptGetUnicodeTag :: proc(script: u8) -> u32 ---
}

when size_of(rawptr) == 8 {
	#assert(size_of(SB_Sequence) == 24 && offset_of(SB_Sequence, buffer) == 8)
	#assert(size_of(SB_Run) == 24 && offset_of(SB_Run, level) == 16)
	#assert(size_of(SB_Script_Agent) == 24 && offset_of(SB_Script_Agent, script) == 16)
}
