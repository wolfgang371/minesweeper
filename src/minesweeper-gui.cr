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

# Cell images, embedded into the binary at compile time and served from
# CrSFMLBackend's registry (no runtime file dependency). The registry key is the
# image name, which is exactly what `cell.to_s` yields for every board value:
# Symbols (:unknown, :marker, :bomb, :bomb_triggered, :marker_wrong) and the
# neighbour counts 0..8.
{% for name in %w(unknown 0 1 2 3 4 5 6 7 8 marker bomb marker_wrong bomb_triggered) %}
  CrSFMLBackend.register_embedded_image({{name}}, {{ read_file("#{__DIR__}/resources/#{name.id}.png") }}.to_slice)
{% end %}

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
        prims << DrawImage.new(@game.cell(row, col).to_s, rect, tint)
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
  N     = 30
  BOMBS = (N * N * 0.20).to_i # 20% bomb density (matches the original)

  state autosolver : Bool = true # on by default, as in the original
  state gameover : Symbol? = nil # nil | :won | :lost

  @game : Minesweeper
  @board_changed = false
  @timer_started = false

  def initialize
    super()
    @game = Minesweeper.new(N, BOMBS)
    @game.on_win { self.gameover = :won }
    @game.on_lose { self.gameover = :lost }
    @game.on_change { |_row, _col, _cell| @board_changed = true }
  end

  def build : Widget
    start_autosolver_timer

    # Hoisted so we can keep keyboard focus on it: Space / "m" act on the cell
    # under the mouse, the same as a left / right click (original imgui controls).
    board = Board.new(@game, N,
      ->(row : Int32, col : Int32) { left_click(row, col) },
      ->(row : Int32, col : Int32) { right_click(row, col) },
      -> { @last_mouse_position })
    board.request_focus

    window("Minesweeper", 1000, 1040) do
      vstack(id: "root", padding: 10.0, spacing: 8.0) do
        hstack(spacing: 20.0) do
          text("#{@game.remaining_bombs} bombs left", font_scale: 1)
          checkbox("Autosolver?", checked: autosolver) { self.autosolver = !autosolver }
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

  private def restart_game
    @game.restart
    self.gameover = nil # state setter triggers the rebuild
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
    N.times do |row|
      N.times do |col|
        @game.pick_indirect(row, col) if gameover.nil?
      end
    end
    rebuild if @board_changed # rebuild marks all layers dirty → run loop redraws
  end
end

CrymbleUI.run(MinesweeperApp.new)
