--------------------------------------------------------------------------------
-- Title       : FT232HPQ interface
-- Project     : ELIX_LowLat_DVBT2
--------------------------------------------------------------------------------
-- File        : ft232_interface.vhd
-- Author      : Bastien Pillonel <bastien.pillonel@heig-vd.ch>
-- Company     : HEIG-VD
-- Created     : Thu Dec 11 11:39:18 2025
-- Last update : Fri Dec 12 10:29:40 2025
-- Platform    : Default Part Number
-- Standard    : <VHDL-2008>
--------------------------------------------------------------------------------
-- Copyright (c) 2025 HEIG-VD
-------------------------------------------------------------------------------
-- Description: This file describe an FT232HPQ interface that will receive TS 
-- packet from host computer.
--------------------------------------------------------------------------------
-- Revisions:  Revisions and documentation are controlled by
-- the revision control system (RCS).  The RCS should be consulted
-- on revision history.
-------------------------------------------------------------------------------



LIBRARY IEEE;
USE IEEE.std_logic_1164.ALL ;
USE IEEE.std_logic_arith.ALL ;

entity ft232_interface is 
    port(
        -- 60MHz clock for operation with FT232HPQ in sync fifo mode
        ft_clock : in std_logic;
        reset_n : in std_logic;

        -- FT232HPQ interface signal
        ft_data : inout std_logic_vector(7 downto 0);
        ft_rxf_n : in std_logic;
        ft_txe_n : in std_logic;
        ft_rd_n  : out std_logic;
        ft_wr_n  : out std_logic;
        ft_oe_n  : out std_logic;
        ft_siwu_n  : out std_logic;

        -- FIFO side RX USB -> FPGA
        rx_data : out std_logic_vector(7 downto 0);
        rx_valid : out std_logic;
        rx_ready : in std_logic;

        -- FIFO side TX FPGA -> USB
        tx_data : in std_logic_vector(7 downto 0);
        tx_valid : in std_logic;
        tx_ready : out std_logic
    );
end ft232_interface;

architecture internal of ft232_interface is 

    type state_t is (
        IDLE,
        RX_OE,
        RX_RD,
        TX
    );

    signal state : state_t := IDLE;
    signal data_out : std_logic_vector(7 downto 0);
    -- 0 => read data from FT232HPQ | 1 => write data to the FT232HPQ
    signal data_dir : std_logic := '0';

    signal rxf_n_reg : std_logic;
    signal txe_n_reg : std_logic;

begin

    -- Tristate buffer for FT232 data
    ft_data <= data_out when data_dir = '1' else (others => 'Z');

    ----------------------------------------------------------------------------
    -- RXF and TXE synchronous registration
    rxf_txe_sync : process (ft_clock, reset_n)
    begin
        if (reset_n = '0') then
            rxf_n_reg <= '1';
            txe_n_reg <= '1';

        elsif (rising_edge(ft_clock)) then
            rxf_n_reg <= ft_rxf_n;
            txe_n_reg <= ft_txe_n;

        end if;
    end process;
    ----------------------------------------------------------------------------

    ----------------------------------------------------------------------------
    -- FT232HPQ RX/TX handling process
    rx_tx_handling : process(ft_clock, reset_n)
    begin
        if (reset_n = '0') then
            state <= IDLE;

            ft_rd_n <= '1';
            ft_wr_n <= '1';
            ft_oe_n <= '1';
            ft_siwu_n <= '1';

            data_out <= (others =>'0');
            data_dir <= '0';

            rx_data <= (others => '0');
            rx_valid <= '0';
            tx_ready <= '0';

        elsif (rising_edge(ft_clock)) then
            -- Default state
            state <= IDLE;

            ft_rd_n <= '1';
            ft_wr_n <= '1';
            ft_oe_n <= '1';
            ft_siwu_n <= '1';

            data_out  <= (others => '0');
            data_dir  <= '0';

            rx_valid <= '0';
            tx_ready <= '0';

            case state is 
                when IDLE => 
                    -- Priority on read from USB action when data are available
                    if ((rxf_n_reg = '0') and (rx_ready = '1')) then
                        ft_oe_n <= '0';
                        state <= RX_OE;

                    elsif ((txe_n_reg = '0') and (tx_valid = '1')) then
                        data_dir <= '1';
                        data_out <= tx_data;
                        ft_wr_n <= '0';
                        state <= TX;

                    end if;
                when RX_OE =>
                    ft_oe_n <= '0';
                    ft_rd_n <= '0';
                    state <= RX_RD;

                when RX_RD => 
                    -- End of reading stream condition
                    if ((rxf_n_reg = '1') or (rx_ready = '0')) then
                        ft_oe_n <= '1';
                        ft_rd_n <= '1';
                    else
                        ft_oe_n <= '0';
                        ft_rd_n <= '0';
                        rx_data <= ft_data;
                        rx_valid <= '1';
                        state <= RX_RD;
                    end if;

                when TX =>
                    -- Pulse to indicate tx can output next byte
                    tx_ready <= '1';

                when others =>
                    state <= IDLE;
            end case;
        end if;
    end process;

end internal;