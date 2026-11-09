-- Registers the color with the syncs so they all change on the same edge,
-- and blanks the color outside the visible area.
library ieee;
use ieee.std_logic_1164.all;

entity vga_out is
    port (
        clk      : in  std_logic;
        h_sync   : in  std_logic;
        v_sync   : in  std_logic;
        video_on : in  std_logic;
        red      : in  std_logic_vector(3 downto 0);
        green    : in  std_logic_vector(3 downto 0);
        blue     : in  std_logic_vector(3 downto 0);
        vga_r    : out std_logic_vector(3 downto 0);
        vga_g    : out std_logic_vector(3 downto 0);
        vga_b    : out std_logic_vector(3 downto 0);
        vga_hs   : out std_logic;
        vga_vs   : out std_logic
    );
end vga_out;

architecture rtl of vga_out is
begin
    process (clk)
    begin
        if rising_edge(clk) then
            vga_hs <= h_sync;
            vga_vs <= v_sync;
            if video_on = '1' then
                vga_r <= red;  vga_g <= green;  vga_b <= blue;
            else
                vga_r <= "0000";  vga_g <= "0000";  vga_b <= "0000";
            end if;
        end if;
    end process;
end rtl;
