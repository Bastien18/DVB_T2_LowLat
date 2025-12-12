library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity ft232h_sync245_if_tb is
end entity;

architecture tb of ft232h_sync245_if_tb is

    ------------------------------------------------------------------------
    -- Constants
    ------------------------------------------------------------------------
    constant CLK_PERIOD : time := 16.667 ns; -- 60 MHz FT clock

    ------------------------------------------------------------------------
    -- DUT signals
    ------------------------------------------------------------------------
    signal ft_clk    : std_logic := '0';
    signal reset_n   : std_logic := '0';

    signal ft_data   : std_logic_vector(7 downto 0);
    signal ft_rxf_n  : std_logic := '1';
    signal ft_txe_n  : std_logic := '1';
    signal ft_rd_n   : std_logic;
    signal ft_wr_n   : std_logic;
    signal ft_oe_n   : std_logic;
    signal ft_siwu_n : std_logic;

    signal rx_data   : std_logic_vector(7 downto 0);
    signal rx_valid  : std_logic;
    signal rx_ready  : std_logic := '0';
    signal tx_data   : std_logic_vector(7 downto 0) := (others => '0');
    signal tx_valid  : std_logic := '0';
    signal tx_ready  : std_logic;

    ------------------------------------------------------------------------
    -- FT232 behavioral model state
    ------------------------------------------------------------------------
    type byte_array_t is array (natural range <>) of std_logic_vector(7 downto 0);

    -- Data that the "PC/FT232" will send to the FPGA (RX direction)
    constant FT_RX_PAYLOAD : byte_array_t := (
        x"47", x"01", x"02", x"03", x"04", x"05", x"06", x"07",
        x"08", x"09", x"0A", x"0B", x"0C", x"0D", x"0E", x"0F"
    );

    signal ft_rx_index        : integer range 0 to FT_RX_PAYLOAD'length := 0;
    signal ft_data_ft         : std_logic_vector(7 downto 0) := (others => 'Z');

    signal rd_n_prev_model    : std_logic := '1';
    signal wr_n_prev_model    : std_logic := '1';
    signal oe_n_prev_check    : std_logic := '1';
    signal rd_n_prev_check    : std_logic := '1';

    constant MAX_TX_BYTES     : integer := 16;
    signal tx_capture         : byte_array_t(0 to MAX_TX_BYTES-1);
    signal tx_capture_idx     : integer range 0 to MAX_TX_BYTES := 0;

begin

    ------------------------------------------------------------------------
    -- Bidirectional data bus modeling
    -- FT side drives ft_data only when FT's outputs are enabled
    -- (i.e., ft_oe_n = '0'). Otherwise the DUT is assumed to drive it.
    ------------------------------------------------------------------------
    ft_data <= ft_data_ft when ft_oe_n = '0' else (others => 'Z');

    ------------------------------------------------------------------------
    -- Clock generation (60 MHz)
    ------------------------------------------------------------------------
    clk_gen : process
    begin
        ft_clk <= '0';
        wait for CLK_PERIOD / 2;
        ft_clk <= '1';
        wait for CLK_PERIOD / 2;
    end process;

    ------------------------------------------------------------------------
    -- Reset generation
    ------------------------------------------------------------------------
    reset_proc : process
    begin
        reset_n <= '0';
        wait for 10 * CLK_PERIOD;
        reset_n <= '1';
        wait;
    end process;

    ------------------------------------------------------------------------
    -- DUT instantiation
    ------------------------------------------------------------------------
    dut_inst : entity work.ft232_interface
        port map (
            ft_clock    => ft_clk,
            reset_n   => reset_n,
            ft_data   => ft_data,
            ft_rxf_n  => ft_rxf_n,
            ft_txe_n  => ft_txe_n,
            ft_rd_n   => ft_rd_n,
            ft_wr_n   => ft_wr_n,
            ft_oe_n   => ft_oe_n,
            ft_siwu_n => ft_siwu_n,
            rx_data   => rx_data,
            rx_valid  => rx_valid,
            rx_ready  => rx_ready,
            tx_data   => tx_data,
            tx_valid  => tx_valid,
            tx_ready  => tx_ready
        );

    ------------------------------------------------------------------------
    -- FT232 synchronous FIFO READ behaviour (FT232 -> FPGA)
    --
    -- Models:
    --  * RXF# low when data available
    --  * Data driven when RXF#=0, OE#=0, RD#=0
    --  * Next byte after RD# rising edge
    ------------------------------------------------------------------------
    ft_read_model : process (ft_clk)
    begin
        if rising_edge(ft_clk) then
            if reset_n = '0' then
                ft_rx_index     <= 0;
                ft_rxf_n        <= '1';
                ft_data_ft      <= (others => 'Z');
                rd_n_prev_model <= '1';
            else
                -- remember previous RD# for edge detection (model side)
                rd_n_prev_model <= ft_rd_n;

                -- RXF# low while FT has data
                if ft_rx_index < (FT_RX_PAYLOAD'length -1) then
                    ft_rxf_n <= '0';
                else
                    ft_rxf_n <= '1';
                end if;

                -- When RXF# low, OE# low, RD# low => drive current byte
                if (ft_rxf_n = '0') and (ft_oe_n = '0') and (ft_rd_n = '0') then
                    ft_data_ft <= FT_RX_PAYLOAD(ft_rx_index);
                    if ft_rx_index < (FT_RX_PAYLOAD'length -1) then
                        ft_rx_index <= ft_rx_index + 1;
                    end if;
                end if;
            end if;
        end if;
    end process;

    ------------------------------------------------------------------------
    -- FT232 synchronous FIFO WRITE behaviour (FPGA -> FT232)
    --
    -- Models:
    --  * TXE# low while there is space
    --  * Data captured on WR# falling edge when TXE#=0
    --  * TXE# goes high when our simple buffer is "full"
    ------------------------------------------------------------------------
    ft_write_model : process (ft_clk)
    begin
        if rising_edge(ft_clk) then
            if reset_n = '0' then
                ft_txe_n        <= '1';  -- not ready during reset
                tx_capture_idx  <= 0;
                wr_n_prev_model <= '1';
            else
                wr_n_prev_model <= ft_wr_n;

                -- TXE# low while we "have space" in the model buffer
                if tx_capture_idx < MAX_TX_BYTES then
                    ft_txe_n <= '0';
                else
                    ft_txe_n <= '1'; -- pretend FT232 FIFO full
                end if;

                -- Capture data on WR# falling edge while TXE# low
                if (wr_n_prev_model = '1') and (ft_wr_n = '0') and (ft_txe_n = '0') then
                    if tx_capture_idx < MAX_TX_BYTES then
                        tx_capture(tx_capture_idx) <= ft_data;
                        report "FT232 model captured TX byte " &
                               integer'image(tx_capture_idx) & " = " &
                               to_hstring(ft_data);
                        tx_capture_idx <= tx_capture_idx + 1;
                    else
                        report "FT232 model: TX data lost (FIFO full)"
                          severity warning;
                    end if;
                end if;
            end if;
        end if;
    end process;

    ------------------------------------------------------------------------
    -- User-side stimulus (rx_ready, tx_valid/tx_data) + RX monitor
    ------------------------------------------------------------------------
    stimulus : process (ft_clk)
        variable sent_bytes : integer := 0;
    begin
        if rising_edge(ft_clk) then
            if reset_n = '0' then
                rx_ready   <= '0';
                tx_valid   <= '0';
                tx_data    <= (others => '0');
                sent_bytes := 0;
            else
                -- For this test, we are always ready to consume RX bytes
                rx_ready <= '1';

                -- Send a stream of bytes from FPGA to FT232
                if (tx_ready = '1') and (sent_bytes < MAX_TX_BYTES) then
                    tx_data  <= std_logic_vector(to_unsigned(16#A0# + sent_bytes, 8));
                    tx_valid <= '1';
                    sent_bytes := sent_bytes + 1;
                else
                    tx_valid <= '0';
                end if;

                -- Monitor received bytes (FT232 -> FPGA)
                if rx_valid = '1' then
                    report "User side received RX byte = " & to_hstring(rx_data);
                end if;
            end if;
        end if;
    end process;

    ------------------------------------------------------------------------
    -- Timing checker:
    --  Datasheet requires OE# asserted at least one clock before RD# low.
    --  Here we assert that on every RD# falling edge, OE# was already low
    --  in the previous clock cycle.
    ------------------------------------------------------------------------
    timing_check : process (ft_clk)
    begin
        if rising_edge(ft_clk) then
            if reset_n = '0' then
                oe_n_prev_check <= '1';
                rd_n_prev_check <= '1';
            else
                -- RD# falling edge?
                if (rd_n_prev_check = '1') and (ft_rd_n = '0') then
                    assert (oe_n_prev_check = '0')
                    report "Timing violation: RD# asserted without OE# low in previous cycle"
                    severity error;
                end if;

                oe_n_prev_check <= ft_oe_n;
                rd_n_prev_check <= ft_rd_n;
            end if;
        end if;
    end process;

    ------------------------------------------------------------------------
    -- End simulation after some time
    ------------------------------------------------------------------------
    end_sim : process
    begin
        wait for 5 ms;
        assert false report "End of simulation" severity failure;
    end process;

end architecture;
