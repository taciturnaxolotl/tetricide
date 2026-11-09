-- DE1 top level in VHDL. The same wiring is drawn as a schematic in
-- tetricide_top.bdf (tools/gen_bdf.py); either can be the Quartus top level.
library ieee;
use ieee.std_logic_1164.all;

entity tetricide is
    port (
        CLOCK_50 : in  std_logic;
        KEY      : in  std_logic_vector(3 downto 0);
        SW       : in  std_logic_vector(9 downto 0);
        PS2_CLK  : in  std_logic;
        PS2_DAT  : in  std_logic;
        VGA_R    : out std_logic_vector(3 downto 0);
        VGA_G    : out std_logic_vector(3 downto 0);
        VGA_B    : out std_logic_vector(3 downto 0);
        VGA_HS   : out std_logic;
        VGA_VS   : out std_logic;
        HEX0     : out std_logic_vector(6 downto 0);
        HEX1     : out std_logic_vector(6 downto 0);
        HEX2     : out std_logic_vector(6 downto 0);
        HEX3     : out std_logic_vector(6 downto 0);
        LEDG     : out std_logic_vector(7 downto 0);
        LEDR     : out std_logic_vector(9 downto 0)
    );
end tetricide;

architecture rtl of tetricide is
    signal clk25    : std_logic;
    signal hs, vs   : std_logic;
    signal video_on : std_logic;
    signal row, col : std_logic_vector(9 downto 0);
    signal r, g, b  : std_logic_vector(3 downto 0);
    signal lines    : std_logic_vector(15 downto 0);
    signal over     : std_logic;
begin
    div : entity work.clk_div2 port map (CLOCK_50, clk25);

    timing : entity work.vga_timing
        port map (clk25, hs, vs, video_on, row, col);

    core : entity work.tetris_core
        port map (
            clk => clk25, reset_n => KEY(0), ps2_clk => PS2_CLK, ps2_data => PS2_DAT,
            vert_sync => vs, pixel_row => row, pixel_col => col,
            start_level => SW(3 downto 0), force_piece => "111", show_ghost => SW(9),
            red => r, green => g, blue => b,
            lines_bcd => lines, level_bcd => LEDG, game_over => over);

    output : entity work.vga_out
        port map (clk25, hs, vs, video_on, r, g, b, VGA_R, VGA_G, VGA_B, VGA_HS, VGA_VS);

    digits : entity work.hex4 port map (lines, HEX3, HEX2, HEX1, HEX0);

    LEDR <= over & "000000000";
end rtl;
