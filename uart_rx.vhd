library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity Receiver_rxd is
    generic (
        g_CLK_FREQ    : natural := 100000000; -- Tần số clock 100 MHz
        g_BAUD_RATE   : natural := 9600;        -- Tốc độ Baud
        g_OVERSAMPLE  : natural := 4             -- Lấy mẫu 4x
    );
    port (
        i_clk         : in  std_logic;   
        i_reset       : in  std_logic;
        i_rxd         : in  std_logic;
        o_RxData      : out std_logic_vector(7 downto 0);
        o_RxData_valid : out std_logic
    );
end entity Receiver_rxd;

architecture rtl of Receiver_rxd is

    -- Hằng số tính toán
    constant c_BAUD_TICK_MAX : natural := (g_CLK_FREQ / (g_BAUD_RATE * g_OVERSAMPLE)) - 1;
    constant c_SAMPLE_MID    : natural := (g_OVERSAMPLE / 2);
    constant c_BIT_MAX       : natural := 7; -- Đếm từ 0 đến 7 cho 8 bit dữ liệu

    -- Các trạng thái FSM
    type t_state is (s_IDLE, s_START_BIT, s_RX_DATA, s_STOP_BIT);
    signal r_state : t_state := s_IDLE;

    -- Bộ đếm
    signal r_baud_tick_cnt : natural range 0 to c_BAUD_TICK_MAX := 0;
    signal r_sample_cnt    : natural range 0 to g_OVERSAMPLE - 1 := 0;
    signal r_bit_cnt       : natural range 0 to c_BIT_MAX := 0;

    -- Thanh ghi dịch
    signal r_rx_shift_reg : std_logic_vector(7 downto 0) := (others => '0');

    -- Tín hiệu nội bộ
    signal w_tick : std_logic := '0';

    -- Thanh ghi cho đầu ra
    signal r_RxData       : std_logic_vector(7 downto 0) := (others => '0');
    signal r_RxData_valid : std_logic := '0';

begin

    -- 1. BỘ TẠO TICK (Tốc độ 4x Baud Rate)
    -- Process này chạy ở 100MHz để tạo ra xung 'w_tick'
    p_BAUD_TICK_GEN : process(i_clk)
    begin
        if rising_edge(i_clk) then
            if i_reset = '1' then
                r_baud_tick_cnt <= 0;
                w_tick          <= '0';
            else
                w_tick <= '0'; -- Xung tick chỉ kéo dài 1 chu kỳ clock
                if r_baud_tick_cnt = c_BAUD_TICK_MAX then
                    r_baud_tick_cnt <= 0;
                    w_tick          <= '1';
                else
                    r_baud_tick_cnt <= r_baud_tick_cnt + 1;
                end if;
            end if;
        end if;
    end process p_BAUD_TICK_GEN;


    -- 2. MÁY TRẠNG THÁI (FSM) VÀ LOGIC NHẬN
    -- Process này chỉ thực thi logic khi có xung 'w_tick'
    p_FSM_RX : process(i_clk)
    begin
        if rising_edge(i_clk) then
            if i_reset = '1' then
                r_state        <= s_IDLE;
                r_sample_cnt   <= 0;
                r_bit_cnt      <= 0;
                r_RxData_valid <= '0';
                
            elsif w_tick = '1' then
                -- Tín hiệu valid mặc định là 0, trừ khi được set
                r_RxData_valid <= '0';

                case r_state is
                    -- TRẠNG THÁI NHÀN RỖI: Chờ bit Start (rxd = 0)
                    when s_IDLE =>
                        if i_rxd = '0' then
                            r_state      <= s_START_BIT;
                            r_sample_cnt <= 0; -- Reset bộ đếm mẫu
                        end if;

                    -- TRẠNG THÁI BIT START: Xác nhận bit Start (chống nhiễu)
                    when s_START_BIT =>
                        if r_sample_cnt = c_SAMPLE_MID then
                            -- Kiểm tra lại rxd tại điểm giữa bit
                            if i_rxd = '0' then
                                -- OK, đây là bit start thật
                                r_state      <= s_RX_DATA;
                                r_sample_cnt <= 0; -- Reset đếm mẫu cho bit data đầu tiên
                                r_bit_cnt    <= 0; -- Chuẩn bị nhận bit 0
                            else
                                -- Báo động giả (nhiễu), quay về IDLE
                                r_state <= s_IDLE;
                            end if;
                        else
                            r_sample_cnt <= r_sample_cnt + 1;
                        end if;

                    -- TRẠNG THÁI NHẬN DỮ LIỆU: Nhận 8 bit data
                    when s_RX_DATA =>
                        if r_sample_cnt = c_SAMPLE_MID then
                            -- Lấy mẫu tại điểm giữa bit
                            -- Dịch bit LSB (i_rxd) vào trước
                            r_rx_shift_reg <= i_rxd & r_rx_shift_reg(7 downto 1);
                        end if;

                        if r_sample_cnt = g_OVERSAMPLE - 1 then
                            -- Đã hết 1 bit
                            r_sample_cnt <= 0; -- Reset đếm mẫu
                            if r_bit_cnt = c_BIT_MAX then
                                -- Đã nhận đủ 8 bit, chuyển sang bit Stop
                                r_state <= s_STOP_BIT;
                            else
                                -- Nhận bit tiếp theo
                                r_bit_cnt <= r_bit_cnt + 1;
                            end if;
                        else
                            r_sample_cnt <= r_sample_cnt + 1;
                        end if;

                    -- TRẠNG THÁI BIT STOP: Hoàn tất
                    when s_STOP_BIT =>
                        if r_sample_cnt = c_SAMPLE_MID then
                            -- (Có thể kiểm tra i_rxd = '1' ở đây để báo lỗi Framing Error)
                            
                            -- Gửi dữ liệu ra và báo hợp lệ
                            r_RxData       <= r_rx_shift_reg;
                            r_RxData_valid <= '1';
                            r_state        <= s_IDLE; -- Quay về nhàn rỗi
                        else
                            r_sample_cnt <= r_sample_cnt + 1;
                        end if;

                end case;
            end if;
        end if;
    end process p_FSM_RX;

    -- Gán các thanh ghi ra cổng đầu ra
    o_RxData       <= r_RxData;
    o_RxData_valid <= r_RxData_valid;

end architecture rtl;
