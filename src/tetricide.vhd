-- DE1 top level. Pin names match the DE1 pin assignment file.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

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
    signal clk25    : std_logic := '0';
    signal hs, vs   : std_logic;
    signal video_on : std_logic;
    signal row, col : std_logic_vector(9 downto 0);
    signal r, g, b  : std_logic_vector(3 downto 0);
    signal lines    : std_logic_vector(15 downto 0);
    signal level    : std_logic_vector(7 downto 0);
    signal over     : std_logic;

    -- active-low segments, bit 0 = a
    function seg7(d : std_logic_vector(3 downto 0)) return std_logic_vector is
    begin
        case d is
            when x"0" => return "1000000";
            when x"1" => return "1111001";
            when x"2" => return "0100100";
            when x"3" => return "0110000";
            when x"4" => return "0011001";
            when x"5" => return "0010010";
            when x"6" => return "0000010";
            when x"7" => return "1111000";
            when x"8" => return "0000000";
            when x"9" => return "0010000";
            when others => return "1111111";
        end case;
    end seg7;
begin
    process (CLOCK_50)
    begin
        if rising_edge(CLOCK_50) then
            clk25 <= not clk25;
        end if;
    end process;

    timing : entity work.vga_timing
        port map (clk25, hs, vs, video_on, row, col);

    core : entity work.tetris_core
        port map (
            clk => clk25, reset_n => KEY(0), ps2_clk => PS2_CLK, ps2_data => PS2_DAT,
            vert_sync => vs, pixel_row => row, pixel_col => col,
            start_level => SW(3 downto 0), force_piece => "111", show_ghost => SW(9),
            red => r, green => g, blue => b,
            lines_bcd => lines, level_bcd => level, game_over => over);

    -- register color with the syncs so all of them change on the same edge
    process (clk25)
    begin
        if rising_edge(clk25) then
            VGA_HS <= hs;
            VGA_VS <= vs;
            if video_on = '1' then
                VGA_R <= r;  VGA_G <= g;  VGA_B <= b;
            else
                VGA_R <= "0000";  VGA_G <= "0000";  VGA_B <= "0000";
            end if;
        end if;
    end process;

    HEX0 <= seg7(lines(3 downto 0));
    HEX1 <= seg7(lines(7 downto 4));
    HEX2 <= seg7(lines(11 downto 8));
    HEX3 <= seg7(lines(15 downto 12));
    LEDG <= level;
    LEDR <= over & "000000000";
end rtl;
