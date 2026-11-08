library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.pieces.all;

package tetris_pkg is
    constant COLS : integer := 10;
    constant ROWS : integer := 20;

    subtype cell_t is std_logic_vector(2 downto 0);  -- 0 empty, 1..7 = shape + 1
    constant EMPTY : cell_t := "000";
    type row_t is array (0 to COLS - 1) of cell_t;
    type board_t is array (0 to ROWS - 1) of row_t;
    constant EMPTY_ROW   : row_t   := (others => EMPTY);
    constant EMPTY_BOARD : board_t := (others => EMPTY_ROW);

    subtype shape_t is integer range 0 to 6;
    subtype rot_t is integer range 0 to 3;
    -- padded column of the 4x4 box's left edge; board column = px + c - 3
    subtype px_t is integer range 0 to 12;
    subtype py_t is integer range 0 to 20;
    constant SPAWN_PX : px_t := 6;

    subtype rgb_t is std_logic_vector(11 downto 0);  -- R G B, 4 bits each
    constant GRAY : integer := 8;                    -- palette index for game over

    function occupied(b : board_t; p, r : integer) return boolean;
    function collides(b : board_t; s : shape_t; rt : rot_t; px, py : integer) return boolean;
    function row_full(rw : row_t) return boolean;
    function cell_of(s : shape_t) return cell_t;
    function bcd_inc(v : std_logic_vector) return std_logic_vector;
    -- shade: 0 base, 1 highlight, 2 shadow
    function palette(idx : integer; shade : integer) return rgb_t;
    function gravity_frames(level : integer) return integer;
end tetris_pkg;

package body tetris_pkg is

    function occupied(b : board_t; p, r : integer) return boolean is
    begin
        if r > ROWS - 1 or p < 3 or p > COLS + 2 then
            return true;
        end if;
        return b(r)(p - 3) /= EMPTY;
    end occupied;

    function collides(b : board_t; s : shape_t; rt : rot_t; px, py : integer) return boolean is
        variable hit : boolean := false;
    begin
        for r in 0 to 3 loop
            for c in 0 to 3 loop
                if mask_bit(s, rt, r, c) = '1' and occupied(b, px + c, py + r) then
                    hit := true;
                end if;
            end loop;
        end loop;
        return hit;
    end collides;

    function row_full(rw : row_t) return boolean is
        variable full : boolean := true;
    begin
        for c in 0 to COLS - 1 loop
            if rw(c) = EMPTY then
                full := false;
            end if;
        end loop;
        return full;
    end row_full;

    function cell_of(s : shape_t) return cell_t is
    begin
        return std_logic_vector(to_unsigned(s + 1, 3));
    end cell_of;

    -- increment a packed BCD number, saturating at all nines
    function bcd_inc(v : std_logic_vector) return std_logic_vector is
        variable r     : std_logic_vector(v'length - 1 downto 0) := v;
        variable d     : unsigned(3 downto 0);
        variable carry : boolean := true;
        variable nines : boolean := true;
    begin
        for i in 0 to integer(v'length / 4) - 1 loop
            if r(i * 4 + 3 downto i * 4) /= "1001" then
                nines := false;
            end if;
        end loop;
        if nines then
            return r;
        end if;
        for i in 0 to integer(v'length / 4) - 1 loop
            if carry then
                d := unsigned(r(i * 4 + 3 downto i * 4));
                if d = 9 then
                    r(i * 4 + 3 downto i * 4) := "0000";
                else
                    r(i * 4 + 3 downto i * 4) := std_logic_vector(d + 1);
                    carry := false;
                end if;
            end if;
        end loop;
        return r;
    end bcd_inc;

    function palette(idx : integer; shade : integer) return rgb_t is
        type pal_t is array (0 to 8, 0 to 2) of rgb_t;
        constant PAL : pal_t := (
            (x"000", x"000", x"000"),  -- 0 unused
            (x"0EE", x"8FF", x"088"),  -- 1 I cyan
            (x"EE0", x"FF8", x"880"),  -- 2 O yellow
            (x"A0E", x"D8F", x"608"),  -- 3 T purple
            (x"0D0", x"8F8", x"070"),  -- 4 S green
            (x"E00", x"F88", x"800"),  -- 5 Z red
            (x"22F", x"88F", x"008"),  -- 6 J blue
            (x"F80", x"FC8", x"940"),  -- 7 L orange
            (x"888", x"CCC", x"444")   -- 8 game over gray
        );
    begin
        return PAL(idx, shade);
    end palette;

    function gravity_frames(level : integer) return integer is
        type grav_t is array (0 to 29) of integer range 1 to 48;
        constant GRAV : grav_t := (48, 43, 38, 33, 28, 23, 18, 13, 8, 6,
                                   5, 5, 5, 4, 4, 4, 3, 3, 3, 2,
                                   2, 2, 2, 2, 2, 2, 2, 2, 2, 1);
    begin
        return GRAV(level);
    end gravity_frames;

end tetris_pkg;
