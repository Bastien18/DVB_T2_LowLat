--------------------------------------------------------------------------------
-- Title       : ft232_bridge_dispatcher
-- Project     : ELIX_LowLat_DVBT2
--------------------------------------------------------------------------------
-- File        : ft232_bridge_dispatcher.vhd
-- Author      : Bastien Pillonel <bastien.pillonel@heig-vd.ch>
-- Company     : HEIG-VD
-- Created     : Thu Feb  5 10:51:46 2026
-- Last update : Thu Feb  5 10:54:56 2026
-- Platform    : Default Part Number
-- Standard    : <VHDL-2008>
--------------------------------------------------------------------------------
-- Copyright (c) 2026 HEIG-VD
-------------------------------------------------------------------------------
-- Description: 
--------------------------------------------------------------------------------
-- Revisions:  Revisions and documentation are controlled by
-- the revision control system (RCS).  The RCS should be consulted
-- on revision history.
-------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

library work;
use work.common_dcfifo_p.all;

entity ft232_bridge_dispatcher is
  port (
    -- 60MHz clock for operation with FT232 interface
    ft_clock : in std_logic;
    -- 80MHz clock for operation with NIOS II
    nios_clock : in std_logic;
    reset_n    : in std_logic;

    -- FIFO side RX USB -> FPGA
    ftdi_rx_data  : in std_logic_vector(7 downto 0);
    ftdi_rx_valid : in std_logic;
    ftdi_rx_ready : out std_logic;

    -- FIFO side TX FPGA -> USB
    ftdi_tx_data  : out std_logic_vector(7 downto 0);
    ftdi_tx_valid : out std_logic;
    ftdi_tx_ready : in std_logic;

    -- Avalon MM interface
    avs_address     : in std_logic_vector(3 downto 0);
    avs_read        : in std_logic;
    avs_write       : in std_logic;
    avs_readdata    : out std_logic_vector(31 downto 0);
    avs_writedata   : in std_logic_vector(31 downto 0);
    avs_waitrequest : out std_logic;

    -- DVB-T2 TS FIFO interface
    dvbt2_rx_ready : in std_logic;
    dvbt2_rx_valid : out std_logic;
    dvbt2_rx_data  : out std_logic_vector(7 downto 0)
  );
end ft232_bridge_dispatcher;

architecture internal of ft232_bridge_dispatcher is

  -- FIFO request interface 
  signal req_wrreq   : std_logic;
  signal req_data_in : std_logic_vector(31 downto 0);
  signal req_wrfull  : std_logic;
  signal req_wrusedw : std_logic_vector(7 downto 0);

  signal req_rdreq   : std_logic;
  signal req_q       : std_logic_vector(31 downto 0);
  signal req_rdempty : std_logic;
  signal req_rdusedw : std_logic_vector(7 downto 0);

  -- FIFO response interface
  signal resp_wrreq   : std_logic;
  signal resp_data_in : std_logic_vector(31 downto 0);
  signal resp_wrfull  : std_logic;
  signal resp_wrusedw : std_logic_vector(7 downto 0);

  signal resp_rdreq   : std_logic;
  signal resp_q       : std_logic_vector(31 downto 0);
  signal resp_rdempty : std_logic;
  signal resp_rdusedw : std_logic_vector(7 downto 0);

  -- Bridge interface related signal 
  type mode_t is (
    CTRL_RX,
    CTRL_PUSH_WORDS,
    CTRL_WAIT_RESP,
    CTRL_POP_WORDS,
    CTRL_TX_BYTES,
    DATA_FWD,
    TX_ACK
  );
  signal mode : mode_t := CTRL_RX;

  type pkt_buf_t is array(15 downto 0) of std_logic_vector(7 downto 0);
  signal pkt_buf   : pkt_buf_t;
  signal pkt_count : integer range 0 to 16 := 0;

  signal resp_buf   : pkt_buf_t;
  signal resp_count : integer range 0 to 16 := 0;

  signal ack_buf : pkt_buf_t;

  signal tx_countdown : unsigned(63 downto 0) := (others => '0');

  signal push_word_idx : integer range 0 to 4 := 0;
  signal pop_word_idx  : integer range 0 to 4 := 0;

begin

  ----------------------------------------------------------------------------
  -- REQUEST FIFO

  U_req_fifo : entity work.common_dcfifo
    generic map(
      LPM_NUMWORDS  => 256,
      LPM_WIDTH     => 32,
      LPM_WIDTH_R   => 32,
      LPM_SHOWAHEAD => "ON"
    )
    port map
    (
      aclr    => not reset_n,
      data    => req_data_in,
      rdclk   => nios_clock,
      rdreq   => req_rdreq,
      wrclk   => ft_clock,
      wrreq   => req_wrreq,
      q       => req_q,
      rdempty => req_rdempty,
      rdfull  => open,
      rdusedw => req_rdusedw,
      wrempty => open,
      wrfull  => req_wrfull,
      wrusedw => req_wrusedw
    );
  ----------------------------------------------------------------------------

  ----------------------------------------------------------------------------
  -- RESPONSE FIFO

  U_resp_fifo : entity work.common_dcfifo
    generic map(
      LPM_NUMWORDS => 256,
      LPM_WIDTH     => 32,
      LPM_WIDTH_R   => 32,
      LPM_SHOWAHEAD => "ON"
    )
    port map
    (
      aclr    => not reset_n,
      data    => resp_data_in,
      rdclk   => ft_clock,
      rdreq   => resp_rdreq,
      wrclk   => nios_clock,
      wrreq   => resp_wrreq,
      q       => resp_q,
      rdempty => resp_rdempty,
      rdfull  => open,
      rdusedw => resp_rdusedw,
      wrempty => open,
      wrfull  => resp_wrfull,
      wrusedw => resp_wrusedw
    );
  ----------------------------------------------------------------------------

  -- Let avalon slave be always available
  avs_waitrequest <= '0';

  ----------------------------------------------------------------------------
  -- Avalon MM slave FIFO hook
  -- Offset    Name          Access    Meaning
  -- 0x00      REQ_STATUS    R         bit0=req_rdempty, bit1=req_wrfull, bits 15:8 = optional req_rdusedw (bytes)
  -- 0x04      REQ_DATA      R         Pops 1 word from REQ FIFO and returns it in [31:0]
  -- 0x08      RESP_STATUS   R         bit0=resp_rdempty, bit1=resp_wrfull, bits 15:8 = optional resp_wrusedw
  -- 0x0c      RESP_DATA     W         Pushes 1 word into RESP FIFO (takes data from [31:0])
  --
  -- (Below are optional not implemented for now)
  -- 0x10      CTRL          R/W       bit0=SOFT_RESET (self-clears), 
  --                                   bit1=MODE_FORCE_CTRL (debug), 
  --                                   bit2=MODE_FORCE_DATA (debug)
  -- 0x14      IRQ_STATUS    R/W       bit0=REQ_GE_16, bit1=RESP_LE_? optional; write-1 clears
  -- 0x18      VERSION       R         Version
  avalon_mm_slave : process (reset_n, nios_clock)
  begin
    if (reset_n = '0') then
      avs_readdata <= (others => '0');
      req_rdreq    <= '0';
      resp_wrreq   <= '0';
      resp_data_in <= (others => '0');
    elsif (rising_edge(nios_clock)) then
      req_rdreq    <= '0';
      resp_wrreq   <= '0';
      avs_readdata <= (others => '0');

      if (avs_read = '1') then
        case avs_address is
            -- REQ_STATUS
          when "0000" =>
            avs_readdata(0)           <= req_rdempty;
            avs_readdata(1)           <= req_wrfull;
            avs_readdata(15 downto 8) <= req_rdusedw;

            -- REQ_DATA
          when "0001" =>
            if (req_rdempty = '0') then
              -- !!!!! WARNING look for timing issue when requesting a new byte from FIFO and reading this value at the same time !!!!
              req_rdreq    <= '1';
              avs_readdata <= req_q;
            else
              avs_readdata <= (others => '0');
            end if;

            -- RESP_STATUS
          when "0010" =>
            avs_readdata(0)           <= resp_rdempty;
            avs_readdata(1)           <= resp_wrfull;
            avs_readdata(15 downto 8) <= resp_wrusedw;

          when others =>
            null;

        end case;
      end if;

      if (avs_write = '1') then
        case avs_address is
            -- RESP_DATA
          when "0011" =>
            if (resp_wrfull = '0') then
              resp_wrreq   <= '1';
              resp_data_in <= avs_writedata;
            end if;

          when others =>
            null;

        end case;
      end if;
    end if;
  end process;
  ----------------------------------------------------------------------------

  ----------------------------------------------------------------------------
  -- FTDI Bridge packet dispatcher FSM 
  ftdi_bridge : process (reset_n, ft_clock)
    variable target : std_logic_vector(7 downto 0);

    function pack_word(buf : pkt_buf_t; widx : integer) return std_logic_vector is
      variable w : std_logic_vector(31 downto 0);
    begin
      w := buf(widx * 4 + 3) & buf(widx * 4 + 2) & buf(widx * 4 + 1) & buf(widx * 4);
      return w;
    end function;

    procedure set_word(buf : inout pkt_buf_t; widx : integer; w : std_logic_vector(31 downto 0)) is
    begin
      buf(widx * 4)     <= w(7 downto 0);
      buf(widx * 4 + 1) <= w(15 downto 8);
      buf(widx * 4 + 2) <= w(23 downto 16);
      buf(widx * 4 + 3) <= w(31 downto 24);
    end procedure;
  begin
    if (reset_n = '0') then
      mode           <= CTRL_RX;
      pkt_count      <= 0;
      push_word_idx  <= 0;
      pop_word_idx   <= 0;
      resp_count     <= 0;
      tx_countdown   <= (others => '0');
      req_wrreq      <= '0';
      req_data_in    <= (others => '0');
      resp_rdreq     <= '0';
      ftdi_tx_valid  <= '0';
      ftdi_tx_data   <= (others => '0');
      ftdi_rx_ready  <= '0';
      dvbt2_rx_valid <= '0';
      dvbt2_rx_data  <= (others => '0');
    elsif (rising_edge(ft_clock)) then
      req_wrreq      <= '0';
      resp_rdreq     <= '0';
      ftdi_tx_valid  <= '0';
      ftdi_rx_ready  <= '0';
      dvbt2_rx_valid <= '0';

      case mode is
          -- CTRL_RX
        when CTRL_RX =>
          ftdi_rx_ready <= not req_wrfull;
          if (ftdi_rx_ready = '1' and ftdi_rx_valid = '1') then
            pkt_buf(pkt_count) <= ftdi_rx_data;
            pkt_count          <= pkt_count + 1;

            if (pkt_count = 15) then
              target := pkt_buf(1);
              if (target = x"80") then
                tx_countdown <= pkt_buf(13) & pkt_buf(12) & pkt_buf(11) & pkt_buf(10) & pkt_buf(9) & pkt_buf(8) & pkt_buf(7) & pkt_buf(6);

                -- Build ACK package for tx_start response
                for i in 0 to 15 loop
                  ack_buf(i) <= (others => '0');
                end loop;

                ack_buf(0) <= x"45";
                ack_buf(1) <= x"80";
                ack_buf(2) <= x"02";

                for i in 0 to 7 loop
                  ack_buf(i + 6) <= pkt_buf(i + 6);
                end loop;

                resp_count <= 0;
                mode       <= TX_ACK;
              else
                push_word_idx <= 0;
                mode          <= CTRL_PUSH_WORDS;
              end if;

              pkt_count <= 0;
            end if;
          end if;

          --CTRL_PUSH_WORDS
        when CTRL_PUSH_WORDS =>
          if (req_wrfull = '0') then
            req_wrreq   <= '1';
            req_data_in <= pack_word(pkt_buf, push_word_idx);
            if (push_word_idx = 3) then
              mode <= CTRL_WAIT_RESP;
            else
              push_word_idx <= push_word_idx + 1;
            end if;
          end if;

          -- CTRL_WAIT_RESP
        when CTRL_WAIT_RESP =>
          ftdi_rx_ready <= '0';
          -- Wait until resp fifo has >= 16 optional then start TX
          if (unsigned(resp_rdusedw) >= 4) then
            pop_word_idx <= 0;
            mode         <= CTRL_POP_WORDS;
          end if;

          -- CTRL_POP_WORDS
        when CTRL_POP_WORDS =>
          if (resp_rdempty = '0') then
            resp_rdreq <= '1';
            set_word(resp_buf, pop_word_idx, resp_q);
            if (pop_word_idx = 3) then
              resp_count <= 0;
              mode       <= CTRL_TX_BYTES;
            else
              pop_word_idx <= pop_word_idx + 1;
            end if;
          end if;

          -- CTRL_TX_BYTES
        when CTRL_TX_BYTES =>
          ftdi_rx_ready <= '0';
          if (ftdi_tx_ready = '1') then
            ftdi_tx_valid <= '1';
            ftdi_tx_data  <= resp_buf(resp_count);
            if (resp_count = 15) then
              mode <= CTRL_RX;
            else
              resp_count <= resp_count + 1;
            end if;
          end if;

          -- TX_ACK
        when TX_ACK =>
          ftdi_rx_ready <= '0';
          if (ftdi_tx_ready = '1') then
            ftdi_tx_valid <= '1';
            ftdi_tx_data  <= ack_buf(resp_count);
            if (resp_count = 15) then
              mode <= DATA_FWD;
            else
              resp_count <= resp_count + 1;
            end if;
          end if;

          -- DATA_FWD
        when DATA_FWD =>
          -- forward raw bytes to DVB-T2 FIFO
          ftdi_rx_ready <= dvbt2_rx_ready;
          if (ftdi_rx_valid = '1' and ftdi_rx_ready = '1') then
            dvbt2_rx_data  <= ftdi_rx_data;
            dvbt2_rx_valid <= '1';
            if (tx_countdown /= 0) then
              tx_countdown <= tx_countdown - 1;
              if (tx_countdown = 1) then
                mode <= CTRL_RX;
              end if;
            else
              mode <= CTRL_RX;
            end if;
          end if;

        when others =>
      end case;
    end if;

  end process;
  ----------------------------------------------------------------------------

end internal;
