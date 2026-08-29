# lib.nut - the modules the-whole-shebang provides.
#
# One module per line: the name a `use` writes, then the file.
# Read before any module is loaded, so it stays a format that needs
# no parser: the TOML one is itself a module.

diagnostics::findings    libs/diagnostics/findings.sh
verify::digest           libs/verify/digest.sh
tui::confirm             libs/tui/confirm.sh
tui::frame               libs/tui/frame.sh
# Reads one keypress at a time from a terminal, with a timeout short enough to
# tell escape from the start of an escape sequence. That needs `read -n1 -d ''
# -t`, and POSIX `read` has none of the three: it reads a line, it splits on
# `IFS`, and it waits. There is no POSIX rewrite of this, only a different
# program built on `dd bs=1` and `stty`, which is a different module rather than
# this one converted.
#
# So it sits behind the gate rather than on the floor, which is what the third
# layer is for.
#[shell(bash4)]
tui::key                 libs/tui/key.sh
tui::layout              libs/tui/layout.sh
tui::menu                libs/tui/menu.sh
tui::menu::draw          libs/tui/menu/draw.sh    internal
tui::menu::view          libs/tui/menu/view.sh    internal
tui::modal               libs/tui/modal.sh
tui::plan                libs/tui/plan.sh
tui::progress            libs/tui/progress.sh
tui::report              libs/tui/report.sh
tui::run                 libs/tui/run.sh
tui::table               libs/tui/table.sh
tui::term                libs/tui/term.sh
