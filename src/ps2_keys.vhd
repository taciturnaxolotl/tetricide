-- PS/2 keyboard decoder, clocked by the system clock rather than the
-- keyboard's, so a dropped or glitched bit can't leave it out of step.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity ps2_keys is
    port (
        clk       : in  std_logic;  -- 25 MHz
        reset_n   : in  std_logic;
        ps2_clk   : in  std_logic;
        ps2_data  : in  std_logic;
        k_left    : out std_logic;
        k_right   : out std_logic;
        k_down    : out std_logic;
        k_cw      : out std_logic;
        k_ccw     : out std_logic;
        k_drop    : out std_logic;
        key_event : out std_logic   -- one clock on every make or break
    );
end ps2_keys;

architecture rtl of ps2_keys is
    constant TIMEOUT : integer := 32767;  -- ~1.3 ms without a clock edge

    signal clk_sync  : std_logic_vector(1 downto 0) := "11";
    signal dat_sync  : std_logic_vector(1 downto 0) := "11";
    signal clk_hist  : std_logic_vector(7 downto 0) := (others => '1');
    signal clk_filt  : std_logic := '1';
    signal shift     : std_logic_vector(10 downto 0) := (others => '0');
    signal nbits     : integer range 0 to 11 := 0;
    signal idle      : integer range 0 to TIMEOUT := 0;
    signal ext, brk  : std_logic := '0';
    signal held      : std_logic_vector(5 downto 0) := (others => '0');  -- drop ccw cw down right left
begin
    k_left  <= held(0);
    k_right <= held(1);
    k_down  <= held(2);
    k_cw    <= held(3);
    k_ccw   <= held(4);
    k_drop  <= held(5);

    process (clk)
        variable frame  : std_logic_vector(10 downto 0);
        variable code   : std_logic_vector(7 downto 0);
        variable parity : std_logic;
        variable make   : std_logic;
    begin
        if rising_edge(clk) then
            key_event <= '0';
            clk_sync  <= clk_sync(0) & ps2_clk;
            dat_sync  <= dat_sync(0) & ps2_data;
            clk_hist  <= clk_hist(6 downto 0) & clk_sync(1);

            if idle < TIMEOUT then
                idle <= idle + 1;
            else
                nbits <= 0;
            end if;

            if clk_hist = x"FF" then
                clk_filt <= '1';
            elsif clk_hist = x"00" and clk_filt = '1' then
                -- filtered falling edge: one bit is on the data line
                clk_filt <= '0';
                idle     <= 0;
                frame    := dat_sync(1) & shift(10 downto 1);
                shift    <= frame;
                if nbits = 10 then
                    nbits  <= 0;
                    -- frame(0) start, frame(8 downto 1) data LSB first, frame(9) parity, frame(10) stop
                    code   := frame(8 downto 1);
                    parity := '0';
                    for i in 1 to 9 loop
                        parity := parity xor frame(i);
                    end loop;
                    if frame(0) = '0' and frame(10) = '1' and parity = '1' then
                        if code = x"E0" then
                            ext <= '1';
                        elsif code = x"F0" then
                            brk <= '1';
                        else
                            make := not brk;
                            case code is
                                when x"6B" | x"1C" => held(0) <= make;
                                when x"74" | x"23" => held(1) <= make;
                                when x"72" | x"1B" => held(2) <= make;
                                when x"75" | x"1D" | x"22" => held(3) <= make;
                                when x"1A" => held(4) <= make;
                                when x"29" => held(5) <= make;
                                when others => null;
                            end case;
                            key_event <= '1';
                            ext <= '0';
                            brk <= '0';
                        end if;
                    end if;
                else
                    nbits <= nbits + 1;
                end if;
            end if;

            if reset_n = '0' then
                held  <= (others => '0');
                nbits <= 0;
                ext   <= '0';
                brk   <= '0';
            end if;
        end if;
    end process;
end rtl;
