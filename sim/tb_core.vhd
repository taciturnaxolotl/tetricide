-- Plays a scripted game through real PS/2 frames, checks the board by
-- sampling the renderer at cell centers, and writes 640x480 screenshots.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.tetris_pkg.all;

entity tb_core is
end tb_core;

architecture sim of tb_core is
    signal clk         : std_logic := '0';
    signal reset_n     : std_logic := '0';
    signal ps2_clk     : std_logic := '1';
    signal ps2_data    : std_logic := '1';
    signal vert_sync   : std_logic := '1';
    signal pixel_row   : std_logic_vector(9 downto 0) := (others => '0');
    signal pixel_col   : std_logic_vector(9 downto 0) := (others => '0');
    signal force_piece : std_logic_vector(2 downto 0) := "000";
    signal red, green, blue : std_logic_vector(3 downto 0);
    signal lines_bcd   : std_logic_vector(15 downto 0);
    signal level_bcd   : std_logic_vector(7 downto 0);
    signal game_over   : std_logic;
    signal spk_p       : std_logic;
    signal done        : boolean := false;

    constant WELL : rgb_t := x"102";

    -- piece indices, to keep the script readable
    constant P_I : std_logic_vector(2 downto 0) := "000";
    constant P_O : std_logic_vector(2 downto 0) := "001";
    constant P_T : std_logic_vector(2 downto 0) := "010";
    constant P_RANDOM : std_logic_vector(2 downto 0) := "111";

    constant K_LEFT  : integer := 16#6B#;
    constant K_RIGHT : integer := 16#74#;
    constant K_UP    : integer := 16#75#;
    constant K_SPACE : integer := 16#29#;
begin
    clk <= not clk after 20 ns when not done else '0';

    dut : entity work.tetris_core
        port map (
            clk => clk, reset_n => reset_n, ps2_clk => ps2_clk, ps2_data => ps2_data,
            vert_sync => vert_sync, pixel_row => pixel_row, pixel_col => pixel_col,
            start_level => "0000", force_piece => force_piece, show_ghost => '1', sound_en => '1', sound_test => '0',
            red => red, green => green, blue => blue,
            lines_bcd => lines_bcd, level_bcd => level_bcd, game_over => game_over,
            spk_p => spk_p, spk_n => open, spk_on => open);

    script : process
        type char_file is file of character;
        variable fails : integer := 0;

        procedure tick(n : integer) is
        begin
            for i in 1 to n loop
                vert_sync <= '0';
                wait for 400 ns;
                vert_sync <= '1';
                wait for 80 us;
            end loop;
        end tick;

        procedure send_byte(b : integer) is
            variable v      : std_logic_vector(7 downto 0) := std_logic_vector(to_unsigned(b, 8));
            variable bits   : std_logic_vector(10 downto 0);
            variable parity : std_logic := '1';
        begin
            for i in 0 to 7 loop
                parity := parity xor v(i);
            end loop;
            bits := '1' & parity & v & '0';  -- stop, parity, data, start
            for i in 0 to 10 loop
                ps2_data <= bits(i);
                wait for 2.5 us;
                ps2_clk <= '0';
                wait for 5 us;
                ps2_clk <= '1';
                wait for 2.5 us;
            end loop;
            ps2_data <= '1';
            wait for 20 us;
        end send_byte;

        -- press and release one key, one frame each
        procedure tap(code : integer; ext : boolean) is
        begin
            if ext then send_byte(16#E0#); end if;
            send_byte(code);
            tick(1);
            if ext then send_byte(16#E0#); end if;
            send_byte(16#F0#);
            send_byte(code);
            tick(1);
        end tap;

        procedure taps(code : integer; ext : boolean; n : integer) is
        begin
            for i in 1 to n loop
                tap(code, ext);
            end loop;
        end taps;

        procedure drop is
        begin
            tap(K_SPACE, false);
        end drop;

        function at_cell(bx, by : integer) return std_logic_vector is
        begin
            return std_logic_vector(to_unsigned(96 + by * 16 + 7, 10))
                 & std_logic_vector(to_unsigned(240 + bx * 16 + 7, 10));
        end at_cell;

        procedure expect_cell(bx, by : integer; want : rgb_t; what : string) is
            variable pos : std_logic_vector(19 downto 0) := at_cell(bx, by);
            variable got : rgb_t;
        begin
            pixel_row <= pos(19 downto 10);
            pixel_col <= pos(9 downto 0);
            wait for 1 ns;
            got := red & green & blue;
            if got /= want then
                report "FAIL " & what & ": cell (" & integer'image(bx) & "," & integer'image(by)
                     & ") is " & integer'image(to_integer(unsigned(got)))
                     & ", wanted " & integer'image(to_integer(unsigned(want))) severity error;
                fails := fails + 1;
            end if;
        end expect_cell;

        procedure expect(ok : boolean; what : string) is
        begin
            if not ok then
                report "FAIL " & what severity error;
                fails := fails + 1;
            end if;
        end expect;

        procedure screenshot(name : string) is
            file f : char_file;
            constant HEADER : string := "P6 640 480 255" & LF;
        begin
            file_open(f, "sim/out/" & name & ".ppm", write_mode);
            for i in HEADER'range loop
                write(f, HEADER(i));
            end loop;
            for y in 0 to 479 loop
                for x in 0 to 639 loop
                    pixel_row <= std_logic_vector(to_unsigned(y, 10));
                    pixel_col <= std_logic_vector(to_unsigned(x, 10));
                    wait for 1 ns;
                    write(f, character'val(to_integer(unsigned(red)) * 17));
                    write(f, character'val(to_integer(unsigned(green)) * 17));
                    write(f, character'val(to_integer(unsigned(blue)) * 17));
                end loop;
            end loop;
            file_close(f);
            report "screenshot " & name;
        end screenshot;

        constant CYAN   : rgb_t := palette(1, 0);
        constant YELLOW : rgb_t := palette(2, 0);
        constant PURPLE : rgb_t := palette(3, 0);
    begin
        force_piece <= P_I;
        wait for 1 us;
        reset_n <= '1';
        -- title pours in, letters drop
        tick(16);
        screenshot("00a_title_pour");
        tick(40);
        screenshot("00b_title");
        drop;
        tick(14);
        screenshot("00c_melt");
        tick(30);
        screenshot("00d_pour_game");
        tick(30);
        screenshot("01_spawn");
        expect_cell(3, 1, CYAN, "I spawns at columns 3-6");
        expect_cell(6, 1, CYAN, "I spawns at columns 3-6");

        -- I to the far left, drop
        taps(K_LEFT, true, 3);
        expect_cell(0, 1, CYAN, "I moved left three");
        drop;
        expect_cell(0, 19, CYAN, "I landed on the floor");
        expect_cell(3, 19, CYAN, "I landed on the floor");

        -- second I, one right, drop; then an O
        force_piece <= P_O;
        tap(K_RIGHT, true);
        drop;
        expect_cell(4, 19, CYAN, "second I at columns 4-7");
        expect_cell(7, 19, CYAN, "second I at columns 4-7");

        -- O to the right wall completes the bottom row
        force_piece <= P_T;
        taps(K_RIGHT, true, 4);
        expect_cell(9, 1, YELLOW, "O at the right wall");
        drop;
        tick(1);
        screenshot("02a_flash");
        tick(5);
        screenshot("02b_dissolve");
        tick(12);
        expect(lines_bcd = x"0001", "one line cleared");
        expect_cell(8, 19, YELLOW, "O top half shifted down");
        expect_cell(9, 19, YELLOW, "O top half shifted down");
        expect_cell(0, 19, WELL, "cleared row is empty");
        expect_cell(8, 18, WELL, "nothing above the O");
        screenshot("02_clear");

        -- T: rotate clockwise, then let gravity pull it one row
        tap(K_UP, true);
        expect_cell(4, 0, PURPLE, "T rotated: stem top");
        expect_cell(4, 2, PURPLE, "T rotated: stem bottom");
        expect_cell(5, 1, PURPLE, "T rotated: nub");
        expect_cell(3, 1, WELL, "T rotated: old arm gone");
        tick(48);
        expect_cell(4, 3, PURPLE, "gravity moved T down one row");
        expect_cell(4, 0, WELL, "gravity moved T down one row");
        screenshot("03_rotate");

        -- stack O pieces in the middle until the game ends
        force_piece <= P_O;
        for i in 1 to 14 loop
            exit when game_over = '1';
            drop;
        end loop;
        expect(game_over = '1', "stacking to the top ends the game");
        tick(14);
        screenshot("04a_curtain");
        drop;
        expect(game_over = '1', "space is ignored until the curtain is up");
        tick(28);
        screenshot("04b_melt");
        tick(64);
        screenshot("04c_over");

        -- space restarts
        force_piece <= P_RANDOM;
        drop;
        tick(70);
        expect(game_over = '0', "space restarts");
        expect(lines_bcd = x"0000", "restart clears lines");

        -- a few random pieces scattered around, for a nice picture
        for i in 0 to 13 loop
            if i mod 3 = 1 then
                tap(K_UP, true);
            end if;
            if i mod 4 < 2 then
                taps(K_LEFT, true, (i * 7) mod 5);
            else
                taps(K_RIGHT, true, (i * 3) mod 5);
            end if;
            drop;
        end loop;
        tick(3);
        screenshot("05_random");

        if fails = 0 then
            report "PASS: all checks";
        else
            report integer'image(fails) & " check(s) failed" severity failure;
        end if;
        done <= true;
        wait;
    end process;
end sim;
