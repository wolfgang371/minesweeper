class Minesweeper
    # A board cell is either a neighbour-bomb count (0..8) or one of the states
    # :unknown, :marker, :bomb, :bomb_triggered, :marker_wrong.
    alias Cell = Int32 | Symbol

    @bombs_matrix = [] of Array(Bool)  # the goal of the game
    @board_matrix = [] of Array(Cell)  # the progress of the game
    @num_markers_correct = 0
    @num_markers_incorrect = 0
    @num_non_bombs = 0
    @num_remaining_bombs = 0

    # Single-slot callbacks, the same plain-Proc pattern crymble-ui uses. Each
    # returns self so they can be chained: game.on_lose { … }.on_win { … }.
    @on_change : Proc(Int32, Int32, Cell, Nil)? = nil # row, col, new cell value
    @on_lose : Proc(Nil)? = nil
    @on_win : Proc(Nil)? = nil
    def on_change(&@on_change : Int32, Int32, Cell -> Nil); self end
    def on_lose(&@on_lose : -> Nil); self end
    def on_win(&@on_win : -> Nil); self end

    def initialize(@n : Int32, @bombs_num : Int32, seed : Int64? = nil)
        restart(seed)
    end
    def restart(seed : Int64? = nil)
    	a = [true]*@bombs_num + [false]*(@n*@n-@bombs_num)
        a.shuffle!(seed ? Random.new(seed) : Random.new) # seed just for deterministic unit tests
        @num_markers_correct = 0
        @num_markers_incorrect = 0
        @num_non_bombs = 0
        @bombs_matrix.clear
        @board_matrix.clear
    	@n.times do
    		@bombs_matrix.push(a.shift(@n))
            @board_matrix.push(([:unknown] of Cell)*@n)
    	end
        @num_remaining_bombs = @bombs_num
    end
    def remaining_bombs
        @num_remaining_bombs
    end
    def cell(row, col)
        @board_matrix[row][col]
    end
    def pick_direct(row, col) # only works on unknown cells
        if @board_matrix[row][col] == :unknown
            if @bombs_matrix[row][col]
                @board_matrix[row][col] = :bomb_triggered
                reveal_board
                @on_lose.try &.call
            else
                @num_non_bombs += 1
                reveal(row, col) # possibly reveal further cells
            end
            check_win
        end
        @board_matrix[row][col]
    end
    def marker(row, col) # only works on unknown or marked cells
        cell = @board_matrix[row][col]
        if cell.is_a?(Symbol)
            if cell == :marker
                cell = :unknown
                delta = -1
            else
                cell = :marker
                delta = 1
            end
            @num_remaining_bombs -= delta
            if @bombs_matrix[row][col]
                @num_markers_correct += delta
            else
                @num_markers_incorrect += delta
            end
            @board_matrix[row][col] = cell
            @on_change.try &.call(row, col, cell)
            check_win
        end
        cell
    end
    def pick_indirect(row, col) # only works on known cells
        cell = @board_matrix[row][col]
        if cell.is_a?(Int32)
            count_unknown = count_neighbours(row, col) {|r,c| @board_matrix[r][c]==:unknown ? 1:0}
            if count_unknown > 0
                count_marker = count_neighbours(row, col) {|r,c| @board_matrix[r][c]==:marker ? 1:0}
                if count_marker == cell  # -> pick all unknown
                    each_neighbour(row, col) {|r,c| pick_direct(r, c) if @board_matrix[r][c]==:unknown}
                elsif count_marker+count_unknown == cell # -> make all unknown into bombs
                    each_neighbour(row, col) {|r,c| marker(r, c) if @board_matrix[r][c]==:unknown}
                end
            end
        end
        cell
    end
    SYMBOL_CHARS = {:unknown => " ", :marker => "M", :bomb => "*", :bomb_triggered => "!", :marker_wrong => "X"}
    def to_s(io : IO) : Nil
        @board_matrix.each do |row|
            row.each do |cell|
                io << (cell.is_a?(Symbol) ? SYMBOL_CHARS[cell] : cell)
            end
            io << '\n'
        end
    end
    private def reveal_board
        @bombs_matrix.each_with_index do |row, ri|
            row.each_with_index do |is_bomb, ci|
                cell = @board_matrix[ri][ci] # :unknown, :marker, 0-9, :bomb, :bomb_triggered, :marker_wrong
                if cell == :unknown
                    cell = is_bomb ? :bomb : neighbour_bombs(ri, ci)
                elsif cell == :marker && !is_bomb
                    cell = :marker_wrong
                end
                @board_matrix[ri][ci] = cell
                @on_change.try &.call(ri, ci, cell)
            end
        end
    end
    private def reveal(row, col)
        count = neighbour_bombs(row, col)
        @board_matrix[row][col] = count
        @on_change.try &.call(row, col, count)
        each_neighbour(row, col) {|r,c| pick_direct(r,c)} if count == 0
    end
    private def check_win
        if (@num_markers_incorrect == 0) &&
            ((@bombs_num == @num_markers_correct) || # bomb markers match exactly (allows for some cheating)
             (@n*@n-@num_non_bombs == @bombs_num)) # all non-bomb fields have been picked (independent of markers)
            reveal_board
            @on_win.try &.call
        end
    end
    private OFFSETS = [{-1,-1},{-1,0},{-1,1},{0,-1},{0,1},{1,-1},{1,0},{1,1}]
    private def each_neighbour(row, col, &)
        OFFSETS.each do |dr, dc|
            r, c = row+dr, col+dc
            yield r, c if r>=0 && r<@n && c>=0 && c<@n
        end
    end
    private def count_neighbours(row, col, &)
        num = 0
        each_neighbour(row, col) {|r, c| num += yield(r, c)}
        num
    end
    private def neighbour_bombs(row, col)
        count_neighbours(row, col) {|r, c| @bombs_matrix[r][c] ? 1 : 0}
    end
end
