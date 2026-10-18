require "./spec_helper"
require "../src/minesweeper"

describe Minesweeper do
    it "minesweeper works" do
        m = Minesweeper.new(4, 1, 0)
        .on_lose {puts("You lose!")}
        .on_win {puts("You win!")}
        m.marker(0,1)
        m.marker(1,0)
        m.to_s.should eq(" M  \nM   \n    \n    \n")
        m.pick_direct(0,0)
        m.pick_direct(1,1)
        m.to_s.should eq("0M00\nM011\n001 \n001 \n")
    end

    it "reveal_biggest_region opens a zero-region as a free opening" do
        m = Minesweeper.new(9, 5, 1_i64) # seeded layout, deterministic
        cell = m.reveal_biggest_region
        cell.should_not be_nil
        row, col = cell.not_nil!
        m.cell(row, col).should eq(0) # the seed of a region is always a zero-cell
        opened = 0
        9.times {|i| 9.times {|j| opened += 1 if m.cell(i, j).is_a?(Int32)}}
        opened.should be > 1 # a zero-region reveals more than just its seed
    end
end
