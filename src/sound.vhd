-- Music and sound effects as a square wave for a speaker across GPIO_0[0]
-- and GPIO_0[6], the same hookup as the lab's sound circuit. The two pins
-- are driven in opposite phase so the speaker sees twice the swing.
--
-- Music is Korobeiniki, the Russian folk song Tetris made famous (public
-- domain), stored as (note, length in eighths). It plays on the title and
-- game screens and speeds up with the level. Effects cut in over it for a
-- few frames: a blip when a piece locks, a rising run for a line clear
-- (longer for four lines), and a falling run at game over.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.tetris_pkg.all;

entity sound is
    port (
        clk       : in  std_logic;  -- 25 MHz
        enable    : in  std_logic;  -- SW[8]
        test      : in  std_logic;  -- SW[7]: steady A4, ignores the music and frames
        vert_sync : in  std_logic;
        scene     : in  scene_t;
        level     : in  integer range 0 to 29;
        ev_lock   : in  std_logic;  -- one-clock pulses from game_logic
        ev_clear  : in  std_logic;
        ev_tetris : in  std_logic;
        ev_over   : in  std_logic;
        spk_p     : out std_logic;
        spk_n     : out std_logic;
        active    : out std_logic   -- high while a note is playing
    );
end sound;

architecture rtl of sound is
    -- note numbers: 0 is a rest
    constant A3 : integer := 1;   constant C4 : integer := 2;   constant E4 : integer := 3;
    constant G4 : integer := 4;   constant A4 : integer := 5;   constant B4 : integer := 6;
    constant C5 : integer := 7;   constant D5 : integer := 8;   constant E5 : integer := 9;
    constant F5 : integer := 10;  constant G5 : integer := 11;  constant A5 : integer := 12;
    constant C6 : integer := 13;  constant E6 : integer := 14;  constant G6 : integer := 15;

    -- half a period, in 25 MHz clocks
    type half_t is array (0 to 15) of integer range 0 to 65535;
    constant HALF : half_t := (
        0, 56818, 47778, 37922, 31888, 28409, 25310, 23889,
        21283, 18961, 17897, 15944, 14205, 11945, 9480, 7972);

    type note_t is record
        n   : integer range 0 to 15;
        len : integer range 1 to 8;  -- eighths
    end record;
    type song_t is array (natural range <>) of note_t;
    constant SONG : song_t := (
        (E5, 2), (B4, 1), (C5, 1), (D5, 2), (C5, 1), (B4, 1),
        (A4, 2), (A4, 1), (C5, 1), (E5, 2), (D5, 1), (C5, 1),
        (B4, 3), (C5, 1), (D5, 2), (E5, 2),
        (C5, 2), (A4, 2), (A4, 2), (0, 2),
        (0, 1), (D5, 2), (F5, 1), (A5, 2), (G5, 1), (F5, 1),
        (E5, 3), (C5, 1), (E5, 2), (D5, 1), (C5, 1),
        (B4, 2), (B4, 1), (C5, 1), (D5, 2), (E5, 2),
        (C5, 2), (A4, 2), (A4, 2), (0, 2));

    -- effects: a run of notes, FX_STEP frames each
    constant FX_STEP : integer := 3;
    type fx_t is array (0 to 7) of integer range 0 to 15;
    constant FX_LOCK   : fx_t := (A3, 0, 0, 0, 0, 0, 0, 0);
    constant FX_CLEAR  : fx_t := (C5, E5, G5, C6, 0, 0, 0, 0);
    constant FX_TETRIS : fx_t := (C5, E5, G5, C6, E6, G6, E6, G6);
    constant FX_OVER   : fx_t := (A5, E5, C5, A4, E4, C4, A3, A3);

    signal vs_d     : std_logic_vector(1 downto 0) := "00";
    signal tick     : std_logic := '0';

    signal pos      : integer range 0 to SONG'length - 1 := 0;
    signal left     : integer range 0 to 127 := 0;  -- frames left in this note
    signal mnote    : integer range 0 to 15 := 0;

    signal fx       : fx_t := (others => 0);
    signal fx_i     : integer range 0 to 8 := 8;     -- 8 = no effect playing
    signal fx_left  : integer range 0 to FX_STEP := 0;
    signal pend     : std_logic_vector(3 downto 0) := (others => '0');  -- over tetris clear lock

    signal cnt      : integer range 0 to 65535 := 0;
    signal wave     : std_logic := '0';
    signal on_now   : std_logic;
    signal note_now : integer range 0 to 15;

    function eighth_frames(lvl : integer) return integer is
    begin
        if lvl >= 10 then
            return 7;
        else
            return 12 - lvl / 2;
        end if;
    end eighth_frames;
begin
    note_now <= A4 when test = '1' else fx(fx_i) when fx_i < 8 else mnote;
    on_now   <= '1' when enable = '1' and note_now /= 0 else '0';
    active   <= on_now;

    process (clk)
    begin
        if rising_edge(clk) then
            vs_d <= vs_d(0) & vert_sync;
            tick <= vs_d(0) and not vs_d(1);

            if ev_lock = '1'   then pend(0) <= '1'; end if;
            if ev_clear = '1'  then pend(1) <= '1'; end if;
            if ev_tetris = '1' then pend(2) <= '1'; end if;
            if ev_over = '1'   then pend(3) <= '1'; end if;

            if tick = '1' then
                -- start the most important pending effect
                if pend /= "0000" then
                    if pend(3) = '1' then
                        fx <= FX_OVER;
                    elsif pend(2) = '1' then
                        fx <= FX_TETRIS;
                    elsif pend(1) = '1' then
                        fx <= FX_CLEAR;
                    else
                        fx <= FX_LOCK;
                    end if;
                    fx_i    <= 0;
                    fx_left <= FX_STEP;
                    pend    <= (others => '0');
                elsif fx_i < 8 then
                    if fx_left > 1 then
                        fx_left <= fx_left - 1;
                    elsif fx_i = 7 or fx(fx_i + 1) = 0 then
                        fx_i <= 8;
                    else
                        fx_i    <= fx_i + 1;
                        fx_left <= FX_STEP;
                    end if;
                end if;

                -- music: the song on the title and game screens
                if scene = SC_OVER then
                    mnote <= 0;
                    pos   <= 0;
                    left  <= 0;
                elsif left = 0 then
                    mnote <= SONG(pos).n;
                    left  <= SONG(pos).len * eighth_frames(level) - 1;
                    if pos = SONG'length - 1 then
                        pos <= 0;
                    else
                        pos <= pos + 1;
                    end if;
                else
                    left <= left - 1;
                    if left = 1 then
                        mnote <= 0;  -- a frame of silence keeps repeated notes apart
                    end if;
                end if;
            end if;

            -- square wave
            if on_now = '0' then
                cnt  <= 0;
                wave <= '0';
            elsif cnt >= HALF(note_now) - 1 then
                cnt  <= 0;
                wave <= not wave;
            else
                cnt <= cnt + 1;
            end if;
        end if;
    end process;

    spk_p <= wave and on_now;
    spk_n <= (not wave) and on_now;
end rtl;
