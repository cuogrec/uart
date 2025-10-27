library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tx is
    generic (
        g_CLK_FREQ  : natural := 100000000; -- Clock 100 MHz
        g_BAUD_RATE : natural := 9600       -- Baud rate 9600
    );
    port (
        clk        : in  std_logic;
        reset      : in  std_logic;
        data       : in  std_logic_vector(7 downto 0);
        transmit   : in  std_logic;  -- Nhấn để gửi (nhận 1 xung đã khử dội)
        txd        : out std_logic;
        o_tx_ready : out std_logic   -- '1' rảnh, '0' bận
    );
end entity tx;

architecture rtl of tx is
  -- ===== Baud generator =====
  constant c_BAUD_CNT_MAX : natural := (g_CLK_FREQ / g_BAUD_RATE) - 1;

  -- ===== FSM =====
  type t_state is (s_IDLE, s_SEND_START, s_SEND_DATA, s_SEND_STOP);
  signal r_state : t_state := s_IDLE;

  -- ===== Baud/Tick control =====
  signal r_baud_cnt     : natural range 0 to c_BAUD_CNT_MAX := 0;
  signal w_tick         : std_logic := '0';
  signal r_tick_en      : std_logic := '0'; -- chỉ đếm khi đang gửi
  signal r_tick_restart : std_logic := '0'; -- reset bộ đếm để đảm bảo đủ 1 bit

  -- ===== Shift/Data =====
  signal r_bit_cnt      : natural range 0 to 7 := 0;
  signal r_tx_shift_reg : std_logic_vector(9 downto 0) := (others => '1');

  -- ===== Ready =====
  signal r_tx_ready     : std_logic := '1';

  -- ===== Debounce cho transmit =====
  signal s_sync1, s_sync2 : std_logic := '0';
  signal s_debounced      : std_logic := '0';
  signal s_deb_last       : std_logic := '0';
  signal s_start_pulse    : std_logic := '0';

  -- ~10 ms @100 MHz ≈ 1,000,000 xung (2^20 > 1e6)
  signal r_deb_cnt        : unsigned(19 downto 0) := (others => '0');
  constant C_DEB_MAX      : unsigned(19 downto 0) := to_unsigned(1_000_000-1, 20);

begin
  -- =========================
  -- 1) Đồng bộ + Khử dội + Pulse 1 chu kỳ cho 'transmit'
  -- =========================
  p_SYNC_DEB: process(clk)
  begin
    if rising_edge(clk) then
      if reset = '1' then
        s_sync1       <= '0';
        s_sync2       <= '0';
        s_debounced   <= '0';
        s_deb_last    <= '0';
        s_start_pulse <= '0';
        r_deb_cnt     <= (others => '0');
      else
        -- 2 FF sync
        s_sync1 <= transmit;
        s_sync2 <= s_sync1;

        -- Debounce
        if s_sync2 = s_debounced then
          r_deb_cnt <= (others => '0');
        else
          if r_deb_cnt = C_DEB_MAX then
            s_debounced <= s_sync2;
            r_deb_cnt   <= (others => '0');
          else
            r_deb_cnt <= r_deb_cnt + 1;
          end if;
        end if;

        -- Tạo xung 1 chu kỳ ở cạnh lên (sau khi đã debounced)
        s_start_pulse <= (not s_deb_last) and s_debounced;
        s_deb_last    <= s_debounced;
      end if;
    end if;
  end process;

  -- =========================
  -- 2) Baud tick có enable + restart
  -- =========================
  p_BAUD: process(clk)
  begin
    if rising_edge(clk) then
      if reset = '1' then
        r_baud_cnt <= 0;
        w_tick     <= '0';
      else
        w_tick <= '0';
        if r_tick_restart = '1' then
          r_baud_cnt <= 0;             -- đảm bảo bit hiện tại đủ 1 chu kỳ baud
        elsif r_tick_en = '1' then
          if r_baud_cnt = c_BAUD_CNT_MAX then
            r_baud_cnt <= 0;
            w_tick     <= '1';
          else
            r_baud_cnt <= r_baud_cnt + 1;
          end if;
        end if;
      end if;
    end if;
  end process;   

  -- =========================
  -- 3) FSM TX
  -- =========================
  p_FSM_TX: process(clk)
  begin
    if rising_edge(clk) then
      if reset = '1' then
        r_state        <= s_IDLE;
        r_tx_ready     <= '1';
        r_bit_cnt      <= 0;
        r_tick_en      <= '0';
        r_tick_restart <= '0';
        txd            <= '1';
      else
        -- Defaults mỗi chu kỳ
        r_tick_restart <= '0';

        case r_state is
          -- IDLE: chờ start_pulse
          when s_IDLE =>
            r_tx_ready <= '1';
            r_tick_en  <= '0';
            txd        <= '1';

            if s_start_pulse = '1' then
              -- Nạp khung: Stop(1) + Data[7:0] + Start(0), LSB trước
              r_tx_shift_reg <= '1' & data & '0';
              r_tx_ready     <= '0';
              r_bit_cnt      <= 0;
              r_tick_en      <= '1';
              r_tick_restart <= '1';  -- đảm bảo START đủ 1 baud từ bây giờ
              r_state        <= s_SEND_START;
            end if;

          -- Gửi START (bit 0)
          when s_SEND_START =>
            txd <= r_tx_shift_reg(0);
            if w_tick = '1' then
              r_tx_shift_reg <= '1' & r_tx_shift_reg(9 downto 1);
              r_state        <= s_SEND_DATA;
            end if;

          -- Gửi 8 bit DATA
          when s_SEND_DATA =>
            txd <= r_tx_shift_reg(0);
            if w_tick = '1' then
              r_tx_shift_reg <= '1' & r_tx_shift_reg(9 downto 1);
              if r_bit_cnt = 7 then
                r_state <= s_SEND_STOP;
              else
                r_bit_cnt <= r_bit_cnt + 1;
              end if;
            end if;

          -- Gửi STOP (bit 1)
          when s_SEND_STOP =>
            txd <= r_tx_shift_reg(0);     -- sẽ là '1'
            if w_tick = '1' then
              r_tick_en  <= '0';          -- tắt baud ngay khi xong khung
              r_state    <= s_IDLE;
            end if;
        end case;
      end if;
    end if;
  end process;

  -- =========================
  -- 4) Outputs
  -- =========================
  o_tx_ready <= r_tx_ready;

end architecture rtl;
