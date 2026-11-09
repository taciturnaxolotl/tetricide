-- 50 MHz to 25 MHz: a toggle flip-flop.
library ieee;
use ieee.std_logic_1164.all;

entity clk_div2 is
    port (
        clk_in  : in  std_logic;
        clk_out : out std_logic
    );
end clk_div2;

architecture rtl of clk_div2 is
    signal t : std_logic := '0';
begin
    process (clk_in)
    begin
        if rising_edge(clk_in) then
            t <= not t;
        end if;
    end process;
    clk_out <= t;
end rtl;
