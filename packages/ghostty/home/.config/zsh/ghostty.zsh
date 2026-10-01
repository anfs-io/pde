# ghostty

# Change terminal background color (OSC 11)
function set_bg() {
  printf '\e]11;%s\e\\' "$1"
}

# Change terminal foreground color (OSC 10)
function set_fg() {
  printf '\e]10;%s\e\\' "$1"
}

# Reset colors to default (OSC 110/111)
function reset_colors() {
  printf '\e]110\e\\'  # Reset foreground
  printf '\e]111\e\\'  # Reset background
}

# Set tab/window title (OSC 2)
function tab_title() {
  printf '\e]2;%s\e\\' "$1"
}
