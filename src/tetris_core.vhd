-- Keyboard, game and renderer behind plain std_logic ports, so Quartus can
-- make a schematic symbol for it and it can sit next to Dr. Kohl's VGA_SYNC.
library ieee;
use ieee.std_logic_1164.all;
use work.tetris_pkg.all;

entity tetris_core is
    port (
        clk         : in  std_logic;  -- 25 MHz
        reset_n     : in  std_logic;
        ps2_clk     : in  std_logic;
        ps2_data    : in  std_logic;
        vert_sync   : in  std_logic;
        pixel_row   : in  std_logic_vector(9 downto 0);
        pixel_col   : in  std_logic_vector(9 downto 0);
        start_level : in  std_logic_vector(3 downto 0);
        force_piece : in  std_logic_vector(2 downto 0);  -- tie to "111"
        show_ghost  : in  std_logic;
        red         : out std_logic_vector(3 downto 0);
        green       : out std_logic_vector(3 downto 0);
        blue        : out std_logic_vector(3 downto 0);
        lines_bcd   : out std_logic_vector(15 downto 0);
        level_bcd   : out std_logic_vector(7 downto 0);
        game_over   : out std_logic
    );
end tetris_core;

architecture rtl of tetris_core is
    signal k_left, k_right, k_down, k_cw, k_ccw, k_drop, key_event : std_logic;
    signal board  : board_t;
    signal cs, ns : shape_t;
    signal cr     : rot_t;
    signal cx     : px_t;
    signal cy, gy : py_t;
    signal over   : std_logic;
    signal lines  : std_logic_vector(15 downto 0);
    signal level  : std_logic_vector(7 downto 0);
    signal rgb    : rgb_t;
    signal pon    : std_logic;
    signal arows  : std_logic_vector(ROWS - 1 downto 0);
    signal at     : integer range 0 to ANIM_LEN - 1;
    signal ot     : integer range 0 to OVER_LEN;
    signal fcnt   : std_logic_vector(9 downto 0);
    signal scn    : scene_t;
    signal mph    : mphase_t;
    signal mt     : integer range 0 to MELT_LEN - 1;
    signal sct    : integer range 0 to 127;
begin
    keys : entity work.ps2_keys
        port map (clk, reset_n, ps2_clk, ps2_data,
                  k_left, k_right, k_down, k_cw, k_ccw, k_drop, key_event);

    game : entity work.game_logic
        port map (
            clk => clk, reset_n => reset_n, vert_sync => vert_sync,
            k_left => k_left, k_right => k_right, k_down => k_down,
            k_cw => k_cw, k_ccw => k_ccw, k_drop => k_drop, key_event => key_event,
            start_level => start_level, force_piece => force_piece,
            board => board, cur_shape => cs, cur_rot => cr, cur_px => cx,
            cur_py => cy, ghost_py => gy, next_shape => ns, game_over => over,
            lines_bcd => lines, level_bcd => level, piece_on => pon,
            anim_rows => arows, anim_t => at, over_t => ot, frame_cnt => fcnt,
            scene => scn, mphase => mph, melt_t => mt, scene_t_out => sct);

    draw : entity work.renderer
        port map (
            pixel_row => pixel_row, pixel_col => pixel_col, board => board,
            cur_shape => cs, cur_rot => cr, cur_px => cx, cur_py => cy,
            ghost_py => gy, next_shape => ns, game_over => over,
            lines_bcd => lines, level_bcd => level, show_ghost => show_ghost, piece_on => pon, anim_rows => arows, anim_t => at,
            over_t => ot, frame_cnt => fcnt, scene => scn, mphase => mph,
            melt_t => mt, scene_t => sct, rgb => rgb);

    red       <= rgb(11 downto 8);
    green     <= rgb(7 downto 4);
    blue      <= rgb(3 downto 0);
    lines_bcd <= lines;
    level_bcd <= level;
    game_over <= over;
end rtl;
