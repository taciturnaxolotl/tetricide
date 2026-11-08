-- 640x480 @ 60 Hz from a 25 MHz pixel clock. Syncs are active low.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity vga_timing is
    port (
        clk       : in  std_logic;
        h_sync    : out std_logic;
        v_sync    : out std_logic;
        video_on  : out std_logic;
        pixel_row : out std_logic_vector(9 downto 0);
        pixel_col : out std_logic_vector(9 downto 0)
    );
end vga_timing;

architecture rtl of vga_timing is
    signal h : unsigned(9 downto 0) := (others => '0');  -- 0..799
    signal v : unsigned(9 downto 0) := (others => '0');  -- 0..524
begin
    process (clk)
    begin
        if rising_edge(clk) then
            if h = 799 then
                h <= (others => '0');
                if v = 524 then
                    v <= (others => '0');
                else
                    v <= v + 1;
                end if;
            else
                h <= h + 1;
            end if;
        end if;
    end process;

    h_sync    <= '0' when h >= 656 and h < 752 else '1';
    v_sync    <= '0' when v >= 490 and v < 492 else '1';
    video_on  <= '1' when h < 640 and v < 480 else '0';
    pixel_col <= std_logic_vector(h);
    pixel_row <= std_logic_vector(v);
end rtl;
