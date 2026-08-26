# lib.nut - the modules the-whole-shebang provides.
#
# One module per line: the name a `use` writes, then the file.
# Read before any module is loaded, so it stays a format that needs
# no parser: the TOML one is itself a module.

diagnostics              libs/diagnostics.sh
tui::confirm             libs/tui/confirm.sh
tui::frame               libs/tui/frame.sh
tui::key                 libs/tui/key.sh
tui::layout              libs/tui/layout.sh
tui::menu                libs/tui/menu.sh
tui::menu::draw          libs/tui/menu/draw.sh
tui::menu::view          libs/tui/menu/view.sh
tui::modal               libs/tui/modal.sh
tui::plan                libs/tui/plan.sh
tui::progress            libs/tui/progress.sh
tui::report              libs/tui/report.sh
tui::run                 libs/tui/run.sh
tui::table               libs/tui/table.sh
tui::term                libs/tui/term.sh
