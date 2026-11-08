-- Game state and the once-per-frame update. Every move is proposed into the
-- k* candidate registers, the shared collision checker answers the next
-- clock, and the following state commits or rejects it.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.pieces.all;
use work.tetris_pkg.all;

entity game_logic is
    port (
        clk         : in  std_logic;
        reset_n     : in  std_logic;
        vert_sync   : in  std_logic;
        k_left      : in  std_logic;
        k_right     : in  std_logic;
        k_down      : in  std_logic;
        k_cw        : in  std_logic;
        k_ccw       : in  std_logic;
        k_drop      : in  std_logic;
        key_event   : in  std_logic;
        start_level : in  std_logic_vector(3 downto 0);
        force_piece : in  std_logic_vector(2 downto 0);  -- "111" = random
        board       : out board_t;
        cur_shape   : out shape_t;
        cur_rot     : out rot_t;
        cur_px      : out px_t;
        cur_py      : out py_t;
        ghost_py    : out py_t;
        next_shape  : out shape_t;
        game_over   : out std_logic;
        lines_bcd   : out std_logic_vector(15 downto 0);
        level_bcd   : out std_logic_vector(7 downto 0)
    );
end game_logic;

architecture rtl of game_logic is
    type state_t is (S_RESET, S_SPAWN, S_SPAWN_CHK, S_WAIT, S_ROT, S_ROT_CHK,
                     S_MOVE, S_MOVE_CHK, S_FALL, S_FALL_CHK, S_HARD_CHK,
                     S_GHOST_CHK, S_LOCK, S_CLEAR, S_OVER);
    signal st : state_t := S_RESET;

    signal brd : board_t := EMPTY_BOARD;
    signal cs  : shape_t := 0;
    signal cr  : rot_t   := 0;
    signal cx  : px_t    := SPAWN_PX;
    signal cy  : py_t    := 0;
    signal gy  : py_t    := 0;
    signal ns  : shape_t := 0;

    -- candidate position under test
    signal ks  : shape_t := 0;
    signal kr  : rot_t   := 0;
    signal kx  : integer range -2 to 14 := SPAWN_PX;
    signal ky  : integer range 0 to 21  := 0;
    signal hit : boolean;

    -- frame tick and keys; key vector is drop ccw cw down right left
    signal vs_sync  : std_logic_vector(2 downto 0) := "000";
    signal frame_rq : std_logic := '0';
    signal kprev    : std_logic_vector(5 downto 0) := (others => '0');
    signal pressed  : std_logic_vector(5 downto 0) := (others => '0');

    -- this frame's decisions
    signal want_rot  : integer range -1 to 1 := 0;
    signal want_dx   : integer range -1 to 1 := 0;
    signal want_fall : std_logic := '0';
    signal want_drop : std_logic := '0';
    signal kick      : integer range 0 to 4 := 0;

    signal das      : integer range 0 to 16 := 0;
    signal grav_cnt : integer range 0 to 63 := 0;
    signal soft     : std_logic := '0';

    signal lvl       : integer range 0 to 29 := 0;
    signal lvl_bcd   : std_logic_vector(7 downto 0) := x"00";
    signal lines     : std_logic_vector(15 downto 0) := x"0000";
    signal lvl_lines : integer range 0 to 9 := 0;
    signal over      : std_logic := '0';

    signal lfsr : std_logic_vector(15 downto 0) := x"ACE1";

    function pick(l : std_logic_vector(15 downto 0); avoid : shape_t;
                  forced : std_logic_vector(2 downto 0)) return shape_t is
        variable v : integer range 0 to 7;
    begin
        if forced /= "111" then
            return to_integer(unsigned(forced));
        end if;
        v := to_integer(unsigned(l(2 downto 0)));
        if v = 7 or v = avoid then
            v := to_integer(unsigned(l(5 downto 3)));
            if v = 7 then
                v := to_integer(unsigned(l(8 downto 6))) mod 7;
            end if;
        end if;
        return v;
    end pick;

    function kick_dx(i : integer) return integer is
    begin
        case i is
            when 1 => return -1;
            when 2 => return 1;
            when 3 => return -2;
            when 4 => return 2;
            when others => return 0;
        end case;
    end kick_dx;

    function clamp_level(v : std_logic_vector(3 downto 0)) return integer is
    begin
        if unsigned(v) > 9 then
            return 9;
        end if;
        return to_integer(unsigned(v));
    end clamp_level;
begin
    hit <= collides(brd, ks, kr, kx, ky);

    board      <= brd;
    cur_shape  <= cs;
    cur_rot    <= cr;
    cur_px     <= cx;
    cur_py     <= cy;
    ghost_py   <= gy;
    next_shape <= ns;
    game_over  <= over;
    lines_bcd  <= lines;
    level_bcd  <= lvl_bcd;

    process (clk)
        variable keys  : std_logic_vector(5 downto 0);
        variable acc   : std_logic_vector(5 downto 0);
        variable fp    : std_logic_vector(5 downto 0);
        variable full  : integer range -1 to ROWS - 1;
        variable fall  : std_logic;
        variable dx    : integer range -1 to 1;
        variable max_k : integer range 0 to 4;
    begin
        if rising_edge(clk) then
            -- LFSR steps every clock but stalls on key events, so the
            -- sequence depends on exactly when each key was hit
            if key_event = '0' then
                lfsr <= lfsr(14 downto 0) & (lfsr(15) xor lfsr(13) xor lfsr(12) xor lfsr(10));
            end if;

            vs_sync <= vs_sync(1 downto 0) & vert_sync;
            if vs_sync(1) = '1' and vs_sync(2) = '0' then
                frame_rq <= '1';
            end if;

            keys  := k_drop & k_ccw & k_cw & k_down & k_right & k_left;
            acc   := pressed or (keys and not kprev);
            kprev <= keys;
            fp    := (others => '0');

            case st is
                when S_RESET =>
                    brd       <= EMPTY_BOARD;
                    lines     <= x"0000";
                    lvl       <= clamp_level(start_level);
                    lvl_bcd   <= "0000" & std_logic_vector(to_unsigned(clamp_level(start_level), 4));
                    lvl_lines <= 0;
                    over      <= '0';
                    grav_cnt  <= 0;
                    das       <= 0;
                    ns        <= pick(lfsr, ns, "111");
                    acc       := (others => '0');
                    st        <= S_SPAWN;

                when S_SPAWN =>
                    if force_piece /= "111" then
                        cs <= to_integer(unsigned(force_piece));
                        ks <= to_integer(unsigned(force_piece));
                    else
                        cs <= ns;
                        ks <= ns;
                        ns <= pick(lfsr, ns, "111");
                    end if;
                    cr <= 0;  kr <= 0;
                    cx <= SPAWN_PX;  kx <= SPAWN_PX;
                    cy <= 0;  ky <= 0;
                    grav_cnt <= 0;
                    st <= S_SPAWN_CHK;

                when S_SPAWN_CHK =>
                    if hit then
                        over <= '1';
                        st   <= S_OVER;
                    else
                        ky <= 1;
                        st <= S_GHOST_CHK;
                    end if;

                when S_WAIT =>
                    if frame_rq = '1' then
                        frame_rq <= '0';
                        fp  := acc;
                        acc := (others => '0');

                        -- rotation: clockwise wins if both
                        if fp(3) = '1' then
                            want_rot <= 1;
                        elsif fp(4) = '1' then
                            want_rot <= -1;
                        else
                            want_rot <= 0;
                        end if;

                        -- sideways with delayed auto shift (16 frames, then every 6)
                        dx := 0;
                        if fp(0) = '1' then
                            dx := -1;  das <= 0;
                        elsif fp(1) = '1' then
                            dx := 1;   das <= 0;
                        elsif keys(0) = '1' or keys(1) = '1' then
                            if das = 15 then
                                das <= 10;
                                if keys(0) = '1' then dx := -1; else dx := 1; end if;
                            else
                                das <= das + 1;
                            end if;
                        else
                            das <= 0;
                        end if;
                        want_dx <= dx;

                        -- gravity, sped up to every 2nd frame by soft drop
                        fall := '0';
                        if grav_cnt + 1 >= gravity_frames(lvl) then
                            fall := '1';
                        end if;
                        if keys(2) = '1' then
                            soft <= not soft;
                            if soft = '1' or fp(2) = '1' then
                                fall := '1';
                            end if;
                        else
                            soft <= '0';
                        end if;
                        if fall = '1' then
                            grav_cnt <= 0;
                        else
                            grav_cnt <= grav_cnt + 1;
                        end if;
                        want_fall <= fall;
                        want_drop <= fp(5);
                        kick <= 0;
                        st   <= S_ROT;
                    end if;

                when S_ROT =>
                    ks <= cs;
                    kx <= cx + kick_dx(kick);
                    ky <= cy;
                    kr <= (cr + 4 + want_rot) mod 4;
                    if want_rot = 0 then
                        st <= S_MOVE;
                    else
                        st <= S_ROT_CHK;
                    end if;

                when S_ROT_CHK =>
                    if cs = 0 then max_k := 4; else max_k := 2; end if;
                    if not hit then
                        cr <= kr;
                        cx <= kx;
                        st <= S_MOVE;
                    elsif kick < max_k then
                        kick <= kick + 1;
                        st   <= S_ROT;
                    else
                        st <= S_MOVE;
                    end if;

                when S_MOVE =>
                    ks <= cs;  kr <= cr;  ky <= cy;
                    kx <= cx + want_dx;
                    if want_dx = 0 then
                        st <= S_FALL;
                    else
                        st <= S_MOVE_CHK;
                    end if;

                when S_MOVE_CHK =>
                    if not hit then
                        cx <= kx;
                    end if;
                    st <= S_FALL;

                when S_FALL =>
                    ks <= cs;  kr <= cr;  kx <= cx;
                    ky <= cy + 1;
                    if want_drop = '1' then
                        st <= S_HARD_CHK;
                    elsif want_fall = '1' then
                        st <= S_FALL_CHK;
                    else
                        st <= S_GHOST_CHK;
                    end if;

                when S_FALL_CHK =>
                    if hit then
                        st <= S_LOCK;
                    else
                        cy <= ky;
                        ky <= ky + 1;
                        st <= S_GHOST_CHK;
                    end if;

                when S_HARD_CHK =>
                    if hit then
                        st <= S_LOCK;
                    else
                        cy <= ky;
                        ky <= ky + 1;
                    end if;

                when S_GHOST_CHK =>
                    if hit then
                        gy <= ky - 1;
                        st <= S_WAIT;
                    else
                        ky <= ky + 1;
                    end if;

                when S_LOCK =>
                    for r in 0 to 3 loop
                        for c in 0 to 3 loop
                            if mask_bit(cs, cr, r, c) = '1' and cy + r <= ROWS - 1
                               and cx + c >= 3 and cx + c <= COLS + 2 then
                                brd(cy + r)(cx + c - 3) <= cell_of(cs);
                            end if;
                        end loop;
                    end loop;
                    st <= S_CLEAR;

                when S_CLEAR =>
                    full := -1;
                    for r in 0 to ROWS - 1 loop
                        if row_full(brd(r)) then
                            full := r;
                        end if;
                    end loop;
                    if full >= 0 then
                        for r in 1 to ROWS - 1 loop
                            if r <= full then
                                brd(r) <= brd(r - 1);
                            end if;
                        end loop;
                        brd(0) <= EMPTY_ROW;
                        lines  <= bcd_inc(lines);
                        if lvl_lines = 9 then
                            lvl_lines <= 0;
                            if lvl < 29 then
                                lvl     <= lvl + 1;
                                lvl_bcd <= bcd_inc(lvl_bcd);
                            end if;
                        else
                            lvl_lines <= lvl_lines + 1;
                        end if;
                    else
                        st <= S_SPAWN;
                    end if;

                when S_OVER =>
                    if frame_rq = '1' then
                        frame_rq <= '0';
                        if acc(5) = '1' then
                            st <= S_RESET;
                        end if;
                        acc := (others => '0');
                    end if;
            end case;

            pressed <= acc;

            if reset_n = '0' then
                st       <= S_RESET;
                frame_rq <= '0';
                pressed  <= (others => '0');
            end if;
        end if;
    end process;
end rtl;
