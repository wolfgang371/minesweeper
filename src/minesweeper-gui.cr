# Minesweeper — CrymbleUI frontend.
#
# Design:
# - Game logic lives entirely in Minesweeper (src/minesweeper.cr); this file is
#   only the view + input layer and talks to the game through its public API and
#   win/lose signals.
# - The whole board is ONE custom widget (Board) that paints every cell as a
#   DrawImage primitive and turns click coordinates back into (row, col). This
#   mirrors the original "tile map" approach and avoids 900 child widgets.
#
# Build/run:
#   crystal run src/minesweeper-gui.cr        # or: shards build minesweeper && bin/minesweeper

require "crymble-ui"
require "./minesweeper"

include CrymbleUI

# Cell images, embedded into the binary at compile time as CrymbleUI ImageSources
# (key + compile-time read_file bytes — the same thing embed_image builds, done in
# a loop). No runtime file dependency. Keyed by the string `cell.to_s` yields for
# every board value: the symbols (:unknown, :marker, :bomb, :bomb_triggered,
# :marker_wrong) and the neighbour counts 0..8.
CELL_IMAGES = begin
  images = {} of String => ImageSource
  {% for name in %w(unknown 0 1 2 3 4 5 6 7 8 marker bomb marker_wrong bomb_triggered) %}
    images[{{name}}] = ImageSource.new({{name}}, {{ read_file("#{__DIR__}/resources/#{name.id}.png") }}.to_slice)
  {% end %}
  images
end

# Renders the full minesweeper board and dispatches per-cell clicks.
#
# Like the original (imgui's `is_item_clicked` "reacts on release"), a press
# only *highlights* the cell under the cursor — the action fires on release, and
# only if the release lands on a cell. The highlight follows the cursor while the
# button is held (on_mouse_move is delivered to the press-widget during a drag).
class Board < Widget
  CELL         = 32                       # pixel size of one cell
  PRESSED_TINT = Color.new(150, 150, 150) # multiply-darken → "sunken" look

  @pressed : Tuple(Int32, Int32)? = nil

  # @mouse_point yields the current mouse position (nil if unknown) so the
  # keyboard shortcuts can act on the cell under the cursor, like the original.
  def initialize(@game : Minesweeper, @n : Int32,
                 @on_left : Proc(Int32, Int32, Nil),
                 @on_right : Proc(Int32, Int32, Nil),
                 @mouse_point : Proc(Vec2?))
    super(id: "board")
  end

  def measure(constraints : BoxConstraints) : Size
    Size.new(@n * CELL, @n * CELL)
  end

  def perform_layout(constraints : BoxConstraints, position : Vec2)
    @bounds = Rect.new(position, measure(constraints))
  end

  # One DrawImage per cell, reading the live game state; the pressed cell is
  # drawn darkened.
  def to_primitives(bounds : Rect) : Array(DrawPrimitive)
    prims = [] of DrawPrimitive
    pressed = @pressed
    @n.times do |row|
      @n.times do |col|
        rect = Rect.new(Vec2.new(col * CELL, row * CELL), Size.new(CELL, CELL))
        tint = pressed == {row, col} ? PRESSED_TINT : Color.white
        prims << DrawImage.new(CELL_IMAGES[@game.cell(row, col).to_s], rect, tint)
      end
    end
    prims
  end

  # Press: highlight only, do not trigger yet.
  def on_mouse_down(point : Vec2, button : MouseButton = MouseButton::Left)
    set_pressed(cell_at(point))
  end

  # Drag while held: highlight follows the cursor (nil once off the board).
  def on_mouse_move(point : Vec2)
    set_pressed(cell_at(point))
  end

  # Release: trigger the action on the cell under the cursor, then clear.
  def on_mouse_up(point : Vec2, button : MouseButton = MouseButton::Left)
    if cell = cell_at(point)
      button.right? ? @on_right.call(cell[0], cell[1]) : @on_left.call(cell[0], cell[1])
    end
    set_pressed(nil)
  end

  # Keyboard equivalents of clicking the *hovered* cell, mirroring the original
  # imgui controls: Space = left click, "m" = right click (toggle marker). The
  # board is the focused widget, so it receives these before the framework's
  # own Space-activates-focused-widget handling.
  def on_key_down(key : SF::Keyboard::Key, control : Bool, shift : Bool, alt : Bool = false) : Bool
    return false if control || alt
    action = case key
             when SF::Keyboard::Space then @on_left
             when SF::Keyboard::M     then @on_right
             else                          return false
             end
    if (point = @mouse_point.call) && (cell = cell_at(point))
      action.call(cell[0], cell[1])
    end
    true # consume Space/m even off-board, so they don't fall through
  end

  # Focusable so it can receive key events; the app keeps focus on it.
  def focusable? : Bool
    true
  end

  # The board paints no focus visual, so swallow the focus-flash highlight to
  # avoid the controller's periodic mark_needs_render (pointless redraws).
  def focus_highlighted=(value : Bool)
  end

  def label : String
    "board"
  end

  private def set_pressed(cell : Tuple(Int32, Int32)?)
    return if cell == @pressed
    @pressed = cell
    mark_needs_render
  end

  # Absolute point → (row, col), or nil if outside the board.
  private def cell_at(point : Vec2) : Tuple(Int32, Int32)?
    lx = point.x - absolute_bounds.x
    ly = point.y - absolute_bounds.y
    return nil if lx < 0 || ly < 0
    col = (lx / CELL).to_i
    row = (ly / CELL).to_i
    return nil if row >= @n || col >= @n
    {row, col}
  end
end

class MinesweeperApp < App
  # Board configuration choices, offered as combo boxes so only sensible values
  # are selectable. Sizes stop at 30 — the largest board that fits the window
  # (30 * 32px). Bomb counts are offered as densities of the current board, so
  # changing the size keeps the difficulty; 20% matches the original.
  SIZES     = [8, 10, 12, 16, 20, 24, 30]
  DENSITIES = [10, 12, 15, 18, 20, 22, 25] # percent of cells holding a bomb

  state autosolver : Bool = true # on by default, as in the original
  state autostart : Bool = true  # free opening (reveal the biggest region) on new games
  state size_index : Int32 = SIZES.size - 1      # 30x30, as in the original
  state density_index : Int32 = DENSITIES.index!(20)
  state gameover : Symbol? = nil # nil | :won | :lost

  # Placeholder until initialize wires up the real game: new_game's callbacks
  # capture self, which Crystal only allows once every ivar is set.
  @game = Minesweeper.new(1, 0)
  @board_changed = false
  @timer_started = false

  def initialize
    super()
    @game = new_game
  end

  private def n : Int32
    SIZES[size_index]
  end

  private def bombs_for(density : Int32) : Int32
    (n * n * density / 100).to_i
  end

  def build : Widget
    start_autosolver_timer

    # Hoisted so we can keep keyboard focus on it: Space / "m" act on the cell
    # under the mouse, the same as a left / right click (original imgui controls).
    board = Board.new(@game, n,
      ->(row : Int32, col : Int32) { left_click(row, col) },
      ->(row : Int32, col : Int32) { right_click(row, col) },
      -> { @last_mouse_position })
    board.request_focus

    window("Minesweeper", 1000, 1070) do
      vstack(id: "root", padding: 10.0, spacing: 14.0) do
        vstack(spacing: 6.0) do
          # Changing size or bomb count starts a new game with the new settings.
          hstack(spacing: 16.0) do
            text("#{@game.remaining_bombs} bombs left", font_scale: 1)
            # F2, as in the classic game: a plain letter is too easy to hit by
            # accident, and a browser tab never sees Ctrl+N (web build).
            button("New game", shortcut: "F2") { restart_game }
            text("Size:")
            combo_box(items: SIZES.map { |s| "#{s}x#{s}" }, selected: size_index, width: 100.0) do |idx, _|
              self.size_index = idx
              restart_game
            end
            text("Bombs:")
            combo_box(items: DENSITIES.map { |d| "#{bombs_for(d)} (#{d}%)" }, selected: density_index, width: 120.0) do |idx, _|
              self.density_index = idx
              restart_game
            end
            checkbox("Auto-start?", checked: autostart) { self.autostart = !autostart }
            checkbox("Autosolver?", checked: autosolver) { self.autosolver = !autosolver }
          end

          text("Left click / Space: reveal, chord  |  Right click / m: toggle marker", font_scale: -1)
        end

        widget board
      end

      if go = gameover
        popup(x: 400.0, y: 440.0, padding: 20.0) do
          vstack(spacing: 12.0) do
            text(go == :won ? "You won!" : "You lost!", font_scale: 3)
            text("Play again?")
            hstack(spacing: 12.0) do
              button("Yes", shortcut: "Y") { restart_game }
              button("No", shortcut: "N") { quit }
            end
          end
        end
      end
    end
  end

  # Left click: reveal an unknown/marked cell, or chord-pick around a number.
  private def left_click(row, col)
    return unless gameover.nil?
    cell = @game.cell(row, col)
    cell.is_a?(Symbol) ? @game.pick_direct(row, col) : @game.pick_indirect(row, col)
    request_rebuild
  end

  # Right click: toggle a marker on an unknown/marked cell, or chord-pick a number.
  private def right_click(row, col)
    return unless gameover.nil?
    cell = @game.cell(row, col)
    cell.is_a?(Symbol) ? @game.marker(row, col) : @game.pick_indirect(row, col)
    request_rebuild
  end

  # A fresh game with the current settings. Always a new instance (not
  # Minesweeper#restart), since size and bomb count may have changed.
  private def new_game : Minesweeper
    game = Minesweeper.new(n, bombs_for(DENSITIES[density_index]))
    game.on_win { self.gameover = :won }
    game.on_lose { self.gameover = :lost }
    game.on_change { |_row, _col, _cell| @board_changed = true }
    game.reveal_biggest_region if autostart # free opening: open the biggest region up front
    game
  end

  private def restart_game
    self.gameover = nil # first: a free opening on a small board can win outright
    @game = new_game
    request_rebuild # gameover may already be nil, so don't rely on its setter
  end

  # The scheduler only exists once the renderer is up, so start the repeating
  # timer lazily on the first build() that finds it ready (mirrors CPUMonitor).
  private def start_autosolver_timer
    return if @timer_started
    Widget.scheduler.schedule(50.milliseconds, repeating: true) { autosolve_tick }
    @timer_started = true
  rescue
    # Scheduler not initialized yet (first build, before the renderer) — retry.
  end

  # One animated autosolver step: a full deductive sweep over the board. Only
  # rebuilds (→ redraws) when the sweep actually changed something, so a stuck
  # solver goes idle instead of burning frames.
  private def autosolve_tick
    return unless autosolver && gameover.nil?
    @board_changed = false
    n.times do |row|
      n.times do |col|
        @game.pick_indirect(row, col) if gameover.nil?
      end
    end
    rebuild if @board_changed # rebuild marks all layers dirty → run loop redraws
  end
end

CrymbleUI.run(MinesweeperApp.new)
