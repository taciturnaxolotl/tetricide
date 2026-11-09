-- Four BCD digits to the four active-low seven-segment displays.
library ieee;
use ieee.std_logic_1164.all;

entity hex4 is
    port (
        bcd  : in  std_logic_vector(15 downto 0);
        hex3 : out std_logic_vector(6 downto 0);
        hex2 : out std_logic_vector(6 downto 0);
        hex1 : out std_logic_vector(6 downto 0);
        hex0 : out std_logic_vector(6 downto 0)
    );
end hex4;

architecture rtl of hex4 is
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
    hex3 <= seg7(bcd(15 downto 12));
    hex2 <= seg7(bcd(11 downto 8));
    hex1 <= seg7(bcd(7 downto 4));
    hex0 <= seg7(bcd(3 downto 0));
end rtl;
