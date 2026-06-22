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
end
