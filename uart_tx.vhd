library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity tx is
    Port (
        clk      : in  std_logic;
        data     : in  std_logic_vector(7 downto 0);
        transmit : in  std_logic;
        reset    : in  std_logic;
        txd      : out std_logic
    );
end tx;

architecture Behavioral of tx is
    signal bit_cnt            : unsigned(3 downto 0) := (others => '0');
    signal baud_cnt           : unsigned(13 downto 0) := (others => '0');
    signal shiftright_register: std_logic_vector(9 downto 0) := (others => '1');
    signal state, next_state  : std_logic := '0';
    signal shift, load, clear : std_logic := '0';
begin

    -- UART Transmission process
    process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                state     <= '0';
                bit_cnt   <= (others => '0');
                baud_cnt  <= (others => '0');
            else
                baud_cnt <= baud_cnt + 1;
                if baud_cnt = to_unsigned(10415, 14) then
                    baud_cnt <= (others => '0');
                    state <= next_state;
                    if load = '1' then
                        shiftright_register <= '1' & data & '0';  -- stop + data + start
                    end if;
                    if clear = '1' then
                        bit_cnt <= (others => '0');
                    end if;
                    if shift = '1' then
                        shiftright_register <= '1' & shiftright_register(9 downto 1);
                        bit_cnt <= bit_cnt + 1;
                    end if;
                end if;
            end if;
        end if;
    end process;

    -- Mealy state machine
    process(clk)
    begin
        if rising_edge(clk) then
            load  <= '0';
            shift <= '0';
            clear <= '0';
            txd   <= '1';
            case state is
                when '0' =>
                    if transmit = '1' then
                        next_state <= '1';
                        load  <= '1';
                        shift <= '0';
                        clear <= '0';
                    else
                        next_state <= '0';
                        txd <= '1';
                    end if;
                when '1' =>
                    if bit_cnt = to_unsigned(10, 4) then
                        next_state <= '0';
                        clear <= '1';
                    else
                        next_state <= '1';
                        txd <= shiftright_register(0);
                        shift <= '1';
                    end if;
                when others =>
                    next_state <= '0';
            end case;
        end if;
    end process;

end Behavioral;
