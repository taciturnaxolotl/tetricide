-- Renders the sound block to sim/out/sound.wav (8 kHz, 8-bit) so it can be
-- heard without a board: title music, a lock, a clear, a four-line clear,
-- then game over.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.tetris_pkg.all;

entity tb_sound is
end tb_sound;

architecture sim of tb_sound is
    constant SECONDS : integer := 9;
    signal clk       : std_logic := '0';
    signal vs        : std_logic := '1';
    signal scene     : scene_t := SC_TITLE;
    signal e_lock, e_clear, e_tetris, e_over : std_logic := '0';
    signal spk_a, spk_b : std_logic;
    signal done      : boolean := false;
begin
    clk <= not clk after 20 ns when not done else '0';

    dut : entity work.sound
        port map (clk, '1', '0', vs, scene, 0, e_lock, e_clear, e_tetris, e_over, spk_a, spk_b, open);

    -- 60 Hz frames
    frames : process
    begin
        while not done loop
            vs <= '0'; wait for 64 us;
            vs <= '1'; wait for 16.6 ms;
        end loop;
        wait;
    end process;

    script : process
        procedure pulse(signal s : out std_logic) is
        begin
            wait until rising_edge(clk); s <= '1';
            wait until rising_edge(clk); s <= '0';
        end procedure;
    begin
        wait for 2 sec;   scene <= SC_GAME;
        wait for 1 sec;   pulse(e_lock);
        wait for 1 sec;   pulse(e_lock); pulse(e_clear);
        wait for 1.5 sec; pulse(e_lock); pulse(e_tetris);
        wait for 1.5 sec; pulse(e_over); scene <= SC_OVER;
        wait;
    end process;

    record_wav : process
        type char_file is file of character;
        file f : char_file;
        constant RATE : integer := 8000;
        constant N    : integer := RATE * SECONDS;
        procedure put32(v : integer) is
            variable u : unsigned(31 downto 0) := to_unsigned(v, 32);
        begin
            for i in 0 to 3 loop
                write(f, character'val(to_integer(u(i * 8 + 7 downto i * 8))));
            end loop;
        end procedure;
        procedure put16(v : integer) is
        begin
            write(f, character'val(v mod 256));
            write(f, character'val(v / 256));
        end procedure;
        procedure puts(s : string) is
        begin
            for i in s'range loop write(f, s(i)); end loop;
        end procedure;
    begin
        file_open(f, "sim/out/sound.wav", write_mode);
        puts("RIFF"); put32(36 + N); puts("WAVEfmt ");
        put32(16); put16(1); put16(1); put32(RATE); put32(RATE); put16(1); put16(8);
        puts("data"); put32(N);
        for i in 1 to N loop
            wait for 125 us;
            if spk_a = '1' then
                write(f, character'val(176));
            elsif spk_b = '1' then
                write(f, character'val(80));
            else
                write(f, character'val(128));
            end if;
        end loop;
        file_close(f);
        report "wrote sim/out/sound.wav";
        done <= true;
        wait;
    end process;
end sim;
